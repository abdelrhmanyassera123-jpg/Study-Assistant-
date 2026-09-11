import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'repository.dart';

final supabaseProvider = Provider<SupabaseClient>((ref) => Supabase.instance.client);

final repositoryProvider = Provider<Repository>((ref) => Repository(ref.watch(supabaseProvider)));

/// حالة تسجيل الدخول — الواجهة كلها بتتفرع من هنا.
/// Auth state; the whole UI branches off this.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentUser;
});

// ---------------------------------------------------------------- data
final subjectsProvider =
    FutureProvider<List<Subject>>((ref) => ref.watch(repositoryProvider).subjects());

final tasksProvider =
    FutureProvider<List<Task>>((ref) => ref.watch(repositoryProvider).tasks());

final notesProvider =
    FutureProvider<List<Note>>((ref) => ref.watch(repositoryProvider).notes());

final cardsProvider =
    FutureProvider<List<Flashcard>>((ref) => ref.watch(repositoryProvider).cards());

final sessionsProvider =
    FutureProvider<List<StudySession>>((ref) => ref.watch(repositoryProvider).recentSessions());

final weeklyReviewsProvider =
    FutureProvider<int>((ref) => ref.watch(repositoryProvider).reviewsThisWeek());

/// جدول المحاضرات الأسبوعي.
/// The weekly timetable.
final scheduleProvider = FutureProvider<List<ScheduleEntry>>(
  (ref) => ref.watch(repositoryProvider).scheduleEntries(),
);

/// بروفايلات الشكل حسب المادة.
/// Look profiles by subject.
final styleProfilesProvider = FutureProvider<Map<String?, Map<String, dynamic>>>(
  (ref) => ref.watch(repositoryProvider).styleProfiles(),
);

final styleSamplesProvider =
    FutureProvider<List<StyleSample>>((ref) => ref.watch(repositoryProvider).styleSamples());

/// بيختار العينات اللي هتتبعت للموديل: بتاعة المادة الأول، وبعدين العامة.
/// Picks which samples go into the prompt: subject-specific first, then general.
///
/// بنقف عند [limit] لأن نقل الأسلوب بيوصل لأقصاه عند حوالي 4 أمثلة —
/// بعد كده الأمثلة الزيادة بتميّع الأسلوب بدل ما توضحه.
/// We cap at [limit] because style transfer peaks around four examples; extra
/// ones dilute the voice instead of sharpening it.
List<StyleSample> pickStyleSamples(
  List<StyleSample> all,
  String? subjectId, {
  int limit = 4,
}) {
  final forSubject = all.where((s) => s.subjectId == subjectId && subjectId != null);
  final general = all.where((s) => s.subjectId == null);
  final others = all.where((s) => s.subjectId != null && s.subjectId != subjectId);

  return [...forSubject, ...general, ...others].take(limit).toList();
}

/// خريطة id -> مادة، عشان نعرض اسم/لون المادة جنب أي عنصر.
/// id -> subject lookup, for showing a subject's name and color inline.
final subjectMapProvider = Provider<Map<String, Subject>>((ref) {
  final list = ref.watch(subjectsProvider).value ?? const <Subject>[];
  return {for (final s in list) s.id: s};
});

/// الكروت المستحقة دلوقتي، الأقدم استحقاقًا الأول.
/// Cards due right now, most overdue first.
final dueCardsProvider = Provider<List<Flashcard>>((ref) {
  final cards = ref.watch(cardsProvider).value ?? const <Flashcard>[];
  final due = cards.where((c) => c.isDue).toList()
    ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
  return due;
});

/// يعيد تحميل كل الداتا — بيتنادى بعد أي تعديل.
/// Refreshes every list; called after each mutation.
void invalidateAll(WidgetRef ref) {
  ref.invalidate(subjectsProvider);
  ref.invalidate(tasksProvider);
  ref.invalidate(notesProvider);
  ref.invalidate(cardsProvider);
  ref.invalidate(sessionsProvider);
  ref.invalidate(weeklyReviewsProvider);
  ref.invalidate(styleSamplesProvider);
  ref.invalidate(styleProfilesProvider);
  ref.invalidate(scheduleProvider);
}
