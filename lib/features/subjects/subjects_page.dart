import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class SubjectsPage extends ConsumerWidget {
  const SubjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final subjects = ref.watch(subjectsProvider);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final cards = ref.watch(cardsProvider).value ?? const <Flashcard>[];
    final notes = ref.watch(notesProvider).value ?? const <Note>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addSubject),
      ),
      body: subjects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(subjectsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.folder_outlined,
              message: l.noSubjectsYet,
              action: FilledButton.icon(
                onPressed: () => _openEditor(context, ref, null),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.addSubject),
              ),
            );
          }
          return PageBody(
            child: Column(
              children: [
                for (final s in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SubjectCard(
                      subject: s,
                      taskCount: tasks.where((t) => t.subjectId == s.id && !t.isDone).length,
                      cardCount: cards.where((c) => c.subjectId == s.id).length,
                      noteCount: notes.where((n) => n.subjectId == s.id).length,
                      onEdit: () => _openEditor(context, ref, s),
                      onDelete: () async {
                        final ok = await confirmDelete(context, extra: l.subjectDeleteWarning);
                        if (!ok) return;
                        await ref.read(repositoryProvider).deleteSubject(s.id);
                        invalidateAll(ref);
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, WidgetRef ref, Subject? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SubjectEditor(existing: existing),
    );
    if (saved == true) invalidateAll(ref);
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({
    required this.subject,
    required this.taskCount,
    required this.cardCount,
    required this.noteCount,
    required this.onEdit,
    required this.onDelete,
  });

  final Subject subject;
  final int taskCount;
  final int cardCount;
  final int noteCount;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: subject.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.book_rounded, color: subject.color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$taskCount ${l.tasks} · $cardCount ${l.flashcards} · $noteCount ${l.notes}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l.delete,
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubjectEditor extends ConsumerStatefulWidget {
  const _SubjectEditor({this.existing});

  final Subject? existing;

  @override
  ConsumerState<_SubjectEditor> createState() => _SubjectEditorState();
}

class _SubjectEditorState extends ConsumerState<_SubjectEditor> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late Color _color = widget.existing?.color ?? AppTheme.subjectPalette.first;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);

    final repo = ref.read(repositoryProvider);
    final existing = widget.existing;
    final subject = Subject(
      id: existing?.id ?? '',
      name: name,
      color: _color,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    try {
      if (existing == null) {
        await repo.addSubject(subject);
      } else {
        await repo.updateSubject(subject);
      }
      if (mounted) Navigator.pop(context, true);
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
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? l.addSubject : l.editSubject,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: l.subjectName),
          ),
          const SizedBox(height: 20),
          Text(l.subjectColor, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in AppTheme.subjectPalette)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: c.toARGB32() == _color.toARGB32()
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                    child: c.toARGB32() == _color.toARGB32()
                        ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l.save),
          ),
        ],
      ),
    );
  }
}
