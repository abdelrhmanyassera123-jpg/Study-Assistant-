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
// الفنكشن دي منشورة بـ --no-verify-jwt: مفيش مستخدم بينادي عليها، الكرون
// نفسه هو اللي بينادي، فالتحقق بيبقى بمقارنة هيدر "x-cron-secret" بسر مخزّن
// كإعداد على مستوى الداتابيز (شوف الـ migration).
//
// Deployed with --no-verify-jwt: no user calls this, only the cron job does,
// so the check is comparing the "x-cron-secret" header against a secret
// stored as a database-level setting (see the migration).
// =====================================================================

const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY") ?? "";
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY") ?? "";
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") ?? "mailto:support@studyassistant.app";

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

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== CRON_SECRET || !CRON_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
    return new Response("missing configuration", { status: 500 });
  }

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

  for (const { entry, occurrenceAt } of due) {
    const claimed = await claimReminder(entry.id, occurrenceAt);
    if (!claimed) continue; // already sent by an earlier tick

    const subs = await fetchSubscriptions(entry.user_id);
    if (subs.length === 0) continue;

    const minutesLeft = entry.remind_minutes;
    const body = entry.location.trim()
      ? `${reminderBody(minutesLeft)} · ${entry.location.trim()}`
      : reminderBody(minutesLeft);

    for (const sub of subs) {
      try {
        await sendWebPush(sub, {
          title: entry.title,
          body,
          tag: entry.id,
        });
        sent++;
      } catch (err) {
        errors++;
        if (err instanceof PushGoneError) {
          await deleteSubscription(sub.id);
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
});

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
    `${SUPABASE_URL}/rest/v1/schedule_entries?select=id,user_id,title,location,weekday,start_minutes,remind_minutes&remind_minutes=not.is.null`,
    { headers: restHeaders() },
  );
  if (!res.ok) {
    console.error("fetchDueEntries failed", res.status, await res.text());
    return [];
  }
  return await res.json();
}

async function fetchSubscriptions(userId: string): Promise<PushSubscriptionRow[]> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/push_subscriptions?select=id,endpoint,p256dh,auth&user_id=eq.${userId}`,
    { headers: restHeaders() },
  );
  if (!res.ok) return [];
  return await res.json();
}

async function deleteSubscription(id: string): Promise<void> {
  await fetch(`${SUPABASE_URL}/rest/v1/push_subscriptions?id=eq.${id}`, {
    method: "DELETE",
    headers: restHeaders(),
  });
}

/// بيحاول "يحجز" إرسال التنبيه ده — لو صف اتحط بالفعل (نداء تاني لقاه)، السطر
/// ده بيرجّع false ومفيش إرسال تاني.
/// Tries to "claim" sending this reminder — if the row is already there (an
/// earlier tick claimed it), this returns false and nothing is sent again.
async function claimReminder(entryId: string, occurrenceAt: string): Promise<boolean> {
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/push_reminders_sent?on_conflict=entry_id,occurrence_at`,
    {
      method: "POST",
      headers: {
        ...restHeaders(),
        Prefer: "resolution=ignore-duplicates,return=representation",
      },
      body: JSON.stringify([{ entry_id: entryId, occurrence_at: occurrenceAt }]),
    },
  );
  if (!res.ok) {
    console.error("claimReminder failed", res.status, await res.text());
    return false;
  }
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

// =====================================================================
// Web Push — تشفير الرسالة وتوقيع VAPID (RFC 8291 / 8188 / 8292)
// Web Push — message encryption and VAPID signing (RFC 8291 / 8188 / 8292)
// =====================================================================

class PushGoneError extends Error {}

async function sendWebPush(
  sub: PushSubscriptionRow,
  payload: { title: string; body: string; tag: string },
): Promise<void> {
  const endpointOrigin = new URL(sub.endpoint).origin;
  const vapidHeader = await buildVapidHeader(endpointOrigin);
  const body = await encryptPayload(sub.p256dh, sub.auth, JSON.stringify(payload));

  const res = await fetch(sub.endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/octet-stream",
      "Content-Encoding": "aes128gcm",
      TTL: "300",
      Authorization: vapidHeader,
    },
    body,
  });

  if (res.status === 404 || res.status === 410) {
    throw new PushGoneError(`subscription gone (${res.status})`);
  }
  if (!res.ok) {
    throw new Error(`push service responded ${res.status}: ${await res.text()}`);
  }
}

async function buildVapidHeader(audience: string): Promise<string> {
  const header = b64url(new TextEncoder().encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const payload = b64url(new TextEncoder().encode(JSON.stringify({
    aud: audience,
    exp: Math.floor(Date.now() / 1000) + 12 * 3600,
    sub: VAPID_SUBJECT,
  })));
  const signingInput = `${header}.${payload}`;

  const privateKey = await crypto.subtle.importKey(
    "jwk",
    vapidPrivateJwk(),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(signingInput),
  );

  const jwt = `${signingInput}.${b64url(new Uint8Array(signature))}`;
  return `vapid t=${jwt}, k=${VAPID_PUBLIC_KEY}`;
}

/// بيحوّل المفتاح الخاص الخام (32 بايت) لصيغة JWK عشان SubtleCrypto يقدر
/// يستورده — المفتاح العام مشتق من نفس نقطة EC المخزّنة في VAPID_PUBLIC_KEY.
/// Turns the raw private scalar (32 bytes) into JWK form so SubtleCrypto can
/// import it — the public key is the same EC point stored in
/// VAPID_PUBLIC_KEY.
function vapidPrivateJwk(): JsonWebKey {
  const pub = b64urlDecode(VAPID_PUBLIC_KEY); // 0x04 || X(32) || Y(32)
  const x = pub.slice(1, 33);
  const y = pub.slice(33, 65);
  const d = b64urlDecode(VAPID_PRIVATE_KEY);
  return {
    kty: "EC",
    crv: "P-256",
    x: b64url(x),
    y: b64url(y),
    d: b64url(d),
    ext: true,
  };
}

/// تشفير الحمولة حسب RFC 8291 (aes128gcm واحدة، مفيش padding زيادة).
/// Encrypts the payload per RFC 8291 (a single aes128gcm record, no extra
/// padding).
async function encryptPayload(
  p256dhB64: string,
  authB64: string,
  plaintext: string,
): Promise<Uint8Array> {
  const uaPublicRaw = b64urlDecode(p256dhB64); // 65 bytes
  const authSecret = b64urlDecode(authB64); // 16 bytes

  const serverKeyPair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true,
    ["deriveBits"],
  );
  const asPublicRaw = new Uint8Array(
    await crypto.subtle.exportKey("raw", serverKeyPair.publicKey),
  );

  const uaPublicKey = await crypto.subtle.importKey(
    "raw",
    uaPublicRaw,
    { name: "ECDH", namedCurve: "P-256" },
    false,
    [],
  );
  const sharedSecret = new Uint8Array(
    await crypto.subtle.deriveBits(
      { name: "ECDH", public: uaPublicKey },
      serverKeyPair.privateKey,
      256,
    ),
  );

  const prkKey = await hmacSha256(authSecret, sharedSecret);
  const keyInfo = concatBytes([
    new TextEncoder().encode("WebPush: info"),
    new Uint8Array([0]),
    uaPublicRaw,
    asPublicRaw,
  ]);
  const ikm = (await hmacSha256(prkKey, concatBytes([keyInfo, new Uint8Array([1])])))
    .slice(0, 32);

  const salt = crypto.getRandomValues(new Uint8Array(16));
  const prk = await hmacSha256(salt, ikm);

  const cekInfo = concatBytes([
    new TextEncoder().encode("Content-Encoding: aes128gcm"),
    new Uint8Array([0]),
  ]);
  const cek = (await hmacSha256(prk, concatBytes([cekInfo, new Uint8Array([1])]))).slice(0, 16);

  const nonceInfo = concatBytes([
    new TextEncoder().encode("Content-Encoding: nonce"),
    new Uint8Array([0]),
  ]);
  const nonce = (await hmacSha256(prk, concatBytes([nonceInfo, new Uint8Array([1])]))).slice(0, 12);

  const recordPlain = concatBytes([new TextEncoder().encode(plaintext), new Uint8Array([2])]);
  const cekKey = await crypto.subtle.importKey("raw", cek, { name: "AES-GCM" }, false, ["encrypt"]);
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, cekKey, recordPlain),
  );

  const recordSize = new Uint8Array(4);
  new DataView(recordSize.buffer).setUint32(0, 4096, false);

  return concatBytes([
    salt,
    recordSize,
    new Uint8Array([asPublicRaw.length]),
    asPublicRaw,
    ciphertext,
  ]);
}

async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, data));
}

function concatBytes(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((n, c) => n + c.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

function b64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecode(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
    .padEnd(value.length + ((4 - (value.length % 4)) % 4), "=");
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}
