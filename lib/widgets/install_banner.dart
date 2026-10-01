import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

import '../core/design.dart';
import '../core/install_prompt.dart';
import '../core/l10n.dart';

/// شريط "ثبّت التطبيق" — بيظهر أول ما المتصفح يسمح بالتثبيت، ومش بيظهر لو
/// التطبيق متثبّت أو المستخدم قال "مش دلوقتي" من قريب.
/// The "install the app" strip: it appears as soon as the browser allows
/// installing, and never when the app is installed or the user said "not
/// now" recently.
class InstallBanner extends StatefulWidget {
  const InstallBanner({super.key});

  @override
  State<InstallBanner> createState() => _InstallBannerState();
}

class _InstallBannerState extends State<InstallBanner> {
  static const _kDismissed = 'install_banner_dismissed_at';

  /// "مش دلوقتي" بتخفيه 3 أيام بس — التثبيت هو اللي بيخلّي المشاركة
  /// والإشعارات تشتغل، فمش عايزينه يختفي للأبد.
  /// "Not now" hides it for three days only: installing is what makes sharing
  /// and notifications work, so it should not vanish for good.
  static const _snooze = Duration(days: 3);

  StreamSubscription<web.Event>? _sub;
  bool _dismissed = true;
  bool _canPrompt = false;

  @override
  void initState() {
    super.initState();
    if (InstallPrompt.isInstalled) return;
    _canPrompt = InstallPrompt.canPrompt;
    _sub = InstallPrompt.onChange(() {
      if (mounted) setState(() => _canPrompt = InstallPrompt.canPrompt);
    });
    SharedPreferences.getInstance().then((p) {
      final at = DateTime.tryParse(p.getString(_kDismissed) ?? '');
      final snoozed = at != null && DateTime.now().difference(at) < _snooze;
      if (mounted) setState(() => _dismissed = snoozed);
    }).catchError((_) {
      if (mounted) setState(() => _dismissed = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kDismissed, DateTime.now().toIso8601String());
    } catch (_) {}
  }

  Future<void> _install() async {
    final accepted = await InstallPrompt.prompt();
    if (mounted && accepted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final ios = InstallPrompt.isIos;
    if (_dismissed || InstallPrompt.isInstalled || !(_canPrompt || ios)) {
      return const SizedBox.shrink();
    }

    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(Insets.lg, Insets.sm, Insets.sm, Insets.sm),
          child: Row(
            children: [
              Icon(Icons.install_mobile_rounded, color: scheme.onPrimaryContainer),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  ios ? l.installIosSteps : l.installPitch,
                  style: text.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
              if (!ios) ...[
                const SizedBox(width: Insets.sm),
                FilledButton(onPressed: _install, child: Text(l.installApp)),
              ],
              IconButton(
                tooltip: l.notNow,
                onPressed: _dismiss,
                icon: Icon(Icons.close_rounded, size: 18, color: scheme.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
