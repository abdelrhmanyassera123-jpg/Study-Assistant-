import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(notesProvider)),
        data: (all) {
          final q = _query.trim().toLowerCase();
          final visible = q.isEmpty
              ? all
              : all
                  .where((n) =>
                      n.title.toLowerCase().contains(q) || n.body.toLowerCase().contains(q))
                  .toList();

          if (all.isEmpty) {
            return EmptyState(
              icon: Icons.description_outlined,
              message: l.noNotesYet,
              action: FilledButton.icon(
                onPressed: () => openNoteEditor(context, ref, null),
                icon: const Icon(Icons.add_rounded),
                label: Text(l.addNote),
              ),
            );
          }

          return PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l.searchNotes,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                if (visible.isEmpty)
                  EmptyState(icon: Icons.search_off_rounded, message: l.noResults)
                else
                  for (final n in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _NoteCard(note: n),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NoteCard extends ConsumerWidget {
  const _NoteCard({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final subject = ref.watch(subjectMapProvider)[note.subjectId];

    return Card(
      child: InkWell(
        onTap: () => openNoteEditor(context, ref, note),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? context.l.noteTitle : note.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    Fmt.date(context, note.updatedAt),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
              if (note.body.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  note.body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
                ),
              ],
              if (subject != null) ...[
                const SizedBox(height: 12),
                SubjectChip(subject: subject, dense: true),
              ],
            ],
          ),
        ),
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
          TextButton(onPressed: _busy ? null : _save, child: Text(l.save)),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              autofocus: existing == null,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(labelText: l.noteTitle),
            ),
            const SizedBox(height: 14),
            SubjectDropdown(
              subjects: subjects,
              value: _subjectId,
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _body,
              maxLines: null,
              minLines: 12,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                labelText: l.noteBody,
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
