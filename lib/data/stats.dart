import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'providers.dart';

DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// إحصائيات محسوبة من جلسات المذاكرة والمهام.
/// Stats derived from study sessions and tasks.
class StudyStats {
  const StudyStats({
    required this.todayMinutes,
    required this.weekMinutes,
    required this.totalMinutes,
    required this.sessionCount,
    required this.streakDays,
    required this.last7Days,
    required this.minutesBySubject,
    required this.tasksCompletedThisWeek,
  });

  final int todayMinutes;
  final int weekMinutes;
  final int totalMinutes;
  final int sessionCount;

  /// عدد الأيام المتتالية اللي فيها جلسة، لحد النهاردة (أو إمبارح لو النهاردة لسه فاضي).
  /// Consecutive days with at least one session, counting back from today
  /// (or yesterday, so a streak isn't lost before you study today).
  final int streakDays;

  /// آخر 7 أيام بالترتيب — أقدم يوم أول. كل عنصر (تاريخ اليوم، دقايق).
  /// Last 7 days oldest-first, each entry (day, minutes).
  final List<({DateTime day, int minutes})> last7Days;

  /// دقايق التركيز لكل مادة (المفتاح null = بدون مادة).
  /// Focus minutes per subject; a null key means "no subject".
  final Map<String?, int> minutesBySubject;

  final int tasksCompletedThisWeek;

  bool get isEmpty => sessionCount == 0;

  double get dailyAverageMinutes {
    final active = last7Days.where((d) => d.minutes > 0).length;
    if (active == 0) return 0;
    return weekMinutes / active;
  }

  static StudyStats from(List<StudySession> sessions, List<Task> tasks) {
    final today = _dayOf(DateTime.now());
    final weekStart = today.subtract(const Duration(days: 6));

    var todayMin = 0;
    var weekMin = 0;
    var totalMin = 0;
    final byDay = <DateTime, int>{};
    final bySubject = <String?, int>{};

    for (final s in sessions) {
      final day = _dayOf(s.startedAt);
      final mins = s.minutes;
      totalMin += mins;
      byDay[day] = (byDay[day] ?? 0) + mins;
      bySubject[s.subjectId] = (bySubject[s.subjectId] ?? 0) + mins;
      if (day == today) todayMin += mins;
      if (!day.isBefore(weekStart)) weekMin += mins;
    }

    final last7 = <({DateTime day, int minutes})>[
      for (var i = 6; i >= 0; i--)
        (
          day: today.subtract(Duration(days: i)),
          minutes: byDay[today.subtract(Duration(days: i))] ?? 0,
        ),
    ];

    // الـ streak بيبدأ من النهاردة لو فيه مذاكرة، وإلا من إمبارح.
    // The streak starts today if you studied today, otherwise yesterday.
    var streak = 0;
    var cursor = (byDay[today] ?? 0) > 0 ? today : today.subtract(const Duration(days: 1));
    while ((byDay[cursor] ?? 0) > 0) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final tasksDone = tasks
        .where((t) =>
            t.isDone && t.completedAt != null && !_dayOf(t.completedAt!).isBefore(weekStart))
        .length;

    return StudyStats(
      todayMinutes: todayMin,
      weekMinutes: weekMin,
      totalMinutes: totalMin,
      sessionCount: sessions.length,
      streakDays: streak,
      last7Days: last7,
      minutesBySubject: bySubject,
      tasksCompletedThisWeek: tasksDone,
    );
  }
}

final statsProvider = Provider<StudyStats>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const <StudySession>[];
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  return StudyStats.from(sessions, tasks);
});
