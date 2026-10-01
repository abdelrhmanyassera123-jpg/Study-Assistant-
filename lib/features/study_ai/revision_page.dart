import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../flashcards/review_page.dart';
import '../summarize/style_profile.dart';
import '../summarize/styled_result.dart';
import '../summarize/summarizer.dart';
import '../summarize/summarizer_provider.dart';
import '../summarize/summary_images.dart';
import '../past_exams/past_exam.dart';
import '../past_exams/past_exams_page.dart';
import 'ask_page.dart';
import 'exam_page.dart';

Future<void> openRevisionPage(BuildContext context, Subject subject) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => RevisionPage(subject: subject),
    ));

/// مراجعة مادة كاملة قبل الامتحان: ملزمة واحدة من كل تلخيصاتها، وامتحان
/// تجريبي عليها كلها، والكروت اللي بتتنسى.
/// A whole subject's revision before the exam: one pack from all its
/// summaries, a mock exam over all of it, and the cards that keep slipping.
class RevisionPage extends ConsumerStatefulWidget {
  const RevisionPage({super.key, required this.subject});

  final Subject subject;

  @override
  ConsumerState<RevisionPage> createState() => _RevisionPageState();
}

class _RevisionPageState extends ConsumerState<RevisionPage> {
  /// سقف المصدر: تلخيصات ترم كامل ممكن تبقى طويلة، والزيادة بتتقص من الأقدم.
  /// A ceiling on the source: a whole term's summaries can run long, and the
  /// excess is cut from the oldest.
  static const _maxChars = 150000;

  SummaryPage? _page;
  bool _busy = false;
  SummarizerException? _error;

  List<Note> get _notes {
    final notes = (ref.read(notesProvider).value ?? const <Note>[])
        .where((n) => n.subjectId == widget.subject.id)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return notes;
  }

  /// الكروت اللي اتنسيت مرة على الأقل أو سهولتها نزلت — دي نقط الضعف.
  /// Cards forgotten at least once or whose ease has dropped: the weak spots.
  List<Flashcard> get _weakCards {
    final cards = (ref.read(cardsProvider).value ?? const <Flashcard>[])
        .where((c) => c.subjectId == widget.subject.id && (c.lapses > 0 || c.ease < 2.3))
        .toList()
      ..sort((a, b) => b.lapses.compareTo(a.lapses));
    return cards;
  }

  String get _source {
    final parts = [
      for (final n in _notes) '## ${n.title}\n${n.body.trim()}',
    ];
    var text = parts.join('\n\n');
    if (text.length > _maxChars) text = text.substring(text.length - _maxChars);
    return text;
  }

  Future<void> _make() async {
    final source = _source;
    if (source.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final weak = _weakCards.take(20).map((c) => '- ${readableMath(c.front)}').join('\n');
    final profiles = ref.read(styleProfilesProvider).value ?? const {};
    final raw = profiles[widget.subject.id] ?? profiles[null];
    final samples = pickStyleSamples(
      ref.read(styleSamplesProvider).value ?? const <StyleSample>[],
      widget.subject.id,
    );

    final brief = StringBuffer()
      ..writeln('(دي كل تلخيصات مادة "${widget.subject.name}" بالترتيب. اعمل منها '
          'ملزمة مراجعة نهائية للامتحان مش تلخيص جديد: رتّبها بالمحاضرات، '
          'وخلّي كل محاضرة عنوان، وركّز على التعريفات والقوانين والأرقام '
          'والمقارنات اللي بتيجي في الامتحان، وحط جدول/مقارنة لما ينفع، '
          'وفي الآخر بلوك highlight بأهم 5 نقط في المادة كلها.)');
    final past = ref.read(pastQuestionsProvider(widget.subject.id)).value ?? const [];
    final hot = hotTopics(past).where((t) => t.exams > 1).take(10).toList();
    if (hot.isNotEmpty) {
      brief
        ..writeln()
        ..writeln('(المواضيع دي بتتكرر في امتحانات السنين اللي فاتت — خليها واضحة ومعلّمة:)')
        ..writeln(hot.map((t) => '- ${t.topic} (في ${t.exams} امتحانات)').join('\n'));
    }
    if (weak.isNotEmpty) {
      brief
        ..writeln()
        ..writeln('(الطالب بيغلط كتير في الأسئلة دي — اديها مساحة وتوضيح زيادة:)')
        ..writeln(weak);
    }
    brief
      ..writeln()
      ..writeln(source);

    try {
      var page = await ref.read(activeSummarizerProvider).summarizeAsPage(
            lectureText: brief.toString(),
            samples: samples,
            profile: raw == null ? const StyleProfile() : StyleProfile.fromJson(raw),
            images: await savedImageMode(),
          );
      page = await attachImages(page, mode: await savedImageMode());
      if (mounted) setState(() => _page = page);
    } on SummarizerException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final page = _page;
    if (page == null) return;
    try {
      await ref.read(repositoryProvider).addNote(Note(
            id: '',
            title: '${context.l.revisionPack} — ${widget.subject.name}',
            body: readableMath(page.toPlainText()),
            subjectId: widget.subject.id,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
      ref.invalidate(notesProvider);
      if (mounted) showSnack(context, context.l.savedAsNote);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    ref.watch(notesProvider);
    ref.watch(cardsProvider);
    final notes = _notes;
    final weak = _weakCards;
    final past = ref.watch(pastQuestionsProvider(widget.subject.id)).value ?? const [];
    final pastCount = past.map((q) => q.examLabel).toSet().length;
    final profiles = ref.watch(styleProfilesProvider).value ?? const {};
    final raw = profiles[widget.subject.id] ?? profiles[null];

    return Scaffold(
      appBar: AppBar(title: Text('${l.examRevision} — ${widget.subject.name}')),
      body: PageBody(
        maxWidth: 860,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),
            if (notes.isEmpty)
              EmptyState(
                icon: Icons.article_outlined,
                title: l.noSummariesForSubject,
                message: l.noSummariesForSubjectHint,
              )
            else ...[
              InfoBanner(message: l.revisionSources(notes.length, weak.length)),
              const SizedBox(height: Insets.lg),
              LayoutBuilder(builder: (context, c) {
                final buttons = [
                  FilledButton.icon(
                    onPressed: _busy ? null : _make,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                    label: Text(_page == null ? l.makeRevisionPack : l.remakeRevisionPack),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openPastExams(context, widget.subject),
                    icon: const Icon(Icons.history_edu_outlined, size: 19),
                    label: Text(l.pastExamsCount(pastCount)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openAskPage(
                      context,
                      title: widget.subject.name,
                      source: _source,
                    ),
                    icon: const Icon(Icons.forum_outlined, size: 19),
                    label: Text(l.askWholeSubject),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => openExamPage(
                      context,
                      title: widget.subject.name,
                      source: _source,
                      pastExams: pastExamsText(past),
                    ),
                    icon: const Icon(Icons.quiz_outlined, size: 19),
                    label: Text(l.subjectMockExam),
                  ),
                  OutlinedButton.icon(
                    onPressed: weak.isEmpty
                        ? null
                        : () => Navigator.of(context).push<void>(MaterialPageRoute(
                              builder: (_) => ReviewPage(queue: weak),
                            )),
                    icon: const Icon(Icons.style_outlined, size: 19),
                    label: Text(l.reviewWeakCards(weak.length)),
                  ),
                ];
                if (c.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final b in buttons)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Insets.sm),
                          child: b,
                        ),
                    ],
                  );
                }
                return Row(children: [
                  for (final b in buttons) ...[
                    Expanded(child: b),
                    if (b != buttons.last) const SizedBox(width: Insets.md),
                  ],
                ]);
              }),
              if (_busy) ...[
                const SizedBox(height: Insets.xl),
                ProgressBar(label: l.makingRevisionPack),
              ],
              if (_error != null) ...[
                const SizedBox(height: Insets.lg),
                InfoBanner(
                  message: _error.toString(),
                  icon: Icons.error_outline_rounded,
                  tone: BannerTone.error,
                ),
              ],
              if (_page != null) ...[
                const SizedBox(height: Insets.xl),
                StyledResult(
                  page: _page!,
                  profile: raw == null ? const StyleProfile() : StyleProfile.fromJson(raw),
                  subjectId: widget.subject.id,
                  source: _source,
                  onPageChanged: (page) => setState(() => _page = page),
                  onSaveNote: _save,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
