import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';
import '../timer/pomodoro_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final user = ref.watch(currentUserProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: PageBody(
        maxWidth: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(l.language),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ar', label: Text('العربية')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {settings.languageCode},
                  onSelectionChanged: (s) => notifier.setLanguage(s.first),
                ),
              ),
            ),
            SectionHeader(l.theme),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(l.themeLight),
                      icon: const Icon(Icons.light_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(l.themeDark),
                      icon: const Icon(Icons.dark_mode_rounded),
                    ),
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(l.themeSystem),
                      icon: const Icon(Icons.brightness_auto_rounded),
                    ),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                ),
              ),
            ),
            SectionHeader(l.timer),
            Card(
              child: ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: Text(l.focusLength),
                subtitle: Text(
                  '${settings.focusMinutes} / ${settings.shortBreakMinutes} / '
                  '${settings.longBreakMinutes} ${l.minShort}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const TimerSettingsSheet(),
                ),
              ),
            ),
            SectionHeader(l.account),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(Icons.person_rounded, color: scheme.onPrimaryContainer),
                    ),
                    title: Text(
                      (user?.userMetadata?['display_name'] as String?)?.trim().isNotEmpty ==
                              true
                          ? user!.userMetadata!['display_name'] as String
                          : (user?.email ?? ''),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: user?.email == null ? null : Text(user!.email!),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.logout_rounded, color: scheme.error),
                    title: Text(l.signOut, style: TextStyle(color: scheme.error)),
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(l.signOutConfirm),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(l.cancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(l.signOut),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      await ref.read(supabaseProvider).auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context).popUntil((r) => r.isFirst);
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '${l.appName} · Flutter + Supabase',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
