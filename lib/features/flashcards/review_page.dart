import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/study_text.dart';

/// جلسة مراجعة: كارت ورا التاني لحد ما الطابور يخلص.
/// A review session: one card at a time until the queue is empty.
///
/// لو المستخدم دوس "تاني"، الكارت بيترجع آخر الطابور عشان يشوفه في نفس الجلسة.
/// Pressing "Again" pushes the card to the back of the queue so it comes
/// back before the session ends.
class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.queue});

  final List<Flashcard> queue;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  late final List<Flashcard> _queue = List.of(widget.queue);
  bool _revealed = false;
  bool _busy = false;
  int _reviewed = 0;
  int _startCount = 0;

  @override
  void initState() {
    super.initState();
    _startCount = _queue.length;
  }

  Future<void> _grade(ReviewGrade grade) async {
    if (_busy || _queue.isEmpty) return;
    setState(() => _busy = true);

    final card = _queue.removeAt(0);
    try {
      await ref.read(repositoryProvider).reviewCard(card, grade);
      _reviewed++;
      if (grade == ReviewGrade.again) {
        // ترجع تاني في نفس الجلسة، بس مش على طول.
        // Comes back this session, but not immediately.
        _queue.add(card);
        _startCount++;
      }
    } catch (e) {
      _queue.insert(0, card);
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) {
        setState(() {
          _revealed = false;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.celebration_rounded,
          title: l.reviewFinished,
          message: '$_reviewed ${l.cardsReviewed}',
          action: FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.close),
          ),
        ),
      );
    }

    final card = _queue.first;
    final subject = ref.watch(subjectMapProvider)[card.subjectId];
    final progress = _startCount == 0 ? 0.0 : _reviewed / _startCount;

    return Scaffold(
      appBar: AppBar(
        title: Text('$_reviewed / $_startCount'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(3),
          child: LinearProgressIndicator(
              value: progress.clamp(0, 1), minHeight: 3),
        ),
      ),
      body: PageBody(
        maxWidth: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.md),
            if (subject != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SubjectChip(subject: subject),
              ),
            const SizedBox(height: Insets.lg),
            AppCard(
              padding: Insets.section,
              child: Column(
                children: [
                  StudyText(
                    card.front,
                    style: text.headlineSmall,
                    selectable: false,
                  ),
                  // الإجابة بتظهر بحركة قصيرة: الكشف لحظة في المراجعة، والانتقال
                  // المفاجئ بيخلي العين تدوّر على اللي اتغيّر.
                  // The answer fades in: revealing is the moment in a review, and
                  // an instant swap leaves the eye hunting for what changed.
                  AnimatedCrossFade(
                    duration: Motion.normal,
                    sizeCurve: Motion.ease,
                    crossFadeState: _revealed
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Column(
                      children: [
                        const SizedBox(height: Insets.xxl),
                        Divider(color: scheme.outlineVariant),
                        const SizedBox(height: Insets.xxl),
                        StudyText(
                          card.back,
                          style: text.titleMedium?.copyWith(
                            color: scheme.primary,
                          ),
                          selectable: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.xxl),
            if (!_revealed)
              FilledButton.icon(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.visibility_rounded, size: 19),
                label: Text(l.showAnswer),
              )
            else
              _GradeButtons(onGrade: _busy ? null : _grade),
          ],
        ),
      ),
    );
  }
}

/// أزرار التقدير — أربعة في صف على الشاشة الواسعة، و2×2 على الموبايل.
/// The grading buttons: four across on a wide screen, 2×2 on a phone.
///
/// أربعة أزرار في صف واحد على 375 بكسل بتضغط النص لحد ما يتقص، والعربي بيتقص
/// أسرع. التقسيم بيخلي كل زرار مساحته كافية.
/// Four buttons in one row at 375px squeeze the labels until they clip, and
/// Arabic clips sooner. Splitting the row gives each button room.
class _GradeButtons extends StatelessWidget {
  const _GradeButtons({required this.onGrade});

  final void Function(ReviewGrade)? onGrade;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);

    // التدرّج من "تاني" لـ"سهل" بيمشي من الأحمر للأخضر الفاتح: الشدة بتقل مع
    // كل درجة، والألوان من التصميم مش أرقام مكتوبة هنا.
    // The ramp from "again" to "easy" runs red to pale green: the weight drops
    // with each grade, and the colours come from the design, not from hex
    // literals written here.
    final grades = <(ReviewGrade, String, Color, Color)>[
      (ReviewGrade.again, l.againLabel, scheme.error, scheme.onError),
      (ReviewGrade.hard, l.hardLabel, palette.warm, palette.onWarm),
      (ReviewGrade.good, l.goodLabel, scheme.primary, scheme.onPrimary),
      (
        ReviewGrade.easy,
        l.easyLabel,
        scheme.primaryContainer,
        scheme.onPrimaryContainer
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 420 ? 4 : 2;
        final width =
            (constraints.maxWidth - Insets.sm * (columns - 1)) / columns;

        return Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          children: [
            for (final (grade, label, bg, fg) in grades)
              SizedBox(
                width: width,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: bg,
                    foregroundColor: fg,
                    padding: const EdgeInsets.symmetric(
                        vertical: Insets.lg, horizontal: Insets.xs),
                  ),
                  onPressed: onGrade == null ? null : () => onGrade!(grade),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
