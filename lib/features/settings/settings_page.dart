import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../schedule/lecture_editor.dart' show reminderChoices;
import '../schedule/reminder_service.dart';
import '../summarize/model_settings_sheet.dart';
import '../summarize/style_samples_page.dart';
import '../timer/pomodoro_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l.settings)),
      body: PageBody(
        maxWidth: 660,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الحساب فوق: أول سؤال بيتسأل في الإعدادات هو "أنا داخل بمين؟".
            // The account comes first: the first question settings answers is
            // "who am I signed in as?".
            const SizedBox(height: Insets.sm),
            const _AccountCard(),

            SectionHeader(l.appearance, subtitle: l.appearanceHint),
            AppCard(
              padding: Insets.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FieldLabel(l.language),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'ar',
                        label: Text('العربية',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text('English',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                    selected: {settings.languageCode},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => notifier.setLanguage(s.first),
                  ),
                  const SizedBox(height: Insets.xl),
                  _FieldLabel(l.theme),
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(l.themeLight,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        icon: const Icon(Icons.light_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(l.themeDark,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        icon: const Icon(Icons.dark_mode_rounded),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(l.themeSystem,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        icon: const Icon(Icons.brightness_auto_rounded),
                      ),
                    ],
                    selected: {settings.themeMode},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => notifier.setThemeMode(s.first),
                  ),
                  const SizedBox(height: Insets.xl),
                  Row(
                    children: [
                      Expanded(child: _FieldLabel(l.textSize, bottom: 0)),
                      Text(
                        '${(settings.uiScale * 100).round()}%',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.uiScale.clamp(0.7, 1.5),
                    min: 0.7,
                    max: 1.5,
                    divisions: 16,
                    label: '${(settings.uiScale * 100).round()}%',
                    onChanged: (v) => notifier.setUiScale((v * 20).round() / 20),
                  ),
                  Text(
                    l.textSizeHint,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.6,
                        ),
                  ),
                ],
              ),
            ),

            SectionHeader(l.reminders, subtitle: l.remindersHint),
            const _RemindersCard(),
            const SizedBox(height: Insets.md),
            const _NotificationCustomizeCard(),

            SectionHeader(l.studyTools, subtitle: l.studyToolsHint),
            AppCard(
              padding: Insets.xs,
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.timelapse_rounded,
                    title: l.timer,
                    subtitle: '${settings.focusMinutes} / '
                        '${settings.shortBreakMinutes} / '
                        '${settings.longBreakMinutes} ${l.minShort}',
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => const TimerSettingsSheet(),
                    ),
                  ),
                  const Divider(height: 1, indent: Insets.section),
                  _SettingRow(
                    icon: Icons.auto_awesome_rounded,
                    title: l.modelSettings,
                    subtitle: l.modelSettingsHint,
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const ModelSettingsSheet(),
                    ),
                  ),
                  const Divider(height: 1, indent: Insets.section),
                  _SettingRow(
                    icon: Icons.draw_rounded,
                    title: l.styleSamples,
                    subtitle: l.styleSamplesHint,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StyleSamplesPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: Insets.section),
            const _SignOutButton(),
            const SizedBox(height: Insets.xxl),
            Text(
              '${l.appName} · Flutter + Supabase',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// مفتاح التنبيهات ومعاه حالته الحقيقية من المتصفح.
/// The reminders switch, with its real state from the browser.
///
/// المفتاح لوحده مش كفاية: ممكن يكون مفتوح والمتصفح رافض، وساعتها مفيش تنبيه
/// بيطلع والمستخدم مش عارف ليه.
/// The switch alone is not enough: it can be on while the browser refuses, and
/// then nothing appears and the user has no idea why.
class _RemindersCard extends ConsumerWidget {
  const _RemindersCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final reminders = ref.watch(reminderServiceProvider);

    return AppCard(
      padding: Insets.xs,
      child: Column(
        children: [
          SwitchListTile(
            value: settings.remindersOn && reminders.isGranted,
            title: Text(l.reminders),
            subtitle: Text(
              reminders.isBlocked
                  ? l.remindersBlocked
                  : l.remindersNeedOpenTab,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: reminders.isBlocked
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
            ),
            onChanged: reminders.isBlocked
                ? null
                : (on) async {
                    if (!on) {
                      ref.read(settingsProvider.notifier).setReminders(false);
                      unawaited(ref
                          .read(reminderServiceProvider.notifier)
                          .disablePush());
                      return;
                    }
                    // الإذن بيتطلب من الضغطة دي بالظبط: المتصفح بيرفض السؤال
                    // من غير تفاعل مباشر.
                    // Permission is asked from this very press: the browser
                    // refuses to ask without a direct interaction.
                    final granted = await ref
                        .read(reminderServiceProvider.notifier)
                        .requestPermission();
                    ref.read(settingsProvider.notifier).setReminders(granted);
                    if (!granted && context.mounted) {
                      showSnack(context, l.remindersBlocked);
                    }
                  },
          ),
          if (reminders.isBlocked)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.lg, 0, Insets.lg, Insets.md),
              child: Text(
                l.remindersBlockedHint,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// تخصيص شكل التنبيه — صوت، اهتزاز، نص مخصص، ومدة افتراضية لمحاضرة جديدة.
/// Notification look and feel — sound, vibration, custom text, and a
/// default lead time for a new lecture.
class _NotificationCustomizeCard extends ConsumerStatefulWidget {
  const _NotificationCustomizeCard();

  @override
  ConsumerState<_NotificationCustomizeCard> createState() =>
      _NotificationCustomizeCardState();
}

class _NotificationCustomizeCardState
    extends ConsumerState<_NotificationCustomizeCard> {
  final _customBody = TextEditingController();
  bool _seeded = false;
  bool _busy = false;
  bool _testing = false;

  @override
  void dispose() {
    _customBody.dispose();
    super.dispose();
  }

  Future<void> _save(NotificationPrefs next) async {
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveNotificationPrefs(next);
      ref.invalidate(notificationPrefsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final async = ref.watch(notificationPrefsProvider);

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (prefs) {
        // بنملى الحقل أول مرة بس — عشان لمسة المستخدم ما تتمسحش لو الداتا
        // اتحملت تاني بعد حفظ.
        // Seeded only the first time — so a fresh reload after saving does
        // not wipe what the user is typing.
        if (!_seeded) {
          _customBody.text = prefs.customBody ?? '';
          _seeded = true;
        }

        return AppCard(
          padding: Insets.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.soundOn,
                title: Text(l.notificationSound),
                onChanged:
                    _busy ? null : (v) => _save(prefs.copyWith(soundOn: v)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: prefs.vibrateOn,
                title: Text(l.notificationVibrate),
                onChanged:
                    _busy ? null : (v) => _save(prefs.copyWith(vibrateOn: v)),
              ),
              const SizedBox(height: Insets.lg),
              _FieldLabel(l.notificationDefaultLead),
              DropdownButtonFormField<int?>(
                initialValue: reminderChoices.contains(prefs.defaultRemindMinutes)
                    ? prefs.defaultRemindMinutes
                    : 15,
                items: [
                  for (final choice in reminderChoices.whereType<int>())
                    DropdownMenuItem(
                      value: choice,
                      child: Text(l.remindBefore(choice)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) _save(prefs.copyWith(defaultRemindMinutes: v));
                      },
              ),
              const SizedBox(height: Insets.xl),
              _FieldLabel(l.notificationCustomTextLabel),
              TextField(
                controller: _customBody,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: l.notificationCustomTextHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () {
                            _customBody.clear();
                            _save(prefs.copyWith(clearCustomBody: true));
                          },
                    child: Text(l.notificationCustomTextReset),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            await _save(prefs.copyWith(customBody: _customBody.text));
                            if (context.mounted) {
                              showSnack(context, l.notificationSaved);
                            }
                          },
                    child: Text(l.save),
                  ),
                ],
              ),
              const SizedBox(height: Insets.lg),
              OutlinedButton.icon(
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                label: Text(l.sendTestNotification),
                onPressed: _testing
                    ? null
                    : () async {
                        setState(() => _testing = true);
                        final devices = await ref
                            .read(reminderServiceProvider.notifier)
                            .sendTest();
                        if (!context.mounted) return;
                        setState(() => _testing = false);
                        showSnack(context, l.testNotificationResult(devices));
                      },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {this.bottom = Insets.md});

  final String text;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: Icon(icon, size: 21, color: scheme.onSurfaceVariant),
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: scheme.outline),
      onTap: onTap,
    );
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);

    final name = (user?.userMetadata?['display_name'] as String?)?.trim();
    final email = user?.email ?? '';
    final title = name == null || name.isEmpty ? email : name;
    final initial = title.isEmpty ? '?' : title.characters.first.toUpperCase();

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primaryContainer,
            child: Text(
              initial,
              style: text.titleMedium?.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                if (name != null && name.isNotEmpty && email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// الخروج زرار هادي في الآخر: إجراء نادر ومش المفروض يكون أول حاجة تلمسها.
/// Signing out is a quiet button at the end: a rare action that should not be
/// the first thing a thumb lands on.
class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.error,
        side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
      ),
      icon: const Icon(Icons.logout_rounded, size: 19),
      label: Text(l.signOut),
      onPressed: () async {
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
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
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
    );
  }
}
