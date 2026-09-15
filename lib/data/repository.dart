import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// كل القراءة والكتابة من Supabase بتعدي من هنا.
/// Every read and write to Supabase goes through this class.
///
/// مش بنبعت user_id في الفلترة لأن RLS في الداتابيز بيعمل كده أصلاً،
/// بس بنبعته في الـ insert لأن العمود مطلوب.
/// Queries don't filter by user_id — RLS already does that — but inserts
/// must carry it because the column is NOT NULL.
class Repository {
  Repository(this._db);

  final SupabaseClient _db;

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw StateError('No signed-in user');
    return id;
  }

  // ------------------------------------------------------------ subjects
  // ملحوظة: order() في Supabase بيرتب تنازلي افتراضيًا، فلازم ascending: true
  // كل ما نعوز الأقدم/الأصغر الأول.
  // Note: Supabase's order() defaults to descending, so ascending: true is
  // explicit wherever we want oldest/smallest first.
  Future<List<Subject>> subjects() async {
    final rows =
        await _db.from('subjects').select().order('created_at', ascending: true);
    return rows.map((r) => Subject.fromMap(r)).toList();
  }

  Future<void> addSubject(Subject s) =>
      _db.from('subjects').insert(s.toInsert(_uid));

  Future<void> updateSubject(Subject s) =>
      _db.from('subjects').update(s.toUpdate()).eq('id', s.id);

  Future<void> deleteSubject(String id) =>
      _db.from('subjects').delete().eq('id', id);

  // --------------------------------------------------------------- tasks
  Future<List<Task>> tasks() async {
    final rows = await _db
        .from('tasks')
        .select()
        // المفتوح قبل الخالص، الأقرب تسليمًا الأول، واللي من غير تاريخ في الآخر.
        // Open before done, soonest due first, undated last.
        .order('is_done', ascending: true)
        .order('due_date', ascending: true, nullsFirst: false)
        .order('created_at', ascending: false);
    return rows.map((r) => Task.fromMap(r)).toList();
  }

  Future<void> addTask(Task t) => _db.from('tasks').insert(t.toInsert(_uid));

  Future<void> updateTask(Task t) =>
      _db.from('tasks').update(t.toUpdate()).eq('id', t.id);

  Future<void> setTaskDone(Task t, bool done) => _db.from('tasks').update({
        'is_done': done,
        'completed_at': done ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', t.id);

  Future<void> deleteTask(String id) => _db.from('tasks').delete().eq('id', id);

  // --------------------------------------------------------------- notes
  Future<List<Note>> notes() async {
    final rows =
        await _db.from('notes').select().order('updated_at', ascending: false);
    return rows.map((r) => Note.fromMap(r)).toList();
  }

  Future<void> addNote(Note n) => _db.from('notes').insert(n.toInsert(_uid));

  Future<void> updateNote(Note n) =>
      _db.from('notes').update(n.toUpdate()).eq('id', n.id);

  Future<void> deleteNote(String id) => _db.from('notes').delete().eq('id', id);

  // ---------------------------------------------------------- flashcards
  Future<List<Flashcard>> cards() async {
    // الأقدم استحقاقًا الأول.
    // Most overdue first.
    final rows =
        await _db.from('flashcards').select().order('due_at', ascending: true);
    return rows.map((r) => Flashcard.fromMap(r)).toList();
  }

  Future<void> addCard(Flashcard c) =>
      _db.from('flashcards').insert(c.toInsert(_uid));

  Future<void> updateCard(Flashcard c) =>
      _db.from('flashcards').update(c.toUpdate()).eq('id', c.id);

  Future<void> deleteCard(String id) =>
      _db.from('flashcards').delete().eq('id', id);

  /// بيحفظ جدولة الكارت الجديدة ويسجل المراجعة في نفس الوقت.
  /// Saves the card's new schedule and logs the review.
  Future<Flashcard> reviewCard(Flashcard card, ReviewGrade grade) async {
    final updated = card.schedule(grade);
    await updateCard(updated);
    await _db.from('card_reviews').insert({
      'user_id': _uid,
      'card_id': card.id,
      'grade': grade.index,
    });
    return updated;
  }

  // ------------------------------------------------------------ sessions
  /// جلسات آخر 90 يوم — كفاية لكل الرسوم البيانية والـ streak.
  /// The last 90 days of sessions, enough for every chart and the streak.
  Future<List<StudySession>> recentSessions() async {
    final since = DateTime.now().subtract(const Duration(days: 90));
    final rows = await _db
        .from('study_sessions')
        .select()
        .gte('started_at', since.toUtc().toIso8601String())
        .order('started_at', ascending: false);
    return rows.map((r) => StudySession.fromMap(r)).toList();
  }

  Future<void> logSession({
    required DateTime startedAt,
    required int durationSeconds,
    String? subjectId,
  }) =>
      _db.from('study_sessions').insert({
        'user_id': _uid,
        'subject_id': subjectId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'duration_seconds': durationSeconds,
      });

  // -------------------------------------------------------- style samples
  // ------------------------------------------------------- الجدول / schedule

  Future<List<ScheduleEntry>> scheduleEntries() async {
    final rows = await _db
        .from('schedule_entries')
        .select()
        .order('weekday', ascending: true)
        .order('start_minutes', ascending: true);
    return rows.map<ScheduleEntry>(ScheduleEntry.fromMap).toList();
  }

  Future<void> addScheduleEntry(ScheduleEntry e) =>
      _db.from('schedule_entries').insert(e.toInsert(_uid));

  /// بيضيف مجموعة مرة واحدة — الجدول بييجي كله من الاستيراد.
  /// Inserts a batch in one call: a timetable arrives whole from the import.
  Future<void> addScheduleEntries(List<ScheduleEntry> entries) async {
    if (entries.isEmpty) return;
    await _db
        .from('schedule_entries')
        .insert([for (final e in entries) e.toInsert(_uid)]);
  }

  Future<void> updateScheduleEntry(ScheduleEntry e) =>
      _db.from('schedule_entries').update(e.toUpdate()).eq('id', e.id);

  Future<void> deleteScheduleEntry(String id) =>
      _db.from('schedule_entries').delete().eq('id', id);

  Future<void> clearSchedule() =>
      _db.from('schedule_entries').delete().eq('user_id', _uid);

  Future<List<StyleSample>> styleSamples() async {
    final rows = await _db
        .from('style_samples')
        .select()
        .order('created_at', ascending: false);
    return rows.map((r) => StyleSample.fromMap(r)).toList();
  }

  Future<void> addStyleSample(StyleSample s) =>
      _db.from('style_samples').insert(s.toInsert(_uid));

  Future<void> updateStyleSample(StyleSample s) =>
      _db.from('style_samples').update(s.toUpdate()).eq('id', s.id);

  Future<void> deleteStyleSample(String id) =>
      _db.from('style_samples').delete().eq('id', id);

  // ------------------------------------------------------- style profiles
  /// بيرجّع بروفايلات الشكل مفهرسة بالمادة (المفتاح null = البروفايل العام).
  /// Returns look profiles keyed by subject; a null key is the general one.
  Future<Map<String?, Map<String, dynamic>>> styleProfiles() async {
    final rows = await _db.from('style_profiles').select();
    return {
      for (final r in rows)
        r['subject_id'] as String?: (r['profile'] as Map).cast<String, dynamic>(),
    };
  }

  /// بيحفظ البروفايل ويستبدل القديم لنفس المادة.
  /// Saves the profile, replacing any earlier one for the same subject.
  Future<void> saveStyleProfile({
    String? subjectId,
    required Map<String, dynamic> profile,
    required int sourceCount,
  }) async {
    // بنمسح الأول لأن onConflict مش بيشتغل مع فهرس على تعبير (coalesce).
    // Delete first: onConflict can't target an expression index (coalesce).
    final existing = _db.from('style_profiles').delete();
    await (subjectId == null
        ? existing.isFilter('subject_id', null)
        : existing.eq('subject_id', subjectId));

    await _db.from('style_profiles').insert({
      'user_id': _uid,
      'subject_id': subjectId,
      'profile': profile,
      'source_count': sourceCount,
    });
  }

  Future<void> deleteStyleProfile(String? subjectId) async {
    final query = _db.from('style_profiles').delete();
    await (subjectId == null
        ? query.isFilter('subject_id', null)
        : query.eq('subject_id', subjectId));
  }

  /// عدد الكروت اللي اتراجعت في آخر 7 أيام.
  /// How many cards were reviewed in the last 7 days.
  Future<int> reviewsThisWeek() async {
    final since = DateTime.now().subtract(const Duration(days: 7));
    final rows = await _db
        .from('card_reviews')
        .select('id')
        .gte('reviewed_at', since.toUtc().toIso8601String());
    return rows.length;
  }

  // ------------------------------------------------------- personal API key
  // القيمة نفسها متتقراش تاني بعد ما تتحفظ — بس بنعرف هي موجودة ولا لأ.
  // الفنكشن (summarize) هي اللي بتقرا القيمة الحقيقية وقت النداء على Gemini.
  // The value itself is never read back after saving — only whether one
  // exists. The summarize function is what reads the real value when it
  // calls Gemini.
  /// هل المستخدم حاطط مفتاح Gemini شخصي.
  /// Whether the user has a personal Gemini key set.
  Future<bool> hasGeminiKey() async {
    final row = await _db
        .from('user_api_keys')
        .select('user_id')
        .maybeSingle();
    return row != null;
  }

  /// بيحفظ مفتاح Gemini الشخصي، مستبدلًا القديم لو موجود.
  /// Saves the personal Gemini key, replacing an earlier one if present.
  Future<void> saveGeminiKey(String key) => _db.from('user_api_keys').upsert({
        'user_id': _uid,
        'gemini_api_key': key.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> deleteGeminiKey() =>
      _db.from('user_api_keys').delete().eq('user_id', _uid);

  // -------------------------------------------------------- push subscriptions
  /// بيحفظ اشتراك Push بتاع الجهاز ده، مستبدلًا القديم لو نفس الـ endpoint
  /// موجود بالفعل (المتصفح بيرجّع نفس الاشتراك لو اتسأل تاني).
  /// Saves this device's push subscription, replacing an earlier one for the
  /// same endpoint if it already exists (the browser returns the same
  /// subscription when asked again).
  Future<void> savePushSubscription({
    required String endpoint,
    required String p256dh,
    required String auth,
  }) =>
      _db.from('push_subscriptions').upsert({
        'user_id': _uid,
        'endpoint': endpoint,
        'p256dh': p256dh,
        'auth': auth,
      }, onConflict: 'endpoint');

  Future<void> deletePushSubscription(String endpoint) => _db
      .from('push_subscriptions')
      .delete()
      .eq('endpoint', endpoint);

  // ------------------------------------------------------- notification prefs
  Future<NotificationPrefs> notificationPrefs() async {
    final row = await _db.from('notification_prefs').select().maybeSingle();
    return row == null ? const NotificationPrefs() : NotificationPrefs.fromMap(row);
  }

  Future<void> saveNotificationPrefs(NotificationPrefs prefs) =>
      _db.from('notification_prefs').upsert(prefs.toUpsert(_uid));

  /// بيبعت تنبيه تجربة على أي اشتراك Push للمستخدم ده. بيرجّع عدد الأجهزة
  /// اللي وصلها، أو 0 لو مفيش اشتراك أصلاً.
  /// Sends a test notification to any of this user's push subscriptions.
  /// Returns how many devices it reached, or 0 if there is no subscription.
  Future<int> sendTestPush() async {
    final res = await _db.functions.invoke('send-reminders', body: {'test': true});
    final data = res.data;
    if (data is Map && data['sent'] is num) return (data['sent'] as num).toInt();
    return 0;
  }
}
