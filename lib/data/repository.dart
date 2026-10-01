import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'offline_store.dart';

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

  // ------------------------------------------------------------- offline

  /// بيجيب الصفوف من السيرفر ويحفظ نسخة منها؛ لو مفيش نت بيرجّع آخر نسخة.
  /// Fetches rows from the server and keeps a copy; with no connection it
  /// returns the latest copy instead.
  Future<List<Map<String, dynamic>>> _rows(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    final cacheKey = '$_uid/$key';
    try {
      final rows = await fetch();
      OfflineStore.put(cacheKey, rows);
      return rows;
    } catch (e) {
      final cached = await OfflineStore.get(cacheKey);
      if (cached is List) {
        return [for (final r in cached) if (r is Map) r.cast<String, dynamic>()];
      }
      rethrow;
    }
  }

  String get _pendingKey => '$_uid/pending_reviews';

  /// مراجعات اتعملت من غير نت وبتستنى تتبعت.
  /// Reviews done offline, waiting to be sent.
  Future<List<Map<String, dynamic>>> _pending() async {
    final raw = await OfflineStore.get(_pendingKey);
    return raw is List
        ? [for (final r in raw) if (r is Map) r.cast<String, dynamic>()]
        : <Map<String, dynamic>>[];
  }

  /// بيبعت المراجعات المستنية بالترتيب. اللي يفشل يفضل في الطابور للمرة الجاية.
  /// Sends waiting reviews in order. Whatever fails stays queued for next time.
  Future<int> flushPendingReviews() async {
    final pending = await _pending();
    if (pending.isEmpty) return 0;
    var sent = 0;
    for (final op in pending) {
      try {
        await _db.from('flashcards').update(
              (op['card'] as Map).cast<String, dynamic>(),
            ).eq('id', op['id'] as String);
        await _db.from('card_reviews').insert({
          'user_id': _uid,
          'card_id': op['id'],
          'grade': op['grade'],
          'reviewed_at': op['at'],
        });
        sent++;
      } catch (_) {
        break;
      }
    }
    await OfflineStore.put(_pendingKey, pending.sublist(sent));
    return sent;
  }

  // ------------------------------------------------------------ subjects
  // ملحوظة: order() في Supabase بيرتب تنازلي افتراضيًا، فلازم ascending: true
  // كل ما نعوز الأقدم/الأصغر الأول.
  // Note: Supabase's order() defaults to descending, so ascending: true is
  // explicit wherever we want oldest/smallest first.
  Future<List<Subject>> subjects() async {
    final rows = await _rows(
      'subjects',
      () => _db.from('subjects').select().order('created_at', ascending: true),
    );
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
    final rows = await _rows(
      'tasks',
      () => _db
          .from('tasks')
          .select()
          // المفتوح قبل الخالص، الأقرب تسليمًا الأول، واللي من غير تاريخ في الآخر.
          // Open before done, soonest due first, undated last.
          .order('is_done', ascending: true)
          .order('due_date', ascending: true, nullsFirst: false)
          .order('created_at', ascending: false),
    );
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
    final rows = await _rows(
      'notes',
      () => _db.from('notes').select().order('updated_at', ascending: false),
    );
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
    final rows = await _rows(
      'cards',
      () => _db.from('flashcards').select().order('due_at', ascending: true),
    );
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
  ///
  /// من غير نت المراجعة بتتحفظ في طابور وبتتبعت لما النت يرجع، ونسخة الكروت
  /// اللي على الجهاز بتتحدّث عشان الكارت ما يرجعش مستحق.
  /// Offline, the review is queued and sent when the connection returns, and
  /// the on-device copy of the cards is updated so the card is not due again.
  Future<Flashcard> reviewCard(Flashcard card, ReviewGrade grade) async {
    final updated = card.schedule(grade);
    final at = DateTime.now().toUtc().toIso8601String();
    try {
      await updateCard(updated);
      await _db.from('card_reviews').insert({
        'user_id': _uid,
        'card_id': card.id,
        'grade': grade.index,
        'reviewed_at': at,
      });
    } catch (_) {
      final pending = await _pending()
        ..add({'id': card.id, 'card': updated.toUpdate(), 'grade': grade.index, 'at': at});
      await OfflineStore.put(_pendingKey, pending);
      final cached = await OfflineStore.get('$_uid/cards');
      if (cached is List) {
        await OfflineStore.put('$_uid/cards', [
          for (final r in cached)
            if (r is Map && r['id'] == card.id) {...r, ...updated.toUpdate()} else r,
        ]);
      }
    }
    return updated;
  }

  // ------------------------------------------------------------ sessions
  /// جلسات آخر 90 يوم — كفاية لكل الرسوم البيانية والـ streak.
  /// The last 90 days of sessions, enough for every chart and the streak.
  Future<List<StudySession>> recentSessions() async {
    final since = DateTime.now().subtract(const Duration(days: 90));
    final rows = await _rows(
      'sessions',
      () => _db
          .from('study_sessions')
          .select()
          .gte('started_at', since.toUtc().toIso8601String())
          .order('started_at', ascending: false),
    );
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
    final rows = await _rows(
      'schedule',
      () => _db
          .from('schedule_entries')
          .select()
          .order('weekday', ascending: true)
          .order('start_minutes', ascending: true),
    );
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
    final rows = await _rows(
      'style_samples',
      () => _db.from('style_samples').select().order('created_at', ascending: false),
    );
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
    final rows = await _rows('style_profiles', () => _db.from('style_profiles').select());
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
  /// موجود بالفعل (المتصفح بيرجّع نفس الاشتراك لو اتسأل تاني) — حتى لو كان
  /// مسجّل باسم حساب تاني.
  /// Saves this device's push subscription, replacing an earlier one for the
  /// same endpoint if it already exists (the browser returns the same
  /// subscription when asked again) — even one registered to another account.
  Future<void> savePushSubscription({
    required String endpoint,
    required String p256dh,
    required String auth,
  }) =>
      // RPC مش upsert: لو الجهاز كان مسجّل باسم حساب تاني، الاشتراك بينتقل
      // للحساب ده (شوف migration 20261002000000).
      // An RPC rather than an upsert: if the device was registered to another
      // account, the subscription moves to this one (see migration
      // 20261002000000).
      _db.rpc('claim_push_subscription', params: {
        'p_endpoint': endpoint,
        'p_p256dh': p256dh,
        'p_auth': auth,
      });

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
