import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(cardsProvider)),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.style_outlined,
              message: l.noCardsYet,
              action: FilledButton.icon(
                onPressed: () => openCardEditor(context, ref, null),
                icon: const Icon(Icons.add_rounded),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: l.totalCards,
                        value: '${filtered.length}',
                        icon: Icons.style_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        label: l.dueNow,
                        value: '${due.length}',
                        icon: Icons.notifications_active_rounded,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: StatTile(
                        label: l.newCards,
                        value: '${filtered.where((c) => c.isNew).length}',
                        icon: Icons.fiber_new_rounded,
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: due.isEmpty
                      ? null
                      : () async {
                          await Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => ReviewPage(queue: due),
                            ),
                          );
                          ref.invalidate(cardsProvider);
                          ref.invalidate(weeklyReviewsProvider);
                        },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(due.isEmpty ? l.nothingDueNow : '${l.startReview} (${due.length})'),
                ),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: Text(l.all),
                          selected: _subjectFilter == null,
                          onSelected: (_) => setState(() => _subjectFilter = null),
                        ),
                        for (final s in subjects) ...[
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(s.name),
                            selected: _subjectFilter == s.id,
                            selectedColor: s.color.withValues(alpha: 0.2),
                            onSelected: (_) => setState(
                              () => _subjectFilter = _subjectFilter == s.id ? null : s.id,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                SectionHeader(l.flashcards),
                for (final c in filtered)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _CardTile(card: c),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CardTile extends ConsumerWidget {
  const _CardTile({required this.card});

  final Flashcard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final subject = ref.watch(subjectMapProvider)[card.subjectId];

    return Card(
      child: InkWell(
        onTap: () => openCardEditor(context, ref, card),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card.front,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                card.back,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (subject != null) ...[
                    SubjectChip(subject: subject, dense: true),
                    const SizedBox(width: 8),
                  ],
                  Icon(Icons.schedule_rounded, size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    card.isNew ? l.newCards : Fmt.inDays(context, card.dueAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: card.isDue ? scheme.error : scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 14),
            TextField(
              controller: _back,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l.cardBack,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            SubjectDropdown(
              subjects: subjects,
              value: _subjectId,
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _busy ? null : () => _save(), child: Text(l.save)),
            if (existing == null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _save(addAnother: true),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.isAr ? 'حفظ وإضافة تاني' : 'Save and add another'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
