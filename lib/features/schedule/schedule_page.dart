import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'lecture_editor.dart';
import 'reminder_service.dart';
import '../study_ai/plan_page.dart';
import 'schedule_import.dart';

/// ترتيب الأيام في العرض — الأسبوع الدراسي بيبدأ السبت.
/// The order days are shown in: the study week starts on Saturday.
const _weekOrder = [6, 7, 1, 2, 3, 4, 5];

class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final schedule = ref.watch(scheduleProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openLectureEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addLecture),
      ),
      body: schedule.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(scheduleProvider)),
        data: (entries) {
          if (entries.isEmpty) {
            return PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Insets.sm),
                  const _ImportCard(),
                  EmptyState(
                    icon: Icons.calendar_month_rounded,
                    title: l.noScheduleYet,
                    message: l.scheduleEmptyHint,
                    action: FilledButton.icon(
                      onPressed: () => openLectureEditor(context, ref, null),
                      icon: const Icon(Icons.add_rounded, size: 19),
                      label: Text(l.addLecture),
                    ),
                  ),
                ],
              ),
            );
          }

          final today = DateTime.now().weekday;
          return PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Insets.sm),
                _NextUp(entries: entries),
                const SizedBox(height: Insets.lg),
                const _RemindersBanner(),
                const _ImportCard(),
                const _PlanCard(),
                for (final day in _weekOrder)
                  _DaySection(
                    weekday: day,
                    isToday: day == today,
                    entries: entries.where((e) => e.weekday == day).toList(),
                  ),
                const SizedBox(height: Insets.section),
                _ClearButton(count: entries.length),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// أقرب محاضرة جاية — أكتر سطر بيتقرا في الصفحة دي.
/// The next lecture up: the one line on this page that actually gets read.
class _NextUp extends StatelessWidget {
  const _NextUp({required this.entries});

  final List<ScheduleEntry> entries;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;

    final now = DateTime.now();
    final sorted = [...entries]..sort(
        (a, b) => a.nextOccurrence(now).compareTo(b.nextOccurrence(now)));
    final next = sorted.first;
    final when = next.nextOccurrence(now);
    final away = when.difference(now);

    return Container(
      padding: const EdgeInsets.all(Insets.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [palette.heroStart, palette.heroEnd],
        ),
        borderRadius: Radii.all(Radii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.schedule.toUpperCase(),
            style: text.labelSmall?.copyWith(
              color: palette.onHero.withValues(alpha: 0.7),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            next.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleLarge?.copyWith(color: palette.onHero),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            [
              l.weekdayName(next.weekday),
              clockOf(context, next.startMinutes),
              if (next.location.trim().isNotEmpty) next.location.trim(),
            ].join(' · '),
            style: text.bodyMedium?.copyWith(
              color: palette.onHero.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 15, color: palette.onHero.withValues(alpha: 0.8)),
              const SizedBox(width: Insets.sm),
              Text(
                _away(context, away),
                style: text.labelMedium?.copyWith(
                  color: palette.onHero.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _away(BuildContext context, Duration d) {
    final l = context.l;
    if (d.inMinutes < 60) return l.reminderBody(d.inMinutes);
    if (d.inHours < 24) return l.inHours(d.inHours);
    return l.inDays(d.inDays);
  }
}

/// بيقول إن التنبيهات مقفولة، وبيفتحها بضغطة.
/// Says reminders are off, and switches them on in one press.
class _RemindersBanner extends ConsumerWidget {
  const _RemindersBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final state = ref.watch(reminderServiceProvider);
    if (!state.isSupported || state.isLive) return const SizedBox.shrink();

    if (state.isBlocked) {
      return Padding(
        padding: const EdgeInsets.only(bottom: Insets.lg),
        child: InfoBanner(
          message: '${l.remindersBlocked} ${l.remindersBlockedHint}',
          icon: Icons.notifications_off_rounded,
          tone: BannerTone.warn,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.lg),
      child: InfoBanner(
        message: l.remindersHint,
        icon: Icons.notifications_active_rounded,
        action: TextButton(
          onPressed: () async {
            final granted =
                await ref.read(reminderServiceProvider.notifier).requestPermission();
            if (granted) {
              ref.read(settingsProvider.notifier).setReminders(true);
            }
            if (context.mounted && !granted) {
              showSnack(context, l.remindersBlocked);
            }
          },
          child: Text(l.enableReminders),
        ),
      ),
    );
  }
}

class _ImportCard extends ConsumerWidget {
  const _ImportCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: AppCard(
        padding: Insets.lg,
        onTap: () => openScheduleImport(context, ref),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: Radii.all(Radii.md),
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  size: 20, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: Insets.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.importSchedule,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    l.importScheduleHint,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

/// مسح الجدول كله في خطوة واحدة.
/// Clearing the whole timetable in one step.
///
/// الجدول بيتغير كل ترم. المسح محاضرة محاضرة يعني 12 تأكيد عشان حاجة المستخدم
/// متأكد منها من الأول، والاستبدال من الاستيراد مش بديل: ساعات بيبقى عايز
/// يفضّي بس.
/// A timetable changes every term. Deleting lecture by lecture means twelve
/// confirmations for something the user was sure about from the start, and
/// replacing from the import is not a substitute: sometimes they just want it
/// empty.
class _ClearButton extends ConsumerWidget {
  const _ClearButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: scheme.error),
        icon: const Icon(Icons.delete_sweep_rounded, size: 19),
        label: Text(l.clearSchedule),
        onPressed: () async {
          final ok = await confirmDelete(
            context,
            extra: l.clearScheduleWarning(count),
          );
          if (!ok) return;
          try {
            await ref.read(repositoryProvider).clearSchedule();
            ref.invalidate(scheduleProvider);
            if (context.mounted) showSnack(context, l.scheduleCleared);
          } catch (e) {
            if (context.mounted) showSnack(context, '$e');
          }
        },
      ),
    );
  }
}

/// الخطة بتتبني على الجدول، فمكانها هنا مش في شاشة لوحدها.
/// The plan is built from the timetable, so it belongs here rather than on a
/// screen of its own.
class _PlanCard extends StatelessWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: AppCard(
        padding: Insets.lg,
        onTap: () => openPlanPage(context),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: palette.warmSurface,
                borderRadius: Radii.all(Radii.md),
              ),
              child: Icon(Icons.event_note_rounded,
                  size: 20, color: palette.warm),
            ),
            const SizedBox(width: Insets.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.weekPlan,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    l.weekPlanHint,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.outline),
          ],
        ),
      ),
    );
  }
}

class _DaySection extends ConsumerWidget {
  const _DaySection({
    required this.weekday,
    required this.entries,
    required this.isToday,
  });

  final int weekday;
  final List<ScheduleEntry> entries;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Insets.xxl, bottom: Insets.md),
          child: Row(
            children: [
              Text(l.weekdayName(weekday),
                  style: Theme.of(context).textTheme.titleSmall),
              if (isToday) ...[
                const SizedBox(width: Insets.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Insets.sm, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: Radii.all(Radii.sm),
                  ),
                  child: Text(
                    l.today,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ],
          ),
        ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: _LectureRow(entry: entry),
          ),
      ],
    );
  }
}

class _LectureRow extends ConsumerWidget {
  const _LectureRow({required this.entry});

  final ScheduleEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subject = ref.watch(subjectMapProvider)[entry.subjectId];
    final colour = subject?.color ?? scheme.primary;

    final meta = [
      if (entry.location.trim().isNotEmpty) entry.location.trim(),
      if (entry.lecturer.trim().isNotEmpty) entry.lecturer.trim(),
    ].join(' · ');

    return AppCard(
      padding: 0,
      onTap: () => openLectureEditor(context, ref, entry),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: colour),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg, vertical: Insets.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(clockOf(context, entry.startMinutes),
                      style: text.titleSmall),
                  if (entry.endMinutes != null)
                    Text(
                      clockOf(context, entry.endMinutes!),
                      style: text.labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    0, Insets.lg, Insets.sm, Insets.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: Insets.sm, left: Insets.sm),
              child: Tooltip(
                message: entry.remindersOn
                    ? l.remindBefore(entry.remindMinutes!)
                    : l.reminderOff,
                child: Icon(
                  entry.remindersOn
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_outlined,
                  size: 18,
                  color: entry.remindersOn ? scheme.primary : scheme.outline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "09:30" بنفس أرقام اللغة المختارة.
/// "09:30" in the digits of the chosen language.
String clockOf(BuildContext context, int minutes) {
  final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  return time.format(context);
}
