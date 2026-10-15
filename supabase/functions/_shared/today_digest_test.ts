import { clock, DIGEST_TAG, digestEvent, type DigestEntry } from "./today_digest.ts";

// بيشتغل على Deno (deno test) وعلى Node 22+ (node today_digest_test.ts).
// Runs on Deno (deno test) and on Node 22+ (node today_digest_test.ts).
const register: (name: string, fn: () => void) => void =
  (globalThis as { Deno?: { test: (n: string, f: () => void) => void } }).Deno?.test ??
    ((name, fn) => {
      fn();
      console.log(`ok - ${name}`);
    });

function eq(a: unknown, b: unknown) {
  if (JSON.stringify(a) !== JSON.stringify(b)) {
    throw new Error(`expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
  }
}

const day: DigestEntry[] = [
  { id: "b", title: "فسيولوجي", location: "مدرج 2", start_minutes: 12 * 60, end_minutes: 13 * 60 + 30 },
  { id: "a", title: "تشريح", location: "قاعة 5", session_type: "سكشن", start_minutes: 9 * 60, end_minutes: 10 * 60 + 30 },
  { id: "c", title: "كيمياء", location: "", start_minutes: 14 * 60, end_minutes: null },
];

register("nothing before the morning time", () => {
  eq(digestEvent(day, 6 * 60 + 59, 7 * 60), null);
});

register("the morning lists the whole day, next lecture first", () => {
  const event = digestEvent(day, 7 * 60, 7 * 60)!;
  eq(event.key, "morning");
  eq(event.push.title, "محاضرات النهاردة (3)");
  eq(event.push.body.split("\n")[0], "9:00 ص–10:30 ص · تشريح — سكشن · قاعة 5");
  eq(event.push.body.split("\n").length, 3);
  eq(event.push.tag, DIGEST_TAG);
  eq(event.push.silent, true);
});

register("a lecture under way is marked and the finished one drops off", () => {
  const during = digestEvent(day, 12 * 60 + 10, 7 * 60)!;
  eq(during.key, "start:b");
  eq(during.push.title, "باقي النهاردة (2)");
  eq(during.push.body.split("\n")[0].startsWith("▶ دلوقتي: 12:00 م"), true);
  eq(during.push.body.includes("تشريح"), false);
});

register("a lecture with no end time is given an hour and a half", () => {
  const last = digestEvent(day, 14 * 60 + 5, 7 * 60)!;
  eq(last.push.title, "آخر محاضرة النهاردة");
  eq(last.push.body, "▶ دلوقتي: 2:00 م · كيمياء");
  eq(digestEvent(day, 15 * 60 + 29, 7 * 60)!.key, "start:c");
});

register("after the last lecture the notification closes, once, soon after", () => {
  const end = digestEvent(day, 15 * 60 + 30, 7 * 60)!;
  eq(end.key, "end");
  eq(end.push.close, true);
  eq(digestEvent(day, 16 * 60 + 1, 7 * 60), null);
});

register("an early first lecture brings the notification forward", () => {
  const early: DigestEntry[] = [{ id: "x", title: "باكر", location: "", start_minutes: 6 * 60 + 30, end_minutes: 8 * 60 }];
  eq(digestEvent(early, 6 * 60 + 30, 7 * 60)!.key, "start:x");
  eq(digestEvent(early, 6 * 60 + 29, 7 * 60), null);
});

register("a day off sends nothing", () => {
  eq(digestEvent([], 9 * 60, 7 * 60), null);
});

register("the clock reads in 12 hours", () => {
  eq(clock(0), "12:00 ص");
  eq(clock(12 * 60 + 5), "12:05 م");
  eq(clock(23 * 60 + 59), "11:59 م");
});
