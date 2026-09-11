import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
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
    final palette = AppPalette.of(context);

    final stats = ref.watch(statsProvider);
    final dueCards = ref.watch(dueCardsProvider);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final notes = ref.watch(notesProvider).value ?? const <Note>[];

    final openToday =
        tasks.where((t) => !t.isDone && (t.isDueToday || t.isOverdue)).toList();
    final upcoming = tasks
        .where((t) => !t.isDone && !t.isDueToday && !t.isOverdue)
        .take(3)
        .toList();

    return RefreshIndicator(
      onRefresh: () async => invalidateAll(ref),
      child: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WelcomeCard(),
            const SizedBox(height: Insets.xxl),

            StatGrid(
              children: [
                StatTile(
                  label: l.todayFocus,
                  value: Fmt.minutes(context, stats.todayMinutes),
                  icon: Icons.timelapse_rounded,
                  onTap: () =>
                      ref.read(sectionProvider.notifier).go(AppSection.timer),
                ),
                StatTile(
                  label: l.currentStreak,
                  value: '${stats.streakDays}',
                  icon: Icons.local_fire_department_rounded,
                  color: palette.warm,
                  onTap: () =>
                      ref.read(sectionProvider.notifier).go(AppSection.stats),
                ),
                StatTile(
                  label: l.cardsToReview,
                  value: '${dueCards.length}',
                  icon: Icons.style_rounded,
                  color: dueCards.isEmpty ? null : scheme.error,
                  onTap: () => ref
                      .read(sectionProvider.notifier)
                      .go(AppSection.flashcards),
                ),
                StatTile(
                  label: l.dueToday,
                  value: '${openToday.length}',
                  icon: Icons.task_alt_rounded,
                  color: palette.success,
                  onTap: () =>
                      ref.read(sectionProvider.notifier).go(AppSection.tasks),
                ),
              ],
            ),

            if (dueCards.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              _ReviewPrompt(cards: dueCards),
            ],

            // -------------------------------------------------- due today
            SectionHeader(
              l.dueToday,
              action: TextButton(
                onPressed: () =>
                    ref.read(sectionProvider.notifier).go(AppSection.tasks),
                child: Text(l.viewAll),
              ),
            ),
            if (openToday.isEmpty && upcoming.isEmpty)
              _QuietCard(text: l.allCaughtUp)
            else
              for (final t in (openToday.isEmpty ? upcoming : openToday))
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: TaskTile(task: t),
                ),

            // ------------------------------------------------ recent notes
            if (notes.isNotEmpty) ...[
              SectionHeader(
                l.recentNotes,
                action: TextButton(
                  onPressed: () =>
                      ref.read(sectionProvider.notifier).go(AppSection.notes),
                  child: Text(l.viewAll),
                ),
              ),
              AppCard(
                padding: Insets.sm,
                child: Column(
                  children: [
                    for (final n in notes.take(3))
                      ListTile(
                        leading: Icon(Icons.article_outlined,
                            size: 20, color: scheme.onSurfaceVariant),
                        title: Text(
                          n.title.isEmpty ? l.noteTitle : n.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );
  }
}

/// بطاقة الترحيب — التحية، والإجراء الأساسي: ابدأ جلسة.
/// The welcome card: the greeting and the one primary action, start a session.
class _WelcomeCard extends ConsumerWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    final user = ref.watch(currentUserProvider);
    final compact = Breakpoints.isCompact(context);

    final name = (user?.userMetadata?['display_name'] as String?)?.trim();
    final greeting = _greeting(context);

    return Container(
      padding: EdgeInsets.all(compact ? Insets.xl : Insets.section),
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
        children: [
          Text(
            l.workspace,
            style: text.labelSmall?.copyWith(
              color: palette.onHero.withValues(alpha: 0.7),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: Insets.md),
          Text(
            name == null || name.isEmpty
                ? greeting
                : '$greeting${l.comma}$name',
            style: (compact ? text.headlineSmall : text.headlineMedium)
                ?.copyWith(color: palette.onHero),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            l.focusSubtitle,
            style: text.bodyMedium?.copyWith(
              color: palette.onHero.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: Insets.xxl),

          // زرارين بس: واحد أساسي وواحد ثانوي. أكتر من كده بيحوّل البطاقة
          // لقايمة اختيارات بدل ما تكون دعوة واضحة للبدء.
          // Two buttons only: one primary, one secondary. More turns the card
          // into a menu instead of a clear invitation to begin.
          Wrap(
            spacing: Insets.md,
            runSpacing: Insets.md,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: palette.onHero,
                  foregroundColor: palette.heroStart,
                ),
                onPressed: () =>
                    ref.read(sectionProvider.notifier).go(AppSection.timer),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(l.quickStart),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.onHero,
                  side: BorderSide(
                    color: palette.onHero.withValues(alpha: 0.45),
                  ),
                ),
                onPressed: () =>
                    ref.read(sectionProvider.notifier).go(AppSection.summarize),
                icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                label: Text(l.summarizeLecture),
              ),
            ],
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

/// دعوة للمراجعة — بتظهر بس لما يكون في كروت مستحقة.
/// A review prompt, shown only when cards are actually due.
///
/// البطاقة بلون السطح العادي مش بلون مميز: الزرار جواها هو اللي المفروض يلفت
/// النظر، ولو البطاقة نفسها ملونة بيضيع تباينه معاها.
/// The card sits on the ordinary surface rather than an accent: the button
/// inside is what should draw the eye, and an accent card washes it out.
class _ReviewPrompt extends ConsumerWidget {
  const _ReviewPrompt({required this.cards});

  final List<Flashcard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    final info = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(Insets.sm),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: Radii.all(Radii.sm),
          ),
          child: Icon(Icons.style_rounded,
              color: scheme.onPrimaryContainer, size: 19),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Text(
            l.cardsWaiting(cards.length),
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );

    final button = FilledButton(
      onPressed: () async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => ReviewPage(queue: cards)),
        );
        ref.invalidate(cardsProvider);
        ref.invalidate(weeklyReviewsProvider);
      },
      child: Text(l.reviewNow),
    );

    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: Insets.lg),
                button,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: Insets.lg),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _QuietCard extends StatelessWidget {
  const _QuietCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      padding: Insets.xxl,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_rounded, color: palette.success, size: 20),
          const SizedBox(width: Insets.md),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
