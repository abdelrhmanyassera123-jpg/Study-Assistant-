import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/study_text.dart';
import '../study_ai/exam_page.dart';
import '../summarize/file_input.dart';
import '../summarize/image_shrink.dart';
import '../summarize/summarizer.dart';
import '../summarize/summarizer_provider.dart';
import 'past_exam.dart';

/// أسئلة امتحانات مادة، بتتعاد تحميلها لما الحساب يتغيّر.
/// A subject's past-exam questions, reloaded when the account changes.
final pastQuestionsProvider =
    FutureProvider.family<List<PastQuestion>, String>((ref, subjectId) async {
  ref.watch(currentUserIdProvider);
  final rows = await ref
      .watch(supabaseProvider)
      .from('past_questions')
      .select()
      .eq('subject_id', subjectId)
      .order('created_at', ascending: true);
  return rows.map(PastQuestion.fromRow).toList();
});

/// كل الأسئلة كنص، بحد أقصى عشان ما تاكلش البرومبت كله.
/// All the questions as text, capped so they do not swallow the prompt.
String pastExamsText(List<PastQuestion> questions, {int maxChars = 30000}) {
  final text = questions.map((q) => q.toPlainText()).join('\n');
  return text.length <= maxChars ? text : text.substring(0, maxChars);
}

Future<void> openPastExams(BuildContext context, Subject subject) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => PastExamsPage(subject: subject),
    ));

/// امتحانات السنين اللي فاتت لمادة: الأسئلة، اللي بيتكرر، وامتحان بنفس الشكل.
/// A subject's previous years' exams: the questions, what keeps recurring,
/// and a mock in the same shape.
class PastExamsPage extends ConsumerStatefulWidget {
  const PastExamsPage({super.key, required this.subject});

  final Subject subject;

  @override
  ConsumerState<PastExamsPage> createState() => _PastExamsPageState();
}

class _PastExamsPageState extends ConsumerState<PastExamsPage> {
  bool _busy = false;

  List<Note> get _notes => (ref.read(notesProvider).value ?? const <Note>[])
      .where((n) => n.subjectId == widget.subject.id)
      .toList();

  Future<void> _addExam() async {
    final l = context.l;
    final picked = await pickLocalFiles(extensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf']);
    if (picked.isEmpty || !mounted) return;

    final count = (ref.read(pastQuestionsProvider(widget.subject.id)).value ?? const [])
        .map((q) => q.examLabel)
        .toSet()
        .length;
    final label = await _askLabel(l.pastExamDefaultLabel(count + 1));
    if (label == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final files = <LectureFile>[];
      for (final f in picked) {
        final ready = f.mimeType == 'application/pdf' ? f : await shrinkImage(f);
        files.add(LectureFile(name: ready.name, mimeType: ready.mimeType, bytes: ready.bytes));
      }
      final rows = await ref.read(activeSummarizerProvider).extractPastExam(
            files: files,
            lectures: _notes.map((n) => n.title).toList(),
          );
      final questions = [
        for (final r in rows) ?PastQuestion.fromModel(r, label),
      ];
      final db = ref.read(supabaseProvider);
      await db.from('past_questions').insert([
        for (final q in questions)
          {...q.toInsert(widget.subject.id), 'user_id': db.auth.currentUser!.id},
      ]);
      ref.invalidate(pastQuestionsProvider(widget.subject.id));
      if (mounted) showSnack(context, l.pastExamAdded(questions.length));
    } on SummarizerException catch (e) {
      if (mounted) showSnack(context, e.toString());
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askLabel(String initial) {
    final controller = TextEditingController(text: initial);
    final l = context.l;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.pastExamLabelTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l.pastExamLabelHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              controller.text.trim().isEmpty ? initial : controller.text.trim(),
            ),
            child: Text(l.pastExamRead),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _deleteExam(String label) async {
    final ok = await confirmDelete(context);
    if (!ok) return;
    await ref
        .read(supabaseProvider)
        .from('past_questions')
        .delete()
        .eq('subject_id', widget.subject.id)
        .eq('exam_label', label);
    ref.invalidate(pastQuestionsProvider(widget.subject.id));
  }

  void _mockExam(List<PastQuestion> questions) {
    final notes = _notes;
    final source = notes.isEmpty
        ? pastExamsText(questions)
        : notes.map((n) => '## ${n.title}\n${n.body}').join('\n\n');
    openExamPage(
      context,
      title: widget.subject.name,
      source: source,
      pastExams: pastExamsText(questions),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    ref.watch(notesProvider);
    final async = ref.watch(pastQuestionsProvider(widget.subject.id));
    final questions = async.value ?? const <PastQuestion>[];
    final exams = <String, List<PastQuestion>>{};
    for (final q in questions) {
      exams.putIfAbsent(q.examLabel, () => []).add(q);
    }
    final hot = hotTopics(questions).take(12).toList();

    return Scaffold(
      appBar: AppBar(title: Text('${l.pastExams} — ${widget.subject.name}')),
      body: PageBody(
        maxWidth: 820,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),
            InfoBanner(message: l.pastExamsHint),
            const SizedBox(height: Insets.lg),
            if (_busy)
              ProgressBar(label: l.readingPastExam)
            else
              FilledButton.icon(
                onPressed: _addExam,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 19),
                label: Text(l.addPastExam),
              ),
            if (async.isLoading && questions.isEmpty) ...[
              const SizedBox(height: Insets.xl),
              const LoadingView(),
            ],
            if (questions.isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              OutlinedButton.icon(
                onPressed: () => _mockExam(questions),
                icon: const Icon(Icons.quiz_outlined, size: 19),
                label: Text(l.mockLikePastExams),
              ),
              const SizedBox(height: Insets.xl),
              Text(l.hotTopics, style: text.titleSmall),
              const SizedBox(height: Insets.sm),
              AppCard(
                child: Column(
                  children: [
                    for (final t in hot)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: t.exams > 1
                              ? scheme.errorContainer
                              : scheme.surfaceContainerHighest,
                          child: Text('${t.exams}',
                              style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        title: Text(t.topic),
                        subtitle: Text([
                          l.askedInExams(t.exams, exams.length),
                          if (t.lecture.isNotEmpty) t.lecture,
                        ].join(' · ')),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.xl),
              for (final entry in exams.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.md),
                  child: AppCard(
                    padding: Insets.sm,
                    child: ExpansionTile(
                      shape: const Border(),
                      title: Text(entry.key),
                      subtitle: Text(l.questionsCount(entry.value.length)),
                      trailing: IconButton(
                        tooltip: l.delete,
                        icon: const Icon(Icons.delete_outline_rounded, size: 19),
                        onPressed: () => _deleteExam(entry.key),
                      ),
                      children: [
                        for (final q in entry.value)
                          ListTile(
                            leading: Icon(
                              q.isChoice ? Icons.radio_button_checked : Icons.edit_note_rounded,
                              size: 20,
                            ),
                            title: StudyText(q.toPlainText().substring(2), selectable: false),
                            subtitle: Text([
                              q.isChoice ? l.choiceQuestion : l.writtenQuestion,
                              if (q.lecture.isNotEmpty) q.lecture,
                              if (q.answer.isNotEmpty) '${l.answerLabel}: ${q.answer}',
                            ].join(' · ')),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
