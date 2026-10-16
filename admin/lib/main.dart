import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'api.dart';
import 'common.dart';
import 'shell.dart';

/// لوحة تحكم الاشتراكات — بتتنشر على /admin في نفس موقع التطبيق، ومحدش
/// غير الأدمن يقدر يعمل فيها حاجة (الداتابيز نفسها بترفض).
/// The subscriptions dashboard, served at /admin on the app's own site.
/// Nobody but an admin can do anything in it (the database itself refuses).
const supabaseUrl = 'https://epcddoelvsqzbsiaeyem.supabase.co';
const supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVwY2Rkb2VsdnNxemJzaWFleWVtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg4Njc3MjUsImV4cCI6MjEwNDQ0MzcyNX0.e4u-BtZF2UMbiVB40cFPg5ssMVp6o96OfsQ7oOw_ZEg';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: deprecated_member_use
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  final db = Supabase.instance.client;
  runApp(AdminApp(api: SupabaseAdminApi(db), auth: db.auth));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, required this.api, this.auth});

  final AdminApi api;

  /// null = معاينة بداتا تجريبية من غير تسجيل دخول (tool/preview.dart).
  /// null = a preview with sample data and no sign-in (tool/preview.dart).
  final GoTrueClient? auth;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(colorSchemeSeed: brand, useMaterial3: true);
    return MaterialApp(
      title: 'لوحة التحكم · مساعد المذاكرة',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: base.copyWith(
        textTheme: GoogleFonts.cairoTextTheme(base.textTheme),
        scaffoldBackgroundColor: const Color(0xFFF7F6F1),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0xFFE6E3DA)),
          ),
        ),
      ),
      home: auth == null ? AdminShell(api: api) : _Gate(api: api, auth: auth!),
    );
  }
}

/// مش مسجّل → دخول. مسجّل بس مش أدمن → "مش مسموح". أدمن → اللوحة.
/// Signed out → sign in. Signed in but not an admin → "not allowed".
/// An admin → the dashboard.
class _Gate extends StatelessWidget {
  const _Gate({required this.api, required this.auth});

  final AdminApi api;
  final GoTrueClient auth;

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: auth.onAuthStateChange,
        builder: (context, _) {
          if (auth.currentUser == null) return _SignIn(auth: auth);
          return FutureBuilder<bool>(
            key: ValueKey(auth.currentUser!.id),
            future: api.isAdmin(),
            builder: (context, snap) {
              if (!snap.hasData && !snap.hasError) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (snap.data == true) return AdminShell(api: api, onSignOut: auth.signOut);
              return _NotAllowed(email: auth.currentUser!.email ?? '', onSignOut: auth.signOut);
            },
          );
        },
      );
}

class _SignIn extends StatefulWidget {
  const _SignIn({required this.auth});

  final GoTrueClient auth;

  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.signInWithPassword(email: _email.text.trim(), password: _password.text);
    } on AuthException catch (e) {
      setState(() => _error = e.message.contains('Invalid') ? 'الإيميل أو الباسورد غلط.' : e.message);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.admin_panel_settings_rounded, size: 44, color: brand),
                        const SizedBox(height: 12),
                        Text(
                          'لوحة التحكم',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        const Text('ادخل بنفس حساب التطبيق', textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _email,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(labelText: 'الإيميل', border: OutlineInputBorder()),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(labelText: 'الباسورد', border: OutlineInputBorder()),
                          onSubmitted: (_) => _busy ? null : _go(),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _go,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Text(_busy ? '...' : 'دخول'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _NotAllowed extends StatelessWidget {
  const _NotAllowed({required this.email, required this.onSignOut});

  final String email;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.block_rounded, size: 44),
              const SizedBox(height: 12),
              Text('الحساب $email مش أدمن.'),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onSignOut, child: const Text('تسجيل خروج')),
            ],
          ),
        ),
      );
}
