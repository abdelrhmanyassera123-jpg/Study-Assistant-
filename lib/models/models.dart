import 'package:flutter/material.dart';

DateTime? _parseDate(dynamic v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

/// مادة دراسية — كل حاجة تانية بتتربط بيها.
/// A subject; tasks, cards and notes hang off it.
@immutable
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
  });

  final String id;
  final String name;
  final Color color;
  final DateTime createdAt;

  factory Subject.fromMap(Map<String, dynamic> m) => Subject(
        id: m['id'] as String,
        name: m['name'] as String,
        color: Color(m['color'] as int),
        createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        ...toUpdate(),
      };

  Map<String, dynamic> toUpdate() => {
        'name': name,
        'color': color.toARGB32(),
      };
}

enum TaskPriority { low, medium, high }

@immutable
class Task {
  const Task({
    required this.id,
    required this.title,
    this.details,
    this.subjectId,
    this.dueDate,
    this.priority = TaskPriority.medium,
    this.isDone = false,
    this.completedAt,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? details;
  final String? subjectId;
  final DateTime? dueDate;
  final TaskPriority priority;
  final bool isDone;
  final DateTime? completedAt;
  final DateTime createdAt;

  bool get isOverdue {
    final d = dueDate;
    if (d == null || isDone) return false;
    final today = DateTime.now();
    final endOfDay = DateTime(d.year, d.month, d.day, 23, 59, 59);
    return today.isAfter(endOfDay);
  }

  bool get isDueToday {
    final d = dueDate;
    if (d == null) return false;
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  factory Task.fromMap(Map<String, dynamic> m) => Task(
        id: m['id'] as String,
        title: m['title'] as String,
        details: m['details'] as String?,
        subjectId: m['subject_id'] as String?,
        dueDate: _parseDate(m['due_date']),
        priority: TaskPriority.values[(m['priority'] as int?) ?? 1],
        isDone: (m['is_done'] as bool?) ?? false,
        completedAt: _parseDate(m['completed_at']),
        createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        ...toUpdate(),
      };

  Map<String, dynamic> toUpdate() => {
        'title': title,
        'details': details,
        'subject_id': subjectId,
        'due_date': dueDate?.toUtc().toIso8601String(),
        'priority': priority.index,
        'is_done': isDone,
        'completed_at': completedAt?.toUtc().toIso8601String(),
      };

  Task copyWith({
    String? title,
    String? details,
    String? subjectId,
    DateTime? dueDate,
    bool clearDueDate = false,
    TaskPriority? priority,
    bool? isDone,
    DateTime? completedAt,
    bool clearCompletedAt = false,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      details: details ?? this.details,
      subjectId: subjectId ?? this.subjectId,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      priority: priority ?? this.priority,
      isDone: isDone ?? this.isDone,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      createdAt: createdAt,
    );
  }
}

@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    this.subjectId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? subjectId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Note.fromMap(Map<String, dynamic> m) => Note(
        id: m['id'] as String,
        title: m['title'] as String,
        body: (m['body'] as String?) ?? '',
        subjectId: m['subject_id'] as String?,
        createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
        updatedAt: _parseDate(m['updated_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        ...toUpdate(),
      };

  Map<String, dynamic> toUpdate() => {
        'title': title,
        'body': body,
        'subject_id': subjectId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}

/// تقييم المستخدم للكارت بعد ما يشوف الإجابة.
/// How well the user recalled a card.
enum ReviewGrade { again, hard, good, easy }

/// كارت مراجعة بخوارزمية التكرار المتباعد SM-2.
/// A flashcard scheduled with the SM-2 spaced-repetition algorithm.
@immutable
class Flashcard {
  const Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.subjectId,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.repetitions = 0,
    this.lapses = 0,
    required this.dueAt,
    required this.createdAt,
  });

  final String id;
  final String front;
  final String back;
  final String? subjectId;

  /// معامل السهولة (SM-2) — أقل قيمة 1.3.
  /// SM-2 ease factor, floored at 1.3.
  final double ease;
  final int intervalDays;
  final int repetitions;
  final int lapses;
  final DateTime dueAt;
  final DateTime createdAt;

  bool get isNew => repetitions == 0;
  bool get isDue => !dueAt.isAfter(DateTime.now());

  /// بيحسب الجدولة الجاية بناءً على تقييم المستخدم.
  /// Computes the next schedule from the user's grade (SM-2).
  Flashcard schedule(ReviewGrade grade) {
    // q في SM-2 من 0 لـ 5؛ بنستعمل 2/3/4/5 للأربع أزرار.
    // SM-2 grades run 0..5; the four buttons map to 2/3/4/5.
    const qByGrade = {
      ReviewGrade.again: 2,
      ReviewGrade.hard: 3,
      ReviewGrade.good: 4,
      ReviewGrade.easy: 5,
    };
    final q = qByGrade[grade]!;

    var newEase = ease + (0.1 - (5 - q) * (0.08 + (5 - q) * 0.02));
    if (newEase < 1.3) newEase = 1.3;

    int newReps;
    int newInterval;
    int newLapses = lapses;

    if (grade == ReviewGrade.again) {
      // نسيها — ترجع لأول الطابور وتتعاد النهاردة.
      // Forgotten: back to the start of the queue, due again today.
      newReps = 0;
      newInterval = 0;
      newLapses = lapses + 1;
    } else {
      newReps = repetitions + 1;
      if (newReps == 1) {
        newInterval = 1;
      } else if (newReps == 2) {
        newInterval = grade == ReviewGrade.hard ? 3 : 6;
      } else {
        newInterval = (intervalDays * newEase).round();
        if (grade == ReviewGrade.hard) {
          newInterval = (intervalDays * 1.2).round();
        }
      }
      if (newInterval < 1) newInterval = 1;
    }

    final now = DateTime.now();
    final next = newInterval == 0
        // "تاني" يرجعها بعد 10 دقايق في نفس الجلسة.
        // "Again" brings it back in 10 minutes, same session.
        ? now.add(const Duration(minutes: 10))
        : DateTime(now.year, now.month, now.day + newInterval, 4);

    return Flashcard(
      id: id,
      front: front,
      back: back,
      subjectId: subjectId,
      ease: newEase,
      intervalDays: newInterval,
      repetitions: newReps,
      lapses: newLapses,
      dueAt: next,
      createdAt: createdAt,
    );
  }

  factory Flashcard.fromMap(Map<String, dynamic> m) => Flashcard(
        id: m['id'] as String,
        front: m['front'] as String,
        back: m['back'] as String,
        subjectId: m['subject_id'] as String?,
        ease: ((m['ease'] as num?) ?? 2.5).toDouble(),
        intervalDays: (m['interval_days'] as int?) ?? 0,
        repetitions: (m['repetitions'] as int?) ?? 0,
        lapses: (m['lapses'] as int?) ?? 0,
        dueAt: _parseDate(m['due_at']) ?? DateTime.now(),
        createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        ...toUpdate(),
      };

  Map<String, dynamic> toUpdate() => {
        'front': front,
        'back': back,
        'subject_id': subjectId,
        'ease': ease,
        'interval_days': intervalDays,
        'repetitions': repetitions,
        'lapses': lapses,
        'due_at': dueAt.toUtc().toIso8601String(),
      };

  Flashcard copyWith({String? front, String? back, String? subjectId}) => Flashcard(
        id: id,
        front: front ?? this.front,
        back: back ?? this.back,
        subjectId: subjectId ?? this.subjectId,
        ease: ease,
        intervalDays: intervalDays,
        repetitions: repetitions,
        lapses: lapses,
        dueAt: dueAt,
        createdAt: createdAt,
      );
}

/// جلسة تركيز مسجلة — دي مصدر كل الإحصائيات.
/// A recorded focus session; every stat is derived from these.
@immutable
class StudySession {
  const StudySession({
    required this.id,
    this.subjectId,
    required this.startedAt,
    required this.durationSeconds,
  });

  final String id;
  final String? subjectId;
  final DateTime startedAt;
  final int durationSeconds;

  int get minutes => (durationSeconds / 60).round();

  factory StudySession.fromMap(Map<String, dynamic> m) => StudySession(
        id: m['id'] as String,
        subjectId: m['subject_id'] as String?,
        startedAt: _parseDate(m['started_at']) ?? DateTime.now(),
        durationSeconds: (m['duration_seconds'] as int?) ?? 0,
      );
}

/// مثال على أسلوب المستخدم في التلخيص — الموديل بيقلده.
/// One of the user's own summaries, used to teach the model their style.
@immutable
class StyleSample {
  const StyleSample({
    required this.id,
    required this.title,
    required this.body,
    this.subjectId,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;

  /// null = أسلوب عام يصلح لأي مادة.
  /// null means a general sample that fits any subject.
  final String? subjectId;

  final DateTime createdAt;

  /// تقدير تقريبي لطول العينة — بيساعد نحسب حجم البرومبت قبل ما نبعته.
  /// Rough size estimate, so we can budget the prompt before sending it.
  int get approxTokens => (body.length / 3).round();

  factory StyleSample.fromMap(Map<String, dynamic> m) => StyleSample(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        body: m['body'] as String,
        subjectId: m['subject_id'] as String?,
        createdAt: _parseDate(m['created_at']) ?? DateTime.now(),
      );

  Map<String, dynamic> toInsert(String userId) => {
        'user_id': userId,
        ...toUpdate(),
      };

  Map<String, dynamic> toUpdate() => {
        'title': title,
        'body': body,
        'subject_id': subjectId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
}
