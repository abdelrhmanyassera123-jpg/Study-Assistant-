import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/summarize/summarizer.dart';
import 'package:study_assistant/models/models.dart';

ScheduleEntry lecture({
  int weekday = 1,
  int start = 10 * 60,
  int? remind,
}) =>
    ScheduleEntry(
      id: 'e1',
      title: 'فيزياء 2',
      weekday: weekday,
      startMinutes: start,
      remindMinutes: remind,
      createdAt: DateTime(2026),
    );

void main() {
  group('next occurrence', () {
    // الاتنين الساعة 10، والوقت دلوقتي الاتنين 8 الصبح.
    // Monday at ten, with now being Monday morning at eight.
    test('later today is today', () {
      final now = DateTime(2026, 9, 7, 8); // الاتنين / a Monday
      final when = lecture(weekday: 1, start: 10 * 60).nextOccurrence(now);

      expect(when, DateTime(2026, 9, 7, 10));
    });

    // المحاضرة اللي فاتت النهاردة معادها لازم ترجّع الأسبوع الجاي، وإلا التنبيه
    // بيتحسب على وقت عدّى ويفضل "مستحق" على طول.
    // A lecture whose time has passed today must return next week, otherwise the
    // reminder is computed against a moment gone by and stays permanently due.
    test('already passed today rolls to next week', () {
      final now = DateTime(2026, 9, 7, 11);
      final when = lecture(weekday: 1, start: 10 * 60).nextOccurrence(now);

      expect(when, DateTime(2026, 9, 14, 10));
    });

    test('a later day this week is this week', () {
      final now = DateTime(2026, 9, 7, 11); // الاتنين / Monday
      final when = lecture(weekday: 4, start: 9 * 60).nextOccurrence(now);

      expect(when, DateTime(2026, 9, 10, 9)); // الخميس / Thursday
    });

    test('an earlier day in the week goes round to the next one', () {
      final now = DateTime(2026, 9, 10, 11); // الخميس / Thursday
      final when = lecture(weekday: 6, start: 9 * 60).nextOccurrence(now);

      expect(when, DateTime(2026, 9, 12, 9)); // السبت / Saturday
    });

    test('exactly now counts as gone, not as due', () {
      final now = DateTime(2026, 9, 7, 10);
      final when = lecture(weekday: 1, start: 10 * 60).nextOccurrence(now);

      expect(when, DateTime(2026, 9, 14, 10));
    });
  });

  group('reminders', () {
    test('are off when no lead time is set', () {
      expect(lecture().remindersOn, isFalse);
      expect(lecture(remind: 15).remindersOn, isTrue);
    });
  });

  group('merged timetables', () {
    ParsedLecture at(String group) => ParsedLecture(
          title: 'مادة',
          weekday: 6,
          startMinutes: 9 * 60,
          group: group,
        );

    // ده الشكل الحقيقي لجدول كلية: نفس الفترة فيها محاضرة لكل شعبة في قاعة
    // مختلفة. اللي بياخدهم كلهم بيلاقي نفسه في تلات قاعات في نفس الوقت.
    // This is what a college timetable really looks like: the same slot holds a
    // lecture for each section in a different room. Taking them all puts you in
    // three rooms at once.
    test('one section keeps its own lectures only', () {
      final schedule = ParsedSchedule(
        entries: [at('شعبة أ'), at('شعبة ب'), at('شعبة ج')],
        groups: const ['شعبة أ', 'شعبة ب', 'شعبة ج'],
      );

      expect(schedule.forGroup('شعبة ب'), hasLength(1));
      expect(schedule.forGroup('شعبة ب').single.group, 'شعبة ب');
    });

    // المحاضرة العامة مالهاش قسم، ولازم تفضل مع أي اختيار — وإلا الطالب
    // بيروح الكلية ويلاقي محاضرة مش في جدوله.
    // A general lecture has no section and must survive any choice; otherwise
    // the student turns up to find a lecture missing from their timetable.
    test('a lecture for everyone stays whatever you pick', () {
      final schedule = ParsedSchedule(
        entries: [at('شعبة أ'), at('شعبة ب'), at('')],
        groups: const ['شعبة أ', 'شعبة ب'],
      );

      expect(schedule.forGroup('شعبة أ'), hasLength(2));
      expect(schedule.forGroup('شعبة ب'), hasLength(2));
    });

    test('picking nothing keeps the whole timetable', () {
      final schedule = ParsedSchedule(
        entries: [at('شعبة أ'), at('شعبة ب')],
        groups: const ['شعبة أ', 'شعبة ب'],
      );

      expect(schedule.forGroup(null), hasLength(2));
      expect(schedule.forGroup(''), hasLength(2));
    });

    // السؤال بيتسأل لما يبقى ليه معنى بس.
    // The question is asked only when it means something.
    test('one section or none is not worth asking about', () {
      expect(
        const ParsedSchedule(entries: []).needsChoice,
        isFalse,
      );
      expect(
        const ParsedSchedule(entries: [], groups: ['شعبة أ']).needsChoice,
        isFalse,
      );
      expect(
        const ParsedSchedule(entries: [], groups: ['أ', 'ب']).needsChoice,
        isTrue,
      );
    });

    // "ب" فيه عملي بيتقسم "ب-ج1" و"ب-ج2" بمعادين مختلفين — لازم الاتنين
    // يفضلوا شعب منفصلة تحت نفس القسم، مش شعب مستقلة زي أي حرف تاني.
    // "B" splits into a practical with two subgroups "B-C1"/"B-C2" on
    // different times — both must stay separate groups nested under the
    // same section, not standalone sections like any other letter.
    group('nested sections', () {
      test('subgroups are found under their main section', () {
        final schedule = ParsedSchedule(
          entries: [],
          groups: const ['أ', 'ب', 'ب-ج1', 'ب-ج2'],
        );

        expect(schedule.sections['أ'], isEmpty);
        expect(schedule.sections['ب'], unorderedEquals(['ج1', 'ج2']));
        expect(schedule.sections.containsKey('ب-ج1'), isFalse);
      });

      test('picking a subgroup keeps its own slot and the shared ones', () {
        final schedule = ParsedSchedule(
          entries: [
            at('ب'), // محاضرة نظرية للقسم كله / a lecture shared by the section
            at('ب-ج1'),
            at('ب-ج2'),
            at('أ-ج1'),
          ],
          groups: const ['أ-ج1', 'ب', 'ب-ج1', 'ب-ج2'],
        );

        final mine = schedule.forGroup('ب', 'ج1');
        expect(mine, hasLength(2));
        expect(mine.map((e) => e.group), containsAll(['ب', 'ب-ج1']));
      });

      test('picking only the section shows every subgroup inside it', () {
        final schedule = ParsedSchedule(
          entries: [at('ب'), at('ب-ج1'), at('ب-ج2'), at('أ-ج1')],
          groups: const ['أ-ج1', 'ب', 'ب-ج1', 'ب-ج2'],
        );

        expect(schedule.forGroup('ب'), hasLength(3));
      });
    });
  });

  group('reading a timetable', () {
    // الموديل بيرجّع أسماء أيام لأن الأرقام بيغلط فيها — الأسبوع بيبدأ السبت
    // عندنا والاتنين عنده.
    // The model returns day names because it gets numbers wrong: our week starts
    // on Saturday and its own starts on Monday.
    test('day names map to Flutter weekday numbers', () {
      expect(ParsedLecture.weekdayFromName('السبت'), 6);
      expect(ParsedLecture.weekdayFromName('الأحد'), 7);
      expect(ParsedLecture.weekdayFromName('الاثنين'), 1);
      expect(ParsedLecture.weekdayFromName('الاتنين'), 1);
      expect(ParsedLecture.weekdayFromName('Wednesday'), 3);
      expect(ParsedLecture.weekdayFromName('يوم الخميس'), 4);
    });

    test('an unknown day is refused rather than guessed', () {
      expect(ParsedLecture.weekdayFromName(''), isNull);
      expect(ParsedLecture.weekdayFromName('بكرة'), isNull);
    });

    test('clock times become minutes from midnight', () {
      expect(ParsedLecture.minutesFromClock('10:30'), 630);
      expect(ParsedLecture.minutesFromClock('09:00'), 540);
      expect(ParsedLecture.minutesFromClock('8'), 480);
    });

    test('afternoon markers move the hour', () {
      expect(ParsedLecture.minutesFromClock('2:00 pm'), 14 * 60);
      expect(ParsedLecture.minutesFromClock('2:00 م'), 14 * 60);
      expect(ParsedLecture.minutesFromClock('12:30 ص'), 30);
      expect(ParsedLecture.minutesFromClock('12:30 م'), 12 * 60 + 30);
    });

    test('nonsense times are refused', () {
      expect(ParsedLecture.minutesFromClock(''), isNull);
      expect(ParsedLecture.minutesFromClock('لسه'), isNull);
      expect(ParsedLecture.minutesFromClock('99:99'), isNull);
    });

    test('a row is read whole', () {
      final lecture = ParsedLecture.fromJson({
        'title': 'كيمياء عضوية',
        'day': 'الأربعاء',
        'start': '11:00',
        'end': '12:30',
        'location': 'مدرج 4',
        'lecturer': 'د. سمير',
      });

      expect(lecture, isNotNull);
      expect(lecture!.title, 'كيمياء عضوية');
      expect(lecture.weekday, 3);
      expect(lecture.startMinutes, 11 * 60);
      expect(lecture.endMinutes, 12 * 60 + 30);
      expect(lecture.location, 'مدرج 4');
      expect(lecture.lecturer, 'د. سمير');
      expect(lecture.group, '');
    });

    // صف ناقص بيتشال بدل ما يوقف الجدول كله: 12 محاضرة وواحدة مقروءة غلط
    // أنفع من رسالة خطأ.
    // An incomplete row is dropped rather than stopping the whole timetable:
    // twelve lectures with one misread beats an error message.
    test('a row without a day or a time is refused', () {
      expect(
        ParsedLecture.fromJson({'title': 'فيزياء', 'start': '10:00'}),
        isNull,
      );
      expect(
        ParsedLecture.fromJson({'title': 'فيزياء', 'day': 'السبت'}),
        isNull,
      );
      expect(
        ParsedLecture.fromJson({'day': 'السبت', 'start': '10:00'}),
        isNull,
      );
    });

    test('a section name is carried onto the lecture', () {
      final lecture = ParsedLecture.fromJson({
        'title': 'حاسب آلي',
        'day': 'الاثنين',
        'start': '10:00',
        'group': 'شعبة ب',
      });

      expect(lecture!.group, 'شعبة ب');
    });

    test('a missing end time is allowed', () {
      final lecture = ParsedLecture.fromJson({
        'title': 'رياضة',
        'day': 'السبت',
        'start': '09:00',
      });

      expect(lecture, isNotNull);
      expect(lecture!.endMinutes, isNull);
      expect(lecture.location, '');
    });
  });
}
