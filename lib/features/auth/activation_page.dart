import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../data/access.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

/// بتظهر لأي حساب مالوش اشتراك شغال: مكان واحد يكتب فيه الكود.
/// Shown to any account without a live subscription: one place to type the
/// code.
class ActivationPage extends ConsumerStatefulWidget {
  const ActivationPage({super.key, required this.access});

  final Access access;

  @override
  ConsumerState<ActivationPage> createState() => _ActivationPageState();
}

class _ActivationPageState extends ConsumerState<ActivationPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final l = context.l;
    if (_code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await redeemCode(ref, _code.text);
      if (!mounted) return;
      if (result.error == null) {
        showSnack(context, l.activated(result.endsAt));
      } else {
        setState(() => _error = l.redeemError(result.error!));
      }
    } catch (e) {
      if (mounted) setState(() => _error = l.redeemFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final email = ref.watch(currentUserProvider)?.email ?? '';

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Insets.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.key_rounded, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: Insets.lg),
                  Text(
                    l.activateTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    l.activateReason(widget.access.reason, widget.access.endsAt),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Insets.xl),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 2),
                    decoration: const InputDecoration(hintText: 'SA-XXXX-XXXX'),
                    onSubmitted: (_) => _busy ? null : _redeem(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Insets.md),
                    InfoBanner(message: _error!, icon: Icons.error_outline_rounded, tone: BannerTone.error),
                  ],
                  const SizedBox(height: Insets.lg),
                  FilledButton(
                    onPressed: _busy ? null : _redeem,
                    child: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l.activateButton),
                  ),
                  const SizedBox(height: Insets.xl),
                  Text(
                    l.activateHowToGet,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: Insets.lg),
                  TextButton(
                    onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                    child: Text('${l.signOut} ($email)'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
