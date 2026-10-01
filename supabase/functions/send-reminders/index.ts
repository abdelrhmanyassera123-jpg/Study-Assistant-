// =====================================================================
// send-reminders — بيبعت تنبيهات Push قبل كل محاضرة
// =====================================================================
// بتتنادى كل دقيقة من مهمة مجدولة (pg_cron، شوف migration
// 20260915000100_reminder_cron.sql) بدل ما المتصفح نفسه يبقى مسؤول عن
// التنبيه — عشان التنبيه يوصل حتى لو التطبيق مقفول خالص، مش بس تاب مفتوح.
//
// Called every minute by a scheduled job (pg_cron — see migration
// 20260915000100_reminder_cron.sql) instead of the browser being the one
// responsible for the reminder — so it arrives even with the app fully
// closed, not just a background tab.
//
// الفنكشن دي منشورة بـ --no-verify-jwt ومسارين بيوصلولها:
//  • الكرون: هيدر "x-cron-secret" بيتقارن بسر مخزّن في Supabase Vault (شوف
//    الـ migration) — ده اللي بيمسح الجدول ويبعت أي تنبيه مستحق.
//  • زرار "جرّب الإشعار" في التطبيق: طلب فيه Authorization بتاع المستخدم
//    نفسه، وبيبعت له بس تنبيه تجربة على اشتراكاته.
//
// Deployed with --no-verify-jwt, with two paths reaching it:
//  • The cron: an "x-cron-secret" header checked against a secret stored in
//    Supabase Vault (see the migration) — this is what scans the table and
//    sends any due reminder.
//  • The "test notification" button in the app: a request carrying the
//    user's own Authorization, which only gets a test push on their own
//    subscriptions.
// =====================================================================

import { PushGoneError, sendWebPush } from "../_shared/webpush.ts";

const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";

// الجدول بيتكرر أسبوعيًا بتوقيت القاهرة المحلي — نفس افتراض التطبيق نفسه لما
// بيحسب next occurrence على جهاز المستخدم.
// The timetable repeats weekly in Cairo local time — the same assumption the
// app itself makes when it computes the next occurrence on the user's device.
const TIMEZONE = Deno.env.get("REMINDER_TIMEZONE") ?? "Africa/Cairo";

interface ScheduleEntryRow {
  id: string;
  user_id: string;
  title: string;
  location: string;
  lecturer: string;
  weekday: number; // 1 = Monday ... 7 = Sunday
  start_minutes: number;
  remind_minutes: number;
}

interface PushSubscriptionRow {
  id: string;
  endpoint: string;
  p256dh: string;
  auth: string;
}

interface NotificationPrefsRow {
  sound_on: boolean;
  vibrate_on: boolean;
  custom_body: string | null;
  default_remind_minutes: number;
}

const DEFAULT_PREFS: NotificationPrefsRow = {
  sound_on: true,
  vibrate_on: true,
  custom_body: null,
  default_remind_minutes: 10,
};

// الكرون بس هو اللي بينادي بدون CORS (سيرفر لسيرفر)، لكن زرار "جرّب
// الإشعار" جاي من المتصفح — لازم preflight ورد فيه CORS headers، وإلا
// المتصفح بيمنع الطلب قبل ما يوصل هنا خالص ويطلع خطأ عام مش واضح سببه.
// Only the cron calls this without CORS (server-to-server), but the "test
// notification" button comes from the browser — it needs a preflight and a
// response carrying CORS headers, or the browser blocks the request before
// it ever reaches here and surfaces an unhelpful generic error.
const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function withCors(res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(CORS_HEADERS)) headers.set(k, v);
  return new Response(res.body, { status: res.status, headers });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    return withCors(new Response("missing configuration", { status: 500 }));
  }

  if (CRON_SECRET && req.headers.get("x-cron-secret") === CRON_SECRET) {
    return withCors(await handleCronTick());
  }

  const auth = req.headers.get("Authorization");
  if (auth) {
    return withCors(await handleTestPush(auth));
  }

  return withCors(new Response("unauthorized", { status: 401 }));
});

/// المسار المجدول: بيدوّر على أي محاضرة مستحق ليها تنبيه دلوقتي ويبعته.
/// The scheduled path: scans for any lecture due a reminder right now and
/// sends it.
async function handleCronTick(): Promise<Response> {
  const now = new Date();
  const { weekday: currentWeekday, minutes: currentMinutes, offsetMinutes } =
    cairoWallClock(now);

  const entries = await fetchDueEntries();
  const due = entries.filter((entry) => {
    const occurrence = nextOccurrenceUtc(
      entry.weekday,
      entry.start_minutes,
      currentWeekday,
      currentMinutes,
      offsetMinutes,
      now,
    );
    const fireAt = occurrence - entry.remind_minutes * 60_000;
    const diff = now.getTime() - fireAt;
    return diff >= 0 && diff < 60_000;
  }).map((entry) => ({
    entry,
    occurrenceAt: new Date(
      nextOccurrenceUtc(
        entry.weekday,
        entry.start_minutes,
        currentWeekday,
        currentMinutes,
        offsetMinutes,
        now,
      ),
    ).toISOString(),
  }));

  let sent = 0;
  let errors = 0;
  const prefsCache = new Map<string, NotificationPrefsRow>();

  for (const { entry, occurrenceAt } of due) {
    const claimed = await claimReminder(entry.id, occurrenceAt, entry.remind_minutes);
    if (!claimed) continue; // already sent by an earlier tick

    const subs = await fetchSubscriptionsAsService(entry.user_id);
    if (subs.length === 0) continue;

    if (!prefsCache.has(entry.user_id)) {
      prefsCache.set(entry.user_id, await fetchPrefsAsService(entry.user_id));
    }
    const prefs = prefsCache.get(entry.user_id)!;

    const body = applyTemplate(prefs.custom_body, {
      minutes: entry.remind_minutes,
      location: entry.location.trim(),
      lecture: entry.title,
      lecturer: (entry.lecturer ?? "").trim(),
    });

    for (const sub of subs) {
      try {
        await sendWebPush(sub, {
          title: entry.title,
          body,
          // مفتاح فريد لكل معاد، مش للمحاضرة نفسها بس — عشان لو نفس المحاضرة
          // بعتلها أكتر من تنبيه في يوم واحد (تجربة، أو تعديل الميعاد)، كل
          // واحد يظهر لوحده بدل ما يستبدل اللي قبله بصمت من غير تنبيه صوت
          // جديد.
          // A key unique per occurrence, not just per lecture — so if the
          // same lecture gets more than one push in a day (testing, or a
          // time edit), each shows on its own instead of silently replacing
          // the last one with no fresh alert.
          tag: `${entry.id}:${occurrenceAt}`,
          silent: !prefs.sound_on,
          vibrate: prefs.vibrate_on ? [200, 100, 200] : [],
          // زرار بيفتح التطبيق على شاشة التسجيل جاهزة باسم المحاضرة ومادتها،
          // ولما التسجيل يقف التلخيص بيكمّل لوحده على السيرفر.
          // A button that opens the app on the recorder, ready with the
          // lecture's name and subject; once recording stops, the summary
          // carries on by itself on the server.
          url: `./?record=${entry.id}`,
          actions: [{ action: "record", title: "ابدأ التسجيل", url: `./?record=${entry.id}` }],
        });
        sent++;
      } catch (err) {
        errors++;
        if (err instanceof PushGoneError) {
          await deleteSubscriptionAsService(sub.id);
        } else {
          console.error("push failed", entry.id, sub.id, err);
        }
      }
    }
  }

  return new Response(
    JSON.stringify({ checked: entries.length, due: due.length, sent, errors }),
    { headers: { "Content-Type": "application/json" } },
  );
}

/// زرار "جرّب الإشعار": بيبعت تنبيه تجربة بس على اشتراكات المستخدم اللي
/// بينادي، عن طريق RLS بمفتاح anon + الـ Authorization بتاعه — مفيش داعي
/// لـ service role هنا.
/// The "test notification" button: sends a test push only to the calling
/// user's own subscriptions, scoped by RLS via the anon key + their own
/// Authorization — no service role needed here.
async function handleTestPush(auth: string): Promise<Response> {
  const headers = { apikey: ANON_KEY, Authorization: auth };

  const [subsRes, prefsRes] = await Promise.all([
    fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?select=id,endpoint,p256dh,auth`, {
      headers,
    }),
    fetch(`${SUPABASE_URL}/rest/v1/notification_prefs?select=*`, { headers }),
  ]);

  if (!subsRes.ok) {
    return new Response(JSON.stringify({ sent: 0, error: "unauthorized" }), {
      status: subsRes.status === 401 ? 401 : 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const subs: PushSubscriptionRow[] = await subsRes.json();
  const prefsRows: NotificationPrefsRow[] = prefsRes.ok ? await prefsRes.json() : [];
  const prefs = prefsRows[0] ?? DEFAULT_PREFS;

  const body = applyTemplate(prefs.custom_body, {
    minutes: prefs.default_remind_minutes,
    location: "قاعة تجريبية",
    lecture: "محاضرة تجريبية",
    lecturer: "د. تجريبي",
  });

  let sent = 0;
  for (const sub of subs) {
    try {
      await sendWebPush(sub, {
        title: "محاضرة تجريبية",
        body,
        tag: `test:${Date.now()}`,
        silent: !prefs.sound_on,
        vibrate: prefs.vibrate_on ? [200, 100, 200] : [],
      });
      sent++;
    } catch (err) {
      if (err instanceof PushGoneError) {
        // مفيش service role هنا، فمينفعش نمسح الاشتراك — هيتلغي لوحده أول
        // تنبيه حقيقي جاي.
        // No service role here, so the subscription cannot be deleted — it
        // will be cleaned up on the next real reminder instead.
      } else {
        console.error("test push failed", sub.id, err);
      }
    }
  }

  return new Response(JSON.stringify({ sent, found: subs.length }), {
    headers: { "Content-Type": "application/json" },
  });
}

/// القالب المخصص لو موجود، وإلا الصيغة الافتراضية — نفس منطق
/// buildReminderBody في lib/core/notification_text.dart بالظبط.
/// The custom template when set, otherwise the default wording — mirrors
/// buildReminderBody in lib/core/notification_text.dart exactly.
function applyTemplate(
  custom: string | null | undefined,
  vars: { minutes: number; location: string; lecture: string; lecturer: string },
): string {
  const trimmed = custom?.trim();
  if (!trimmed) {
    return [reminderBody(vars.minutes), vars.location, vars.lecturer]
      .filter((part) => part)
      .join(" · ");
  }
  return trimmed
    .replaceAll("{minutes}", String(vars.minutes))
    .replaceAll("{location}", vars.location)
    .replaceAll("{lecture}", vars.lecture)
    .replaceAll("{lecturer}", vars.lecturer);
}

// =====================================================================
// الوقت — حساب "المحاضرة الجاية" بتوقيت القاهرة من غير مكتبة Temporal
// Time — working out "the next lecture" in Cairo time without a Temporal lib
// =====================================================================

/// بيرجّع يوم الأسبوع (1 اتنين .. 7 حد) والدقايق من نص الليل بتوقيت القاهرة
/// دلوقتي، وفرق التوقيت الحالي عن UTC بالدقايق.
/// Returns the weekday (1 Monday .. 7 Sunday) and minutes-since-midnight in
/// Cairo time right now, plus the current UTC offset in minutes.
function cairoWallClock(instant: Date) {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: TIMEZONE,
      hour12: false,
      weekday: "short",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    }).formatToParts(instant).map((p) => [p.type, p.value]),
  );

  const weekdayMap: Record<string, number> = {
    Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7,
  };

  const asUtcMs = Date.UTC(
    Number(parts.year),
    Number(parts.month) - 1,
    Number(parts.day),
    Number(parts.hour) === 24 ? 0 : Number(parts.hour),
    Number(parts.minute),
    Number(parts.second),
  );
  const offsetMinutes = Math.round((asUtcMs - instant.getTime()) / 60_000);

  return {
    weekday: weekdayMap[parts.weekday] ?? 1,
    minutes: (Number(parts.hour) === 24 ? 0 : Number(parts.hour)) * 60 + Number(parts.minute),
    offsetMinutes,
  };
}

/// نفس منطق `ScheduleEntry.nextOccurrence` في التطبيق، بس بتوقيت القاهرة
/// المحسوب من السيرفر بدل ساعة الجهاز.
/// Mirrors the app's `ScheduleEntry.nextOccurrence`, but using Cairo time
/// computed on the server instead of the device's clock.
function nextOccurrenceUtc(
  entryWeekday: number,
  entryStartMinutes: number,
  currentWeekday: number,
  currentMinutes: number,
  offsetMinutes: number,
  now: Date,
): number {
  let daysUntil = (entryWeekday - currentWeekday + 7) % 7;
  if (daysUntil === 0 && entryStartMinutes <= currentMinutes) daysUntil = 7;

  // "نص الليل بتوقيت القاهرة النهاردة" ممثّل كـ UTC field عشان نضيفله أيام
  // ودقايق بأمان من غير ما نتعامل مع منطقة زمنية فعلية.
  // "Midnight in Cairo today" represented as UTC fields so days and minutes
  // can be added safely without touching a real timezone.
  const todayCairoMidnightAsUtcFields = now.getTime() + offsetMinutes * 60_000;
  const todayStart = todayCairoMidnightAsUtcFields -
    (todayCairoMidnightAsUtcFields % 86_400_000);

  const occurrenceCairoWallMs = todayStart +
    daysUntil * 86_400_000 +
    entryStartMinutes * 60_000;

  return occurrenceCairoWallMs - offsetMinutes * 60_000;
}

function reminderBody(minutes: number): string {
  if (minutes <= 0) return "بدأت دلوقتي";
  if (minutes === 1) return "بعد دقيقة";
  if (minutes === 2) return "بعد دقيقتين";
  if (minutes <= 10) return `بعد ${minutes} دقايق`;
  return `بعد ${minutes} دقيقة`;
}

// =====================================================================
// Supabase REST — استعلامات بصلاحية service role
// Supabase REST — queries with service-role privilege
// =====================================================================

function restHeaders(): Record<string, string> {
  return {
    apikey: SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
    "Content-Type": "application/json",
  };
}

async function fetchDueEntries(): Promise<ScheduleEntryRow[]> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/schedule_entries?select=id,user_id,title,location,lecturer,weekday,start_minutes,remind_minutes&remind_minutes=not.is.null`,
    { headers: restHeaders() },
  );
  if (!res.ok) {
    console.error("fetchDueEntries failed", res.status, await res.text());
    return [];
  }
  return await res.json();
}

async function fetchSubscriptionsAsService(userId: string): Promise<PushSubscriptionRow[]> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/push_subscriptions?select=id,endpoint,p256dh,auth&user_id=eq.${userId}`,
    { headers: restHeaders() },
  );
  if (!res.ok) return [];
  return await res.json();
}

async function fetchPrefsAsService(userId: string): Promise<NotificationPrefsRow> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/notification_prefs?select=*&user_id=eq.${userId}`,
    { headers: restHeaders() },
  );
  if (!res.ok) return DEFAULT_PREFS;
  const rows: NotificationPrefsRow[] = await res.json();
  return rows[0] ?? DEFAULT_PREFS;
}

async function deleteSubscriptionAsService(id: string): Promise<void> {
  await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?id=eq.${id}`, {
    method: "DELETE",
    headers: restHeaders(),
  });
}

/// بيحاول "يحجز" إرسال التنبيه ده — لو صف اتحط بالفعل (نداء تاني لقاه)، السطر
/// ده بيرجّع false ومفيش إرسال تاني. مدة التنبيه جزء من مفتاح الحجز نفسه،
/// عشان لو المستخدم غيّرها بعد ما تنبيه النهاردة بعت خلاص، القيمة الجديدة
/// تقدر تبعت لوحدها من غير ما تتحجب.
/// Tries to "claim" sending this reminder — if the row is already there (an
/// earlier tick claimed it), this returns false and nothing is sent again.
/// The lead time is part of the claim key itself, so if the user changes it
/// after today's reminder already went out, the new value can still fire on
/// its own instead of being blocked.
async function claimReminder(
  entryId: string,
  occurrenceAt: string,
  remindMinutes: number,
): Promise<boolean> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/push_reminders_sent?on_conflict=entry_id,occurrence_at,remind_minutes`,
    {
      method: "POST",
      headers: {
        ...restHeaders(),
        Prefer: "resolution=ignore-duplicates,return=representation",
      },
      body: JSON.stringify([
        { entry_id: entryId, occurrence_at: occurrenceAt, remind_minutes: remindMinutes },
      ]),
    },
  );
  if (!res.ok) {
    console.error("claimReminder failed", res.status, await res.text());
    return false;
  }
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}
