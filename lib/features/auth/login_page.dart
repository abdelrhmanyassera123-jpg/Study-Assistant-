import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final auth = ref.read(supabaseProvider).auth;
    try {
      if (_isSignUp) {
        final res = await auth.signUp(
          email: _email.text.trim(),
          password: _password.text,
          data: {'display_name': _name.text.trim()},
        );
        // لو تأكيد الإيميل مفعّل، مفيش session ورا التسجيل.
        // With email confirmation on, sign-up returns no session.
        if (res.session == null && mounted) {
          setState(() => _isSignUp = false);
          showSnack(context, context.l.confirmEmailSent);
        }
      } else {
        await auth.signInWithPassword(
          email: _email.text.trim(),
          password: _password.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.rail;

    return Scaffold(
      body: SafeArea(
        // على الشاشات العريضة الصفحة نصين: لوحة هوية وفورم. على الموبايل
        // الفورم بس — لوحة الهوية بتاكل مساحة الشاشة الصغيرة من غير فايدة.
        // Wide screens split into an identity panel and the form; phones get
        // the form alone, where the panel would eat the screen for nothing.
        child: Row(
          children: [
            if (wide) const Expanded(child: _BrandPanel()),
            Expanded(child: _buildForm(context, wide)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context, bool wide) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: TextButton.icon(
              onPressed: ref.read(settingsProvider.notifier).toggleLanguage,
              icon: const Icon(Icons.translate_rounded, size: 18),
              label: Text(l.isAr ? 'English' : 'العربية'),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.xxl,
                    vertical: Insets.lg,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!wide) ...[
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: Radii.all(Radii.md),
                              ),
                              child: Icon(Icons.auto_stories_rounded,
                                  color: scheme.onPrimaryContainer, size: 26),
                            ),
                          ),
                          const SizedBox(height: Insets.xl),
                        ],
                        Text(
                          _isSignUp ? l.signUp : l.signIn,
                          style: text.headlineSmall,
                        ),
                        const SizedBox(height: Insets.sm),
                        Text(
                          l.tagline,
                          style: text.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: Insets.section),

                        if (_isSignUp) ...[
                          TextFormField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: l.displayName,
                              prefixIcon:
                                  const Icon(Icons.person_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: Insets.md),
                        ],
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: l.email,
                            prefixIcon: const Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(t);
                            return ok ? null : l.emailInvalid;
                          },
                        ),
                        const SizedBox(height: Insets.md),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) =>
                              _busy ? null : _submit(),
                          decoration: InputDecoration(
                            labelText: l.password,
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) =>
                              (v ?? '').length < 6 ? l.passwordShort : null,
                        ),

                        if (_error != null) ...[
                          const SizedBox(height: Insets.lg),
                          InfoBanner(
                            message: _error!,
                            icon: Icons.error_outline_rounded,
                            tone: BannerTone.error,
                          ),
                        ],

                        const SizedBox(height: Insets.xxl),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.2),
                                )
                              : Text(_isSignUp ? l.signUp : l.signIn),
                        ),
                        const SizedBox(height: Insets.sm),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _isSignUp = !_isSignUp;
                                    _error = null;
                                  }),
                          child: Text(
                              _isSignUp ? l.haveAccount : l.noAccountYet),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// لوحة الهوية على الشاشات العريضة.
/// The identity panel on wide screens.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.all(Insets.lg),
      padding: const EdgeInsets.all(Insets.page),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [palette.heroStart, palette.heroEnd],
        ),
        borderRadius: Radii.all(Radii.hero),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.onHero.withValues(alpha: 0.16),
              borderRadius: Radii.all(Radii.md),
            ),
            child: Icon(Icons.auto_stories_rounded,
                color: palette.onHero, size: 28),
          ),
          const SizedBox(height: Insets.section),
          Text(
            l.focusTitle,
            style: text.headlineMedium?.copyWith(color: palette.onHero),
          ),
          const SizedBox(height: Insets.md),
          Text(
            l.focusSubtitle,
            style: text.bodyLarge?.copyWith(
              color: palette.onHero.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: Insets.page),
          for (final line in [l.timer, l.flashcards, l.summarize])
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.md),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded,
                      size: 18, color: palette.onHero.withValues(alpha: 0.75)),
                  const SizedBox(width: Insets.md),
                  Text(
                    line,
                    style: text.bodyMedium?.copyWith(
                      color: palette.onHero.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
