import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../data/stats.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../flashcards/review_page.dart';
import '../home/home_shell.dart';
import '../notes/notes_page.dart';
import '../tasks/tasks_page.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(statsProvider);
    final dueCards = ref.watch(dueCardsProvider);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final notes = ref.watch(notesProvider).value ?? const <Note>[];
    final user = ref.watch(currentUserProvider);

    final openToday = tasks
        .where((t) => !t.isDone && (t.isDueToday || t.isOverdue))
        .toList();
    final upcoming = tasks
        .where((t) => !t.isDone && !t.isDueToday && !t.isOverdue)
        .take(4)
        .toList();

    final name = (user?.userMetadata?['display_name'] as String?)?.trim();

    return RefreshIndicator(
      onRefresh: () async => invalidateAll(ref),
      child: ListView(
        children: [
          PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Text(
                  name == null || name.isEmpty
                      ? _greeting(context)
                      : '${_greeting(context)}، $name',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  l.tagline,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 20),

                // ---------------------------------------------- key numbers
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: l.todayFocus,
                        value: Fmt.minutes(context, stats.todayMinutes),
                        icon: Icons.timer_rounded,
                        onTap: () => ref.read(sectionProvider.notifier).go(AppSection.timer),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        label: l.currentStreak,
                        value: '${stats.streakDays}',
                        icon: Icons.local_fire_department_rounded,
                        color: const Color(0xFFF59E0B),
                        onTap: () => ref.read(sectionProvider.notifier).go(AppSection.stats),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: l.cardsToReview,
                        value: '${dueCards.length}',
                        icon: Icons.style_rounded,
                        color: dueCards.isEmpty ? null : scheme.error,
                        onTap: () => ref.read(sectionProvider.notifier).go(AppSection.flashcards),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        label: l.dueToday,
                        value: '${openToday.length}',
                        icon: Icons.checklist_rounded,
                        color: const Color(0xFF10B981),
                        onTap: () => ref.read(sectionProvider.notifier).go(AppSection.tasks),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => ref.read(sectionProvider.notifier).go(AppSection.timer),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(l.quickStart),
                      ),
                    ),
                    if (dueCards.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => ReviewPage(queue: dueCards),
                              ),
                            );
                            ref.invalidate(cardsProvider);
                            ref.invalidate(weeklyReviewsProvider);
                          },
                          icon: const Icon(Icons.style_rounded),
                          label: Text('${l.startReview} (${dueCards.length})'),
                        ),
                      ),
                    ],
                  ],
                ),

                // ------------------------------------------------- due today
                SectionHeader(
                  l.dueToday,
                  action: TextButton(
                    onPressed: () =>
                        ref.read(sectionProvider.notifier).go(AppSection.tasks),
                    child: Text(l.all),
                  ),
                ),
                if (openToday.isEmpty && upcoming.isEmpty)
                  _QuietCard(text: l.allCaughtUp)
                else ...[
                  for (final t in openToday)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: TaskTile(task: t),
                    ),
                  if (openToday.isEmpty)
                    for (final t in upcoming)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TaskTile(task: t),
                      ),
                ],

                // ---------------------------------------------- recent notes
                if (notes.isNotEmpty) ...[
                  SectionHeader(
                    l.recentNotes,
                    action: TextButton(
                      onPressed: () =>
                          ref.read(sectionProvider.notifier).go(AppSection.notes),
                      child: Text(l.all),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final n in notes.take(3))
                          ListTile(
                            title: Text(
                              n.title.isEmpty ? l.noteTitle : n.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              n.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              Fmt.date(context, n.updatedAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            onTap: () => openNoteEditor(context, ref, n),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _greeting(BuildContext context) {
    final l = context.l;
    final h = DateTime.now().hour;
    if (h < 12) return l.goodMorning;
    if (h < 18) return l.goodAfternoon;
    return l.goodEvening;
  }
}

class _QuietCard extends StatelessWidget {
  const _QuietCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline_rounded, color: scheme.primary, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  text,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
