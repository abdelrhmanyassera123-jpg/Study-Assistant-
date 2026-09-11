import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../widgets/common.dart';
import '../../widgets/study_text.dart';
import '../summarize/summarizer.dart';
import '../summarize/summarizer_provider.dart';
import 'study_ai.dart';

Future<void> openExamPage(
  BuildContext context, {
  required String title,
  required String source,
}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ExamPage(title: title, source: source),
      ),
    );

/// امتحان تجريبي على محاضرة، بتصحيح وتشخيص.
/// A mock exam on one lecture, marked and diagnosed.
///
/// الاختيار من متعدد بيتصحح عندنا: الإجابة الصح معروفة من ساعة ما السؤال
/// اتعمل، فمفيش داعي لنداء تاني. المقالي بس هو اللي بيروح للموديل.
/// Multiple choice is marked here: the right answer has been known since the
/// question was made, so a second call buys nothing. Only the written answers
/// go to the model.
class ExamPage extends ConsumerStatefulWidget {
  const ExamPage({super.key, required this.title, required this.source});

  final String title;
  final String source;

  @override
  ConsumerState<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends ConsumerState<ExamPage> {
  List<ExamQuestion>? _questions;
  final Map<int, int> _picked = {};
  final Map<int, TextEditingController> _written = {};

  ExamResult? _result;
  bool _busy = false;
  bool _marking = false;
  SummarizerException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _make());
  }

  @override
  void dispose() {
    for (final c in _written.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _error = null;
      _questions = null;
      _result = null;
      _picked.clear();
    });
    try {
      final questions =
          await ref.read(activeSummarizerProvider).makeExam(source: widget.source);
      if (!mounted) return;
      setState(() {
        _questions = questions;
        for (var i = 0; i < questions.length; i++) {
          if (!questions[i].isChoice) {
            _written[i] = TextEditingController();
          }
        }
      });
    } on SummarizerException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mark() async {
    final questions = _questions;
    if (questions == null) return;

    final written = <AnsweredQuestion>[
      for (var i = 0; i < questions.length; i++)
        if (!questions[i].isChoice)
          AnsweredQuestion(
            index: i,
            question: questions[i].question,
            expected: questions[i].modelAnswer,
            answer: _written[i]?.text ?? '',
          ),
    ];

    // من غير أسئلة مقالية مفيش حاجة تروح للموديل — الاختيارات بتتصحح هنا.
    // With no written questions nothing goes to the model: the choices are
    // marked right here.
    if (written.isEmpty) {
      setState(() => _result = const ExamResult(
            marks: [],
            weakSpots: [],
            advice: '',
          ));
      return;
    }

    setState(() {
      _marking = true;
      _error = null;
    });
    try {
      final result = await ref.read(activeSummarizerProvider).gradeExam(
            source: widget.source,
            answers: written,
          );
      if (mounted) setState(() => _result = result);
    } on SummarizerException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  ({int right, int total}) get _choiceScore {
    final questions = _questions ?? const <ExamQuestion>[];
    var right = 0;
    var total = 0;
    for (var i = 0; i < questions.length; i++) {
      if (!questions[i].isChoice) continue;
      total++;
      if (_picked[i] == questions[i].answerIndex) right++;
    }
    return (right: right, total: total);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final questions = _questions;
    final marked = _result != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.mockExam, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (questions != null && !_marking)
            IconButton(
              tooltip: l.newExam,
              onPressed: _make,
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: PageBody(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),

            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.section),
                child: ProgressBar(label: l.makingExam),
              ),

            if (_error != null)
              InfoBanner(
                message: _error!.hint == null
                    ? _error!.message
                    : '${_error!.message}\n${_error!.hint}',
                icon: Icons.error_outline_rounded,
                tone: BannerTone.error,
                action: TextButton(onPressed: _make, child: Text(l.retry)),
              ),

            if (questions != null) ...[
              if (marked) _Report(
                score: _choiceScore,
                result: _result!,
                questionCount: questions.length,
              ),

              for (var i = 0; i < questions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Insets.lg),
                  child: _QuestionCard(
                    number: i + 1,
                    question: questions[i],
                    picked: _picked[i],
                    written: _written[i],
                    marked: marked,
                    mark: _result?.marks
                        .where((m) => m.index == i)
                        .cast<WrittenMark?>()
                        .firstWhere((_) => true, orElse: () => null),
                    onPick: marked
                        ? null
                        : (choice) => setState(() => _picked[i] = choice),
                  ),
                ),

              if (!marked)
                FilledButton.icon(
                  onPressed: _marking ? null : _mark,
                  icon: const Icon(Icons.checklist_rounded, size: 19),
                  label: Text(l.markExam),
                ),
              if (_marking) ...[
                const SizedBox(height: Insets.md),
                ProgressBar(label: l.markingExam),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.number,
    required this.question,
    required this.picked,
    required this.written,
    required this.marked,
    required this.mark,
    required this.onPick,
  });

  final int number;
  final ExamQuestion question;
  final int? picked;
  final TextEditingController? written;
  final bool marked;
  final WrittenMark? mark;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: Radii.all(Radii.sm),
                ),
                child: Text('$number', style: text.labelMedium),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: StudyText(question.question, style: text.bodyLarge),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),

          if (question.isChoice)
            for (var c = 0; c < question.choices.length; c++)
              _Choice(
                label: question.choices[c],
                selected: picked == c,
                // بعد التصحيح: الصح بيتعلّم أخضر، واللي اخترته غلط بيتعلّم أحمر.
                // After marking: the right one turns green, and a wrong pick
                // turns red.
                right: marked && c == question.answerIndex,
                wrong: marked && picked == c && c != question.answerIndex,
                onTap: onPick == null ? null : () => onPick!(c),
              )
          else ...[
            TextField(
              controller: written,
              enabled: !marked,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: l.yourAnswer,
                alignLabelWithHint: true,
              ),
            ),
            if (marked && mark != null) ...[
              const SizedBox(height: Insets.md),
              InfoBanner(
                message: mark!.comment.isEmpty
                    ? l.markScore(mark!.score)
                    : '${l.markScore(mark!.score)} — ${mark!.comment}',
                icon: mark!.score >= 0.7
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                tone: mark!.score >= 0.7 ? BannerTone.info : BannerTone.warn,
              ),
            ],
            if (marked && question.modelAnswer.isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              Text(l.modelAnswer, style: text.labelMedium),
              const SizedBox(height: Insets.xs),
              StudyText(
                question.modelAnswer,
                style: text.bodySmall?.copyWith(color: palette.success),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.right,
    required this.wrong,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool right;
  final bool wrong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);

    final border = right
        ? palette.success
        : wrong
            ? scheme.error
            : selected
                ? scheme.primary
                : scheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.all(Radii.md),
          side: BorderSide(color: border, width: right || wrong ? 1.6 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg, vertical: Insets.md),
            child: Row(
              children: [
                Expanded(
                  child: StudyText(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium,
                    selectable: false,
                  ),
                ),
                if (right)
                  Icon(Icons.check_rounded, size: 18, color: palette.success),
                if (wrong)
                  Icon(Icons.close_rounded, size: 18, color: scheme.error),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// النتيجة والتشخيص.
/// The score and the diagnosis.
class _Report extends StatelessWidget {
  const _Report({
    required this.score,
    required this.result,
    required this.questionCount,
  });

  final ({int right, int total}) score;
  final ExamResult result;
  final int questionCount;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;

    final written = result.marks;
    final writtenScore = written.isEmpty
        ? null
        : written.fold<double>(0, (sum, m) => sum + m.score) / written.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.examResult, style: text.titleSmall),
            const SizedBox(height: Insets.lg),
            Row(
              children: [
                if (score.total > 0)
                  Expanded(
                    child: _Score(
                      label: l.multipleChoice,
                      value: '${score.right}/${score.total}',
                      good: score.right >= score.total * 0.7,
                    ),
                  ),
                if (writtenScore != null)
                  Expanded(
                    child: _Score(
                      label: l.written,
                      value: '${(writtenScore * 100).round()}%',
                      good: writtenScore >= 0.7,
                    ),
                  ),
              ],
            ),
            if (result.weakSpots.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              Text(l.weakSpots, style: text.labelMedium),
              const SizedBox(height: Insets.sm),
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final spot in result.weakSpots)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Insets.md, vertical: Insets.sm),
                      decoration: BoxDecoration(
                        color: palette.warmSurface,
                        borderRadius: Radii.all(Radii.sm),
                      ),
                      child: Text(
                        spot,
                        style: text.labelSmall?.copyWith(color: palette.warm),
                      ),
                    ),
                ],
              ),
            ],
            if (result.advice.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              Text(
                result.advice,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.label, required this.value, required this.good});

  final String label;
  final String value;
  final bool good;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: text.headlineSmall?.copyWith(
            color: good ? palette.success : scheme.error,
          ),
        ),
        Text(
          label,
          style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
