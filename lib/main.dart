import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/l10n.dart';
import 'core/settings.dart';
import 'core/supabase_config.dart';
import 'features/auth/auth_gate.dart';
import 'features/auth/setup_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // لو البيانات مش متحطة، بنفتح التطبيق على شاشة الإعداد بدل ما نكراش.
  // Without credentials we show a setup screen instead of crashing.
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // anonKey متعلّم كـ deprecated لصالح publishableKey، بس هو اللي بيقبل
      // المفتاحين (القديم anon والجديد sb_publishable_...) فسايبينه.
      // anonKey is marked deprecated in favour of publishableKey, but it is the
      // parameter that accepts both the legacy anon JWT and the new
      // sb_publishable_... key, so we keep it.
      // ignore: deprecated_member_use
      anonKey: SupabaseConfig.anonKey,
    );
  }

  runApp(const ProviderScope(child: StudyApp()));
}

class StudyApp extends ConsumerWidget {
  const StudyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final isAr = settings.languageCode == 'ar';

    return MaterialApp(
      title: 'Study Assistant',
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        AppL10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: settings.themeMode,
      theme: AppTheme.light(isAr),
      darkTheme: AppTheme.dark(isAr),
      home: SupabaseConfig.isConfigured ? const AuthGate() : const SetupPage(),
    );
  }
}
