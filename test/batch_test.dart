import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/jobs/lecture_job.dart';
import 'package:study_assistant/models/models.dart';

ScheduleEntry _entry(String id, int weekday, int start, int? end, {String? subject}) =>
    ScheduleEntry(
      id: id,
      title: 'محاضرة $id',
      weekday: weekday,
      startMinutes: start,
      endMinutes: end,
      subjectId: subject,
      createdAt: DateTime(2026),
    );

BatchFile _file(String name, String mime, [DateTime? modified]) =>
    BatchFile(name: name, mimeType: mime, bytes: Uint8List(1), modified: modified);

void main() {
  // 2026-10-05 يوم اتنين.
  // 2026-10-05 is a Monday.
  final monday = DateTime(2026, 10, 5);
  final schedule = [
    _entry('anat', DateTime.monday, 9 * 60, 11 * 60, subject: 's-anat'),
    _entry('phys', DateTime.monday, 12 * 60, 13 * 60 + 30, subject: 's-phys'),
  ];

  group('lectureAt', () {
    test('a recording saved inside the lecture belongs to it', () {
      expect(lectureAt(monday.add(const Duration(hours: 10, minutes: 30)), schedule)?.id, 'anat');
    });

    test('a recording saved shortly after the end still belongs to it', () {
      expect(lectureAt(monday.add(const Duration(hours: 11, minutes: 30)), schedule)?.id, 'anat');
    });

    test('a file from another day matches nothing', () {
      expect(lectureAt(monday.add(const Duration(days: 1, hours: 10)), schedule), isNull);
    });

    test('no date, no match', () {
      expect(lectureAt(null, schedule), isNull);
    });
  });

  group('normalizeLectureName', () {
    test('drops extension, copy numbers and separators', () {
      expect(normalizeLectureName('Anatomy_Lec-3 (2).pdf'), 'anatomy lec 3');
    });
  });

  group('groupBatch', () {
    test('each audio file is its own lecture, slides follow their name', () {
      final groups = groupBatch([
        _file('anatomy lec3.m4a', 'audio/mp4'),
        _file('physiology lec1.m4a', 'audio/mp4'),
        _file('Anatomy Lec3.pdf', 'application/pdf'),
      ], schedule);

      expect(groups, hasLength(2));
      final anatomy = groups.firstWhere((g) => g.audio.first.name.startsWith('anatomy'));
      expect(anatomy.docs.single.name, 'Anatomy Lec3.pdf');
    });

    test('slides join the recording made in the same timetable slot', () {
      final groups = groupBatch([
        _file('rec001.m4a', 'audio/mp4', monday.add(const Duration(hours: 13))),
        _file('slides.pdf', 'application/pdf', monday.add(const Duration(hours: 12, minutes: 20))),
      ], schedule);

      expect(groups, hasLength(1));
      expect(groups.single.entry?.id, 'phys');
      expect(groups.single.docs, hasLength(1));
      expect(groups.single.title, 'محاضرة phys 5/10');
    });

    test('slides with no matching recording become a lecture of their own', () {
      final groups = groupBatch([
        _file('rec001.m4a', 'audio/mp4'),
        _file('biochem.pdf', 'application/pdf'),
      ], schedule);

      expect(groups, hasLength(2));
      expect(groups.last.audio, isEmpty);
      expect(groups.last.title, 'biochem');
    });
  });
}
