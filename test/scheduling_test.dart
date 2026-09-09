import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/data/stats.dart';
import 'package:study_assistant/models/models.dart';

Flashcard newCard() => Flashcard(
      id: 'c1',
      front: 'q',
      back: 'a',
      dueAt: DateTime.now(),
      createdAt: DateTime.now(),
    );

int daysFromToday(DateTime d) {
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
}

void main() {
  group('SM-2 scheduling', () {
    test('a good answer moves a new card to tomorrow', () {
      final card = newCard().schedule(ReviewGrade.good);
      expect(card.repetitions, 1);
      expect(card.intervalDays, 1);
      expect(daysFromToday(card.dueAt), 1);
    });

    test('intervals grow across successive good answers', () {
      var card = newCard();
      final intervals = <int>[];
      for (var i = 0; i < 4; i++) {
        card = card.schedule(ReviewGrade.good);
        intervals.add(card.intervalDays);
      }
      expect(intervals, [1, 6, 15, 38]);
      expect(card.repetitions, 4);
    });

    test('again resets progress and brings the card back within the session', () {
      var card = newCard().schedule(ReviewGrade.good).schedule(ReviewGrade.good);
      expect(card.repetitions, 2);

      card = card.schedule(ReviewGrade.again);
      expect(card.repetitions, 0);
      expect(card.intervalDays, 0);
      expect(card.lapses, 1);
      expect(card.isDue, isFalse, reason: 'it waits 10 minutes, not zero');
      expect(card.dueAt.difference(DateTime.now()).inMinutes, lessThanOrEqualTo(10));
    });

    test('ease rises on easy, falls on again, and never drops below 1.3', () {
      expect(newCard().schedule(ReviewGrade.easy).ease, greaterThan(2.5));

      var card = newCard();
      for (var i = 0; i < 12; i++) {
        card = card.schedule(ReviewGrade.again);
      }
      expect(card.ease, 1.3);
    });

    test('hard advances the card but by less than good', () {
      final base = newCard().schedule(ReviewGrade.good).schedule(ReviewGrade.good);
      expect(base.schedule(ReviewGrade.hard).intervalDays,
          lessThan(base.schedule(ReviewGrade.good).intervalDays));
    });
  });

  group('StudyStats', () {
    StudySession session(int daysAgo, int minutes) => StudySession(
          id: 's$daysAgo',
          startedAt: DateTime.now().subtract(Duration(days: daysAgo)),
          durationSeconds: minutes * 60,
        );

    test('sums today, the week, and the total separately', () {
      final stats = StudyStats.from(
        [session(0, 30), session(0, 15), session(3, 50), session(20, 60)],
        const [],
      );
      expect(stats.todayMinutes, 45);
      expect(stats.weekMinutes, 95);
      expect(stats.totalMinutes, 155);
      expect(stats.sessionCount, 4);
    });

    test('counts consecutive days as a streak', () {
      final stats = StudyStats.from(
        [session(0, 20), session(1, 20), session(2, 20), session(4, 20)],
        const [],
      );
      expect(stats.streakDays, 3);
    });

    test('keeps yesterday-anchored streaks alive before you study today', () {
      final stats = StudyStats.from([session(1, 20), session(2, 20)], const []);
      expect(stats.todayMinutes, 0);
      expect(stats.streakDays, 2);
    });

    test('last7Days is oldest first and always seven entries', () {
      final stats = StudyStats.from([session(0, 10)], const []);
      expect(stats.last7Days, hasLength(7));
      expect(stats.last7Days.first.day.isBefore(stats.last7Days.last.day), isTrue);
      expect(stats.last7Days.last.minutes, 10);
    });

    test('splits minutes across subjects', () {
      final stats = StudyStats.from(
        [
          StudySession(
              id: 'a',
              subjectId: 'math',
              startedAt: DateTime.now(),
              durationSeconds: 1800),
          StudySession(
              id: 'b',
              subjectId: 'math',
              startedAt: DateTime.now(),
              durationSeconds: 600),
          StudySession(
              id: 'c', startedAt: DateTime.now(), durationSeconds: 1200),
        ],
        const [],
      );
      expect(stats.minutesBySubject['math'], 40);
      expect(stats.minutesBySubject[null], 20);
    });
  });
}
