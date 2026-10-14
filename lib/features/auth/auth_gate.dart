import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../home/home_shell.dart';
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
            : const HomeShell();
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
          : const HomeShell(),
      data: (state) =>
          state.session == null ? const LoginPage() : const HomeShell(),
    );
  }
}
