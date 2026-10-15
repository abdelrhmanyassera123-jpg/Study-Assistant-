import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant_app/digest.dart';
import 'package:study_assistant_app/table_image.dart';

// نفس حالات supabase/functions/_shared/today_digest_test.ts: الموبايل والسيرفر
// لازم يقولوا نفس الكلام.
// The same cases as supabase/functions/_shared/today_digest_test.ts: the
// phone and the server must say the same thing.
const day = [
  Lecture(id: 'b', title: 'فسيولوجي', location: 'مدرج 2', weekday: 4, startMinutes: 720, endMinutes: 810),
  Lecture(id: 'a', title: 'تشريح', location: 'قاعة 5', sessionType: 'سكشن', weekday: 4, startMinutes: 540, endMinutes: 630),
  Lecture(id: 'c', title: 'كيمياء', location: '', weekday: 4, startMinutes: 840),
];

void main() {
  test('the day changes at the morning and at every start and end, not after the last', () {
    final moments = digestMoments(day, morningMinutes: 420);
    expect(moments.map((m) => m.minutes), [420, 540, 630, 720, 810, 840]);
    expect(moments.last.until, 840 + defaultLengthMinutes);
    expect(moments.first.until, 540);
  });

  test('the morning names the first lecture', () {
    final v = digestView(day, 420);
    expect(v.title, 'محاضرات النهاردة: 3');
    expect(v.body, 'أولها 9:00 ص · تشريح — سكشن · قاعة 5');
    expect(v.rows.map((r) => r.state), [RowState.next, RowState.later, RowState.later]);
  });

  test('a lecture under way leads, with when it ends and what follows', () {
    final v = digestView(day, 730);
    expect(v.title, '▶ فسيولوجي');
    expect(v.body, 'دلوقتي لحد 1:30 م · مدرج 2 · بعدها 2:00 م');
    expect(v.rows.map((r) => r.state), [RowState.done, RowState.now, RowState.later]);
  });

  test('a break points to the next lecture', () {
    final v = digestView(day, 660);
    expect(v.title, 'الجاية: فسيولوجي');
    expect(v.body, 'الساعة 12:00 م · مدرج 2 · فاضل 2');
  });

  test('an early first lecture brings the morning forward', () {
    const early = [Lecture(id: 'x', title: 'باكر', location: '', weekday: 1, startMinutes: 390, endMinutes: 480)];
    expect(digestMoments(early, morningMinutes: 420).map((m) => m.minutes), [390]);
  });

  test('a day off has no notification', () {
    expect(digestMoments(const [], morningMinutes: 420), isEmpty);
  });

  test('the clock reads in 12 hours', () {
    expect(clock(0), '12:00 ص');
    expect(clock(725), '12:05 م');
  });

  testWidgets('the table draws into a PNG', (tester) async {
    final png = await tester.runAsync(() => drawTable(digestView(day, 730).rows));
    expect(png, isNotNull);
    expect(png!.sublist(1, 4), [0x50, 0x4E, 0x47]); // "PNG"
  });
}
