import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../core/supabase_config.dart';
import '../../data/providers.dart';
import 'gemini_summarizer.dart';
import 'summarizer.dart';

/// الملخّص المستخدم في التطبيق.
/// The summarizer the app uses.
///
/// الصفحة بتاخد `Summarizer` مجرّد ومش بتعرف مين وراه، فإضافة مزود تاني بعدين
/// بتتم هنا وفي ملف تنفيذه بس.
/// The page takes an abstract `Summarizer` and never learns what is behind it,
/// so adding another provider later touches only this file and its
/// implementation.
final activeSummarizerProvider = Provider<Summarizer>((ref) {
  final settings = ref.watch(settingsProvider);

  return GeminiSummarizer(GeminiConfig(
    functionUrl: '${SupabaseConfig.url}/functions/v1/summarize',
    // التوكن بيتقرا وقت البناء، والـ provider بيتعاد بناؤه مع أي تغيير في حالة
    // الدخول عشان ما نستعملش توكن منتهي.
    // Read at build time; the provider rebuilds on auth changes so a stale
    // token is never reused.
    accessToken: ref.watch(accessTokenProvider) ?? '',
    anonKey: SupabaseConfig.anonKey,
    model: settings.geminiModel,
  ));
});

/// توكن الدخول الحالي — بيتغير مع تسجيل الدخول والخروج والتجديد.
/// The current access token; changes on sign-in, sign-out and refresh.
final accessTokenProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentSession?.accessToken;
});
