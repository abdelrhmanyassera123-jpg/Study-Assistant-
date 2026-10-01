import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/launch_intent.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../home/home_shell.dart';
import '../study_ai/plan_page.dart';
import '../study_ai/saved_plan.dart';

/// "النهاردة": المحاضرة الجاية، وبنود الخطة بتاعة النهاردة بعلامة صح.
/// "Today": the next lecture, and today's plan items with a tick each.
///
/// أول حاجة في الشاشة الرئيسية عشان الطالب ما يفكرش "أذاكر إيه دلوقتي" —
/// الإجابة قدامه.
/// The first thing on the home screen so the student never wonders "what do
/// I study now" — the answer is in front of them.
class TodayCard extends ConsumerWidget {
  const TodayCard({super.key});

  static String _clock(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;

    final schedule = ref.watch(scheduleProvider).value ?? const <ScheduleEntry>[];
    final lectures = schedule
        .where((e) => e.weekday == now.weekday && (e.endMinutes ?? e.startMinutes + 90) > minutes)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    final next = lectures.firstOrNull;

    final saved = ref.watch(savedPlanProvider).value;
    final today = saved != null && saved.isCurrent ? saved.today : null;
    final items = today?.items ?? const [];
    final firstOpen = [for (var i = 0; i < items.length; i++) i]
        .where((i) => !saved!.done.contains(i) && items[i].kind != 'break')
        .firstOrNull;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${l.today} · ${l.weekdayName(now.weekday)}', style: text.titleMedium),
          if (today != null && today.focus.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(today.focus, style: text.bodySmall?.copyWith(color: scheme.primary)),
          ],
          const SizedBox(height: Insets.md),

          if (next != null) ...[
            _LectureRow(entry: next, now: minutes),
            const SizedBox(height: Insets.md),
          ],

          if (items.isEmpty)
            Row(
              children: [
                Expanded(
                  child: Text(
                    saved == null || !saved.isCurrent ? l.noPlanYet : l.planRestDay,
                    style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                TextButton(onPressed: () => openPlanPage(context), child: Text(l.weekPlan)),
              ],
            )
          else ...[
            for (var i = 0; i < items.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: saved!.done.contains(i),
                onChanged: items[i].kind == 'break'
                    ? null
                    : (_) => ref.read(savedPlanProvider.notifier).toggleDone(i),
                title: Text(
                  items[i].what,
                  style: TextStyle(
                    decoration: saved.done.contains(i) ? TextDecoration.lineThrough : null,
                    fontWeight: i == firstOpen ? FontWeight.w700 : null,
                    color: items[i].kind == 'break' ? scheme.onSurfaceVariant : null,
                  ),
                ),
                subtitle: Text([
                  if (items[i].time.isNotEmpty) items[i].time,
                  Fmt.minutes(context, items[i].minutes),
                ].join(' · ')),
                secondary: i == firstOpen
                    ? IconButton(
                        tooltip: l.startFocus,
                        icon: Icon(Icons.play_circle_fill_rounded, color: scheme.primary),
                        onPressed: () =>
                            ref.read(sectionProvider.notifier).go(AppSection.timer),
                      )
                    : null,
              ),
            const SizedBox(height: Insets.sm),
            LinearProgressIndicator(
              value: items.where((i) => i.kind != 'break').isEmpty
                  ? 0
                  : saved!.done.length / items.where((i) => i.kind != 'break').length,
              borderRadius: Radii.all(Radii.sm),
            ),
          ],
        ],
      ),
    );
  }
}

class _LectureRow extends ConsumerWidget {
  const _LectureRow({required this.entry, required this.now});

  final ScheduleEntry entry;
  final int now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final end = entry.endMinutes ?? entry.startMinutes + 90;
    // زرار التسجيل بيظهر من ربع ساعة قبل المحاضرة لحد آخرها.
    // The record button shows from a quarter hour before the lecture to its end.
    final live = now >= entry.startMinutes - 15 && now <= end;

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: live ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: Radii.all(Radii.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.event_rounded, color: scheme.primary),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  [
                    '${TodayCard._clock(entry.startMinutes)}–${TodayCard._clock(end)}',
                    if (entry.location.isNotEmpty) entry.location,
                    if (entry.lecturer.isNotEmpty) entry.lecturer,
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (live)
            FilledButton.icon(
              onPressed: () {
                LaunchIntent.armRecord(entry.id);
                ref.read(sectionProvider.notifier).go(AppSection.summarize);
              },
              icon: const Icon(Icons.mic_rounded, size: 18),
              label: Text(l.recordIt),
            ),
        ],
      ),
    );
  }
}
