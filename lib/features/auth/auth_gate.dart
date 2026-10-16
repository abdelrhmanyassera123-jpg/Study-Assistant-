import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/access.dart';
import '../../data/providers.dart';
import '../home/home_shell.dart';
import 'activation_page.dart';
import 'login_page.dart';

/// بيوجّه المستخدم: مسجل دخول -> التطبيق، مش مسجل -> شاشة الدخول.
/// Routes signed-in users into the app and everyone else to the login screen.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    // أول تشغيل: الـ stream لسه ما بعتش، بس ممكن تكون فيه جلسة محفوظة.
    // On first frame the stream hasn't emitted yet, but a stored session may exist.
    return auth.when(
      loading: () {
        final user = ref.watch(supabaseProvider).auth.currentUser;
        return user == null
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : const _SubscriptionGate();
      },
      // الخطأ هنا غالبًا فشل تجديد الجلسة من غير نت (التوكن بيخلص بعد ساعة)،
      // والمكتبة بتسيب الجلسة المحفوظة زي ما هي. لو فيه مستخدم، نفتح التطبيق
      // على داتاه المحفوظة بدل ما نرميه على تسجيل الدخول وهو مش قادر يدخل.
      // An error here is usually a failed session refresh with no connection
      // (the token expires after an hour), and the library keeps the stored
      // session. With a user present, open on their saved data rather than a
      // login screen they cannot get past offline.
      error: (_, _) => ref.watch(supabaseProvider).auth.currentUser == null
          ? const LoginPage()
          : const _SubscriptionGate(),
      data: (state) =>
          state.session == null ? const LoginPage() : const _SubscriptionGate(),
    );
  }
}

/// مسجّل دخول: التطبيق لو الاشتراك شغال، وإلا شاشة الكود. لو الأدمن قفل
/// الاشتراك والتطبيق مفتوح، الشاشة بتتبدّل في نفس اللحظة (accessProvider).
/// Signed in: the app with a live subscription, otherwise the code screen.
/// If the admin switches it off with the app open, the screen changes that
/// moment (accessProvider).
class _SubscriptionGate extends ConsumerWidget {
  const _SubscriptionGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(accessProvider);
    return access.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      // أي عطل غير متوقع ما يقفلش على حد — السيرفر بيرفض الذكاء الاصطناعي
      // لأي حد مالوش اشتراك على أي حال.
      // An unexpected failure locks nobody out: the server refuses AI to
      // anyone without a subscription anyway.
      error: (_, _) => const HomeShell(),
      data: (a) => a.active ? const HomeShell() : ActivationPage(access: a),
    );
  }
}
