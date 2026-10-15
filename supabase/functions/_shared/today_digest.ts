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

  const started = list.filter((e) => e.start_minutes <= nowMinutes);
  const key = started.length === 0 ? "morning" : `start:${started[started.length - 1].id}`;
  return { key, push: digestPush(list, nowMinutes) };
}

/// محتوى الإشعار: العنوان، وكل محاضرة فاضلة في سطر — السطر الأول هو اللي
/// بيبان والإشعار مقفول، فهو المحاضرة الجاية (أو اللي شغالة).
/// The notification's content: a title, and one line per lecture still to
/// come. The first line is what shows while it is collapsed, so it is the
/// next lecture (or the one under way).
export function digestPush(entries: DigestEntry[], nowMinutes: number): DigestPush {
  const left = entries
    .filter((e) => endOf(e) > nowMinutes)
    .sort((a, b) => a.start_minutes - b.start_minutes);
  const allToday = entries.length;

  const lines = left.map((e) => {
    const now = e.start_minutes <= nowMinutes;
    const what = [e.title.trim(), (e.session_type ?? "").trim()].filter(Boolean).join(" — ");
    const where = e.location.trim();
    const time = e.end_minutes == null
      ? clock(e.start_minutes)
      : `${clock(e.start_minutes)}–${clock(e.end_minutes)}`;
    return `${now ? "▶ دلوقتي: " : ""}${time} · ${what}${where ? ` · ${where}` : ""}`;
  });

  const title = left.length === allToday
    ? `محاضرات النهاردة (${allToday})`
    : left.length === 1
    ? "آخر محاضرة النهاردة"
    : `باقي النهاردة (${left.length})`;

  return {
    title,
    body: lines.join("\n"),
    tag: DIGEST_TAG,
    // إشعار معلومة مش منبّه: من غير صوت، والتحديث بيحل محل القديم بهدوء.
    // Information, not an alarm: no sound, and each update quietly replaces
    // the last.
    silent: true,
    renotify: false,
    url: "./?open=schedule",
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
