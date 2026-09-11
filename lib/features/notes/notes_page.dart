import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../study_ai/study_tools_row.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final notesAsync = ref.watch(notesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openNoteEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addNote),
      ),
      body: notesAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(notesProvider)),
        data: (all) {
          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              title: l.noNotesYet,
              message: l.notesEmptyHint,
              action: FilledButton.icon(
                onPressed: () => openNoteEditor(context, ref, null),
                icon: const Icon(Icons.add_rounded, size: 19),
                label: Text(l.addNote),
              ),
            );
          }

          final q = _query.trim().toLowerCase();
          final visible = q.isEmpty
              ? all
              : all
                  .where((n) =>
                      n.title.toLowerCase().contains(q) ||
                      n.body.toLowerCase().contains(q))
                  .toList();

          return PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Insets.sm),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: l.searchNotes,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: l.clear,
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: Insets.md),
                Text(
                  l.notesCount(visible.length),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: Insets.lg),
                if (visible.isEmpty)
                  EmptyState(
                    icon: Icons.search_off_rounded,
                    message: l.noResults,
                  )
                else
                  CardGrid(
                    children: [
                      for (final n in visible) _NoteCard(note: n),
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

/// بطاقة ملاحظة — عنوان، مقتطف، وتاريخ آخر تعديل.
/// A note card: its title, an excerpt, and when it was last touched.
class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subject = ref.watch(subjectMapProvider)[note.subjectId];

    return AppCard(
      onTap: () => openNoteEditor(context, ref, note),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            note.title.isEmpty ? context.l.noteTitle : note.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall,
          ),
          if (note.body.isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            Text(
              readableMath(note.body),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              if (subject != null) ...[
                SubjectChip(subject: subject, dense: true),
                const SizedBox(width: Insets.sm),
              ],
              const Spacer(),
              Text(
                Fmt.date(context, note.updatedAt),
                style:
                    text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> openNoteEditor(BuildContext context, WidgetRef ref, Note? existing) async {
  final changed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => _NoteEditorPage(existing: existing)),
  );
  if (changed == true) ref.invalidate(notesProvider);
}

/// محرر الملاحظة بصفحة كاملة — الملاحظات بتبقى طويلة.
/// A full-page note editor, since notes get long.
class _NoteEditorPage extends ConsumerStatefulWidget {
  const _NoteEditorPage({this.existing});

  final Note? existing;

  @override
  ConsumerState<_NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<_NoteEditorPage> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _body = TextEditingController(text: widget.existing?.body ?? '');
  late String? _subjectId = widget.existing?.subjectId;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty && body.isEmpty) {
      Navigator.pop(context, false);
      return;
    }
    setState(() => _busy = true);

    final repo = ref.read(repositoryProvider);
    final existing = widget.existing;
    final note = Note(
      id: existing?.id ?? '',
      title: title,
      body: body,
      subjectId: _subjectId,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      if (existing == null) {
        await repo.addNote(note);
      } else {
        await repo.updateNote(note);
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
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final existing = widget.existing;

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? l.addNote : l.editNote),
        actions: [
          if (existing != null)
            IconButton(
              tooltip: l.delete,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (!await confirmDelete(context)) return;
                await ref.read(repositoryProvider).deleteNote(existing.id);
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
            child: FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(l.save),
            ),
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 820,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),
            TextField(
              controller: _title,
              autofocus: existing == null,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: l.noteTitle),
            ),
            const SizedBox(height: Insets.lg),
            SubjectDropdown(
              subjects: subjects,
              value: _subjectId,
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _body,
              maxLines: null,
              minLines: 12,
              keyboardType: TextInputType.multiline,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.noteBody,
                alignLabelWithHint: true,
              ),
            ),

            // الأدوات على محتوى الملاحظة نفسه: الملاحظة هنا هي المحاضرة
            // الملخّصة، وهي أنسب حاجة تتعمل منها كروت أو تتسأل فيها.
            // The tools work on the note's own text: a note here is the
            // summarized lecture, and it is the best thing to build cards from
            // or to ask about.
            StudyToolsSection(
              title: _title.text.trim().isEmpty ? l.theSummary : _title.text,
              source: _body.text,
              subjectId: _subjectId,
            ),
          ],
        ),
      ),
    );
  }
}
