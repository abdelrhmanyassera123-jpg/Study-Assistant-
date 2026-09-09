import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../core/supabase_config.dart';
import '../../data/providers.dart';
import 'gemini_summarizer.dart';
import 'ollama_summarizer.dart';
import 'summarizer.dart';

/// بيبني الملخّص المناسب حسب اختيار المستخدم.
/// Builds the summarizer the user has selected.
///
/// الصفحة بتاخد `Summarizer` مجرّد ومش بتعرف مين اللي وراه — عشان كده إضافة
/// مزود جديد بتتم هنا وفي ملف واحد بس.
/// The page takes an abstract `Summarizer` and never learns which one it got,
/// so adding a provider touches only this file and its implementation.
final activeSummarizerProvider = Provider<Summarizer>((ref) {
  final settings = ref.watch(settingsProvider);

  return switch (settings.summarizer) {
    SummarizerProvider.gemini => GeminiSummarizer(GeminiConfig(
        functionUrl: '${SupabaseConfig.url}/functions/v1/summarize',
        // التوكن بيتقرا وقت البناء، والـ provider بيتعاد بناؤه مع أي تغيير
        // في حالة الدخول عشان ما نستعملش توكن منتهي.
        // Read at build time; the provider rebuilds on auth changes so a stale
        // token is never reused.
        accessToken: ref.watch(accessTokenProvider) ?? '',
        anonKey: SupabaseConfig.anonKey,
        model: settings.geminiModel,
      )),
    SummarizerProvider.ollama => OllamaSummarizer(OllamaConfig(
        baseUrl: settings.ollamaBaseUrl,
        model: settings.ollamaModel,
        numCtx: settings.ollamaNumCtx,
      )),
  };
});

/// توكن الدخول الحالي — بيتغير مع تسجيل الدخول والخروج والتجديد.
/// The current access token; changes on sign-in, sign-out and refresh.
final accessTokenProvider = Provider<String?>((ref) {
  ref.watch(authStateProvider);
  return ref.watch(supabaseProvider).auth.currentSession?.accessToken;
});
