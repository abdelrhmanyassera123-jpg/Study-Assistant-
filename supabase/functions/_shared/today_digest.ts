// =====================================================================
// إشعار "محاضرات النهاردة" — إشعار واحد بيفضل موجود طول اليوم
// The "today's lectures" notification — one notification kept all day
// =====================================================================
// بيوصل أول اليوم، وبيتحدّث من غير صوت كل ما محاضرة تبدأ (فيفضل فيه اللي
// فاضل بس)، وبيختفي بعد آخر محاضرة. كله نفس الـ tag، فكل تحديث بيحل محل
// اللي قبله بدل ما يتراكموا.
//
// It arrives at the start of the day, updates silently whenever a lecture
// starts (so it only ever lists what is left), and disappears after the
// last lecture. All of it shares one tag, so each update replaces the last
// instead of piling up.
//
// المنطق هنا من غير شبكة ولا وقت حقيقي عشان يتختبر لوحده.
// The logic here touches neither the network nor the real clock, so it can
// be tested on its own.
// =====================================================================

export const DIGEST_TAG = "today-schedule";

/// المحاضرة اللي مالهاش ميعاد نهاية بتتحسب ساعة ونص.
/// A lecture with no end time counts as an hour and a half.
const DEFAULT_LENGTH_MINUTES = 90;

/// لو آخر محاضرة خلصت من أكتر من كده والإشعار ما اتقفلش، خلاص فات الأوان —
/// مش هنبعت "اقفل" لإشعار غالبًا اتشال.
/// If the last lecture ended longer ago than this and the notification was
/// never closed, it is too late: no "close" for one that is likely gone.
const CLOSE_GRACE_MINUTES = 30;

export interface DigestEntry {
  id: string;
  title: string;
  location: string;
  session_type?: string | null;
  start_minutes: number;
  end_minutes: number | null;
}

export interface DigestPush {
  title: string;
  body: string;
  tag: string;
  silent: boolean;
  renotify: boolean;
  url: string;
  close?: boolean;
  /// صفوف الجدول اللي بيترسم صورة لما الإشعار يتفتح (web/pwa-sw.js).
  /// The table rows drawn as a picture when the notification is expanded
  /// (web/pwa-sw.js).
  table?: DigestRow[];
}

export interface DigestRow {
  start: string;
  end: string;
  title: string;
  room: string;
  /// خلصت، شغالة، الجاية، أو بعد كده.
  /// Over, under way, up next, or later.
  state: "done" | "now" | "next" | "later";
}

export interface DigestEvent {
  /// مفتاح الحدث في اليوم — بيتحجز مرة واحدة عشان ما يتبعتش مرتين.
  /// The event's key within the day, claimed once so it is never sent twice.
  key: string;
  push: DigestPush;
}

export function endOf(entry: DigestEntry): number {
  return entry.end_minutes ?? entry.start_minutes + DEFAULT_LENGTH_MINUTES;
}

/// الحدث المستحق دلوقتي لمحاضرات النهاردة، أو null لو مفيش.
/// The event due now for today's lectures, or null when there is none.
///
/// مش "اللي ميعاده الدقيقة دي بالظبط": لو نداء الكرون فات دقيقة، الحدث
/// اللي بعده بيلاقي الحالة الصح برضه. الحجز هو اللي بيمنع التكرار.
/// Not "whatever falls on this exact minute": if a cron tick was missed, the
/// next one still finds the right state. The claim is what prevents repeats.
export function digestEvent(
  entries: DigestEntry[],
  nowMinutes: number,
  morningMinutes: number,
): DigestEvent | null {
  if (entries.length === 0) return null;
  const list = [...entries].sort((a, b) => a.start_minutes - b.start_minutes);

  const lastEnd = Math.max(...list.map(endOf));
  // لو أول محاضرة قبل ميعاد الإشعار المعتاد، الإشعار بيوصل معاها.
  // If the first lecture is before the usual time, the notification comes
  // with it.
  const morning = Math.min(morningMinutes, list[0].start_minutes);

  if (nowMinutes < morning) return null;

  if (nowMinutes >= lastEnd) {
    if (nowMinutes - lastEnd > CLOSE_GRACE_MINUTES) return null;
    return {
      key: "end",
      push: {
        title: "",
        body: "",
        tag: DIGEST_TAG,
        silent: true,
        renotify: false,
        url: "./",
        close: true,
      },
    };
  }

  // آخر حد اتعدّى: بداية محاضرة أو نهايتها. النهاية مهمة كمان عشان في
  // البريك بين محاضرتين الإشعار يقول "الجاية" مش "دلوقتي" لحاجة خلصت.
  // The latest boundary passed: a lecture's start or its end. The end
  // matters too, so in a break between two lectures it says "next" rather
  // than "now" for one already over.
  let key = "morning";
  let at = -1;
  for (const e of list) {
    // محاضرة بتبدأ في نفس دقيقة نهاية اللي قبلها بتكسب: هي اللي شغالة.
    // A lecture starting the minute the last one ends wins: it is under way.
    if (e.start_minutes <= nowMinutes && e.start_minutes >= at) {
      at = e.start_minutes;
      key = `start:${e.id}`;
    }
    if (endOf(e) <= nowMinutes && endOf(e) > at) {
      at = endOf(e);
      key = `end:${e.id}`;
    }
  }
  return { key, push: digestPush(list, nowMinutes) };
}

/// محتوى الإشعار. وهو مقفول بيبان سطرين بس، فهما للحاجة الوحيدة اللي محتاج
/// تعرفها دلوقتي: اللي شغالة أو الجاية، ولحد إمتى، وفين. لما يتفتح، اليوم
/// كله بيظهر جدول مرسوم (table) — اللي خلص باهت واللي شغال متلوّن.
/// The notification's content. Collapsed it shows two lines only, so they
/// hold the one thing needed right now: what is under way or next, until
/// when, and where. Expanded, the whole day shows as a drawn table (table):
/// what is over faded, what is under way highlighted.
export function digestPush(entries: DigestEntry[], nowMinutes: number): DigestPush {
  const list = [...entries].sort((a, b) => a.start_minutes - b.start_minutes);
  const current = list.find((e) => e.start_minutes <= nowMinutes && endOf(e) > nowMinutes);
  const upcoming = list.filter((e) => e.start_minutes > nowMinutes);
  const next = upcoming[0];
  const left = list.filter((e) => endOf(e) > nowMinutes).length;

  const name = (e: DigestEntry) =>
    [e.title.trim(), (e.session_type ?? "").trim()].filter(Boolean).join(" — ");
  const room = (e: DigestEntry) => e.location.trim();
  const parts = (...p: string[]) => p.filter(Boolean).join(" · ");

  let title: string;
  let body: string;
  if (current) {
    title = `▶ ${name(current)}`;
    body = parts(
      `دلوقتي لحد ${clock(endOf(current))}`,
      room(current),
      next ? `بعدها ${clock(next.start_minutes)}` : "آخر محاضرة",
    );
  } else if (next) {
    const morning = upcoming.length === list.length;
    title = morning ? `محاضرات النهاردة: ${list.length}` : `الجاية: ${name(next)}`;
    body = morning
      ? parts(`أولها ${clock(next.start_minutes)}`, name(next), room(next))
      : parts(`الساعة ${clock(next.start_minutes)}`, room(next), `فاضل ${left}`);
  } else {
    title = "خلصت محاضرات النهاردة";
    body = "";
  }

  const highlight = current ?? next;
  const table: DigestRow[] = list.map((e) => ({
    start: clock(e.start_minutes),
    end: clock(endOf(e)),
    title: name(e),
    room: room(e),
    state: endOf(e) <= nowMinutes
      ? "done"
      : e === current
      ? "now"
      : e === highlight
      ? "next"
      : "later",
  }));

  return {
    title,
    body,
    tag: DIGEST_TAG,
    // إشعار معلومة مش منبّه: من غير صوت، والتحديث بيحل محل القديم بهدوء.
    // Information, not an alarm: no sound, and each update quietly replaces
    // the last.
    silent: true,
    renotify: false,
    url: "./?open=schedule",
    table,
  };
}

/// ساعة بنظام 12 بالعربي: 9:30 ص، 1:05 م.
/// A 12-hour Arabic clock: 9:30 ص, 1:05 م.
export function clock(minutes: number): string {
  const h24 = Math.floor(minutes / 60) % 24;
  const m = minutes % 60;
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  return `${h12}:${String(m).padStart(2, "0")} ${h24 < 12 ? "ص" : "م"}`;
}
