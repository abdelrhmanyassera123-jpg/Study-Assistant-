import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_theme.dart';
import '../../core/design.dart';
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
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(subjectsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.folder_outlined,
              title: l.noSubjectsYet,
              message: l.subjectsEmptyHint,
              action: FilledButton.icon(
                onPressed: () => _openEditor(context, ref, null),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: Text(l.addSubject),
              ),
            );
          }

          return PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // من غير عنوان قسم: اسم الصفحة موجود في الشريط العلوي، وتكراره
                // تحته مباشرة بيبان إهمال.
                // No section title: the page's name is already in the app bar,
                // and repeating it right underneath reads as carelessness.
                Padding(
                  padding: const EdgeInsets.only(
                      top: Insets.md, bottom: Insets.xl),
                  child: Text(
                    l.subjectsHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                CardGrid(
                  children: [
                    for (final s in list)
                      _SubjectCard(
                        subject: s,
                        taskCount: tasks
                            .where((t) => t.subjectId == s.id && !t.isDone)
                            .length,
                        cardCount:
                            cards.where((c) => c.subjectId == s.id).length,
                        noteCount:
                            notes.where((n) => n.subjectId == s.id).length,
                        onEdit: () => _openEditor(context, ref, s),
                        onDelete: () async {
                          final ok = await confirmDelete(context,
                              extra: l.subjectDeleteWarning);
                          if (!ok) return;
                          await ref.read(repositoryProvider).deleteSubject(s.id);
                          invalidateAll(ref);
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openEditor(
      BuildContext context, WidgetRef ref, Subject? existing) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SubjectEditor(existing: existing),
    );
    if (saved == true) invalidateAll(ref);
  }
}

/// بطاقة المادة — لون المادة شريط جانبي، وتحتها عدّادات كل نوع محتوى.
/// A subject card: its colour is an edge stripe, with a count per content type
/// underneath.
///
/// اللون كشريط مش كخلفية: المواد كتير، ولو كل بطاقة اتملت لون الصفحة بتبقى
/// صاخبة وأسماء المواد بتضيع فيها.
/// The colour is a stripe, not a fill: there are many subjects, and filling
/// each card turns the page loud enough to lose the names in it.
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
    final text = Theme.of(context).textTheme;

    return AppCard(
      padding: 0,
      onTap: onEdit,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: subject.color),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                    Insets.lg, Insets.lg, Insets.sm, Insets.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            subject.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleSmall,
                          ),
                          const SizedBox(height: Insets.md),
                          Wrap(
                            spacing: Insets.lg,
                            runSpacing: Insets.sm,
                            children: [
                              _Count(
                                  icon: Icons.task_alt_rounded,
                                  count: taskCount,
                                  label: l.countTasks),
                              _Count(
                                  icon: Icons.style_rounded,
                                  count: cardCount,
                                  label: l.countCards),
                              _Count(
                                  icon: Icons.article_outlined,
                                  count: noteCount,
                                  label: l.countNotes),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l.delete,
                      iconSize: 19,
                      onPressed: onDelete,
                      icon: Icon(Icons.delete_outline_rounded,
                          color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.count, required this.label});

  final IconData icon;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: Insets.xs),
        Text(
          '$count',
          style: text.labelMedium?.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(width: Insets.xs),
        Text(
          label,
          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
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
        left: Insets.xl,
        right: Insets.xl,
        top: Insets.xs,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.xxl,
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
          const SizedBox(height: Insets.xl),
          TextField(
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(labelText: l.subjectName),
          ),
          const SizedBox(height: Insets.xl),
          Text(l.subjectColor, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.md,
            runSpacing: Insets.md,
            children: [
              for (final c in AppTheme.subjectPalette)
                InkWell(
                  onTap: () => setState(() => _color = c),
                  customBorder: const CircleBorder(),
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
          const SizedBox(height: Insets.section),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(l.save),
          ),
        ],
      ),
    );
  }
}
