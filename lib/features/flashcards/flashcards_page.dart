import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'review_page.dart';

class FlashcardsPage extends ConsumerStatefulWidget {
  const FlashcardsPage({super.key});

  @override
  ConsumerState<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends ConsumerState<FlashcardsPage> {
  String? _subjectFilter;

  Future<void> _review(List<Flashcard> due) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReviewPage(queue: due)),
    );
    ref.invalidate(cardsProvider);
    ref.invalidate(weeklyReviewsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cardsAsync = ref.watch(cardsProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openCardEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addCard),
      ),
      body: cardsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(cardsProvider)),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.style_outlined,
              title: l.noCardsYet,
              message: l.cardsEmptyHint,
              action: FilledButton.icon(
                onPressed: () => openCardEditor(context, ref, null),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: Text(l.addCard),
              ),
            );
          }

          final filtered = _subjectFilter == null
              ? all
              : all.where((c) => c.subjectId == _subjectFilter).toList();
          final due = filtered.where((c) => c.isDue).toList();

          return PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Insets.sm),
                _ReviewCard(due: due, onStart: () => _review(due)),
                const SizedBox(height: Insets.lg),
                StatGrid(
                  children: [
                    StatTile(
                      label: l.totalCards,
                      value: '${filtered.length}',
                      icon: Icons.style_rounded,
                    ),
                    StatTile(
                      label: l.dueNow,
                      value: '${due.length}',
                      icon: Icons.notifications_active_rounded,
                      color: due.isEmpty
                          ? null
                          : Theme.of(context).colorScheme.error,
                    ),
                    StatTile(
                      label: l.newCards,
                      value: '${filtered.where((c) => c.isNew).length}',
                      icon: Icons.fiber_new_rounded,
                      color: AppPalette.of(context).warm,
                    ),
                  ],
                ),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: Insets.lg),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterPill(
                          label: l.all,
                          selected: _subjectFilter == null,
                          onTap: () => setState(() => _subjectFilter = null),
                        ),
                        for (final s in subjects) ...[
                          const SizedBox(width: Insets.sm),
                          FilterPill(
                            label: s.name,
                            dot: s.color,
                            selected: _subjectFilter == s.id,
                            onTap: () => setState(
                              () => _subjectFilter =
                                  _subjectFilter == s.id ? null : s.id,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                SectionHeader(l.allCards, subtitle: l.cardsListHint),
                if (filtered.isEmpty)
                  EmptyState(
                    icon: Icons.filter_alt_off_rounded,
                    message: l.noResults,
                  )
                else
                  CardGrid(
                    children: [
                      for (final c in filtered) _CardTile(card: c),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// دعوة المراجعة — الإجراء الأساسي للصفحة، وله بطاقة مش زرار سايب.
/// The review call to action: the page's primary action, given a card of its
/// own rather than a button floating on the background.
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.due, required this.onStart});

  final List<Flashcard> due;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    final ready = due.isNotEmpty;

    final info = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(Insets.md),
          decoration: BoxDecoration(
            color: ready
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: Radii.all(Radii.md),
          ),
          child: Icon(
            ready ? Icons.bolt_rounded : Icons.check_rounded,
            size: 21,
            color: ready ? scheme.onPrimaryContainer : palette.success,
          ),
        ),
        const SizedBox(width: Insets.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ready ? l.cardsWaiting(due.length) : l.allCaughtUp,
                style: text.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                ready ? l.reviewCardHint : l.nothingDueNow,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    final button = FilledButton.icon(
      onPressed: ready ? onStart : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(l.startReview),
    );

    return AppCard(
      // على الموبايل الزرار بيتحت النص بعرض البطاقة، وعلى الشاشة الواسعة جنبه.
      // On a phone the button sits under the text at full width; on a wide
      // screen it sits beside it.
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 460) {
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

/// بطاقة الكارت في القايمة — السؤال بارز والإجابة سطر خافت تحته.
/// A card in the list: the question leads, the answer sits under it, quieter.
class _CardTile extends ConsumerWidget {
  const _CardTile({required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subject = ref.watch(subjectMapProvider)[card.subjectId];

    return AppCard(
      padding: Insets.lg,
      onTap: () => openCardEditor(context, ref, card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.front,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            card.back,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: [
              if (subject != null) ...[
                Flexible(child: SubjectChip(subject: subject, dense: true)),
                const SizedBox(width: Insets.sm),
              ],
              const Spacer(),
              Icon(Icons.schedule_rounded,
                  size: 13,
                  color: card.isDue ? scheme.error : scheme.onSurfaceVariant),
              const SizedBox(width: Insets.xs),
              Text(
                card.isNew ? l.newCards : Fmt.inDays(context, card.dueAt),
                style: text.labelSmall?.copyWith(
                  color: card.isDue ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openCardEditor(BuildContext context, WidgetRef ref, Flashcard? existing) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CardEditor(existing: existing),
  );
  if (changed == true) ref.invalidate(cardsProvider);
}

class _CardEditor extends ConsumerStatefulWidget {
  const _CardEditor({this.existing});

  final Flashcard? existing;

  @override
  ConsumerState<_CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends ConsumerState<_CardEditor> {
  late final _front = TextEditingController(text: widget.existing?.front ?? '');
  late final _back = TextEditingController(text: widget.existing?.back ?? '');
  late String? _subjectId = widget.existing?.subjectId;
  bool _busy = false;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    super.dispose();
  }

  Future<void> _save({bool addAnother = false}) async {
    final front = _front.text.trim();
    final back = _back.text.trim();
    if (front.isEmpty || back.isEmpty) return;
    setState(() => _busy = true);

    final repo = ref.read(repositoryProvider);
    final existing = widget.existing;

    try {
      if (existing == null) {
        await repo.addCard(Flashcard(
          id: '',
          front: front,
          back: back,
          subjectId: _subjectId,
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        ));
      } else {
        await repo.updateCard(
          existing.copyWith(front: front, back: back, subjectId: _subjectId),
        );
      }

      if (!mounted) return;
      if (addAnother) {
        // فضّي الخانات وسيب المادة زي ما هي — إدخال كروت كتير ورا بعض.
        // Clear the fields but keep the subject, for entering many cards in a row.
        _front.clear();
        _back.clear();
        ref.invalidate(cardsProvider);
        setState(() => _busy = false);
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final existing = widget.existing;

    return Padding(
      padding: EdgeInsets.only(
        left: Insets.xl,
        right: Insets.xl,
        top: Insets.xs,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.xxl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    existing == null ? l.addCard : l.editCard,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (existing != null)
                  IconButton(
                    tooltip: l.delete,
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: () async {
                      if (!await confirmDelete(context)) return;
                      await ref.read(repositoryProvider).deleteCard(existing.id);
                      if (context.mounted) Navigator.pop(context, true);
                    },
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _front,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l.cardFront,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _back,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l.cardBack,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: Insets.lg),
            SubjectDropdown(
              subjects: subjects,
              value: _subjectId,
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: Insets.xxl),
            FilledButton(onPressed: _busy ? null : () => _save(), child: Text(l.save)),
            if (existing == null) ...[
              const SizedBox(height: Insets.sm),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _save(addAnother: true),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.saveAndAddAnother),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
