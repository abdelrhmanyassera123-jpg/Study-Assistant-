import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

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

    if (_queue.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.celebration_rounded,
          message: '${l.reviewFinished}\n$_reviewed ${l.cardsReviewed}',
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
          child: LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 3),
        ),
      ),
      body: PageBody(
        maxWidth: 680,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            if (subject != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: SubjectChip(subject: subject),
              ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  children: [
                    Text(
                      card.front,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                    ),
                    if (_revealed) ...[
                      const SizedBox(height: 24),
                      Divider(color: scheme.outlineVariant),
                      const SizedBox(height: 24),
                      Text(
                        card.back,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: scheme.primary,
                              height: 1.6,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!_revealed)
              FilledButton(
                onPressed: () => setState(() => _revealed = true),
                child: Text(l.showAnswer),
              )
            else
              _GradeButtons(onGrade: _busy ? null : _grade),
          ],
        ),
      ),
    );
  }
}

class _GradeButtons extends StatelessWidget {
  const _GradeButtons({required this.onGrade});

  final void Function(ReviewGrade)? onGrade;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    final buttons = <(ReviewGrade, String, Color)>[
      (ReviewGrade.again, l.againLabel, scheme.error),
      (ReviewGrade.hard, l.hardLabel, const Color(0xFFF59E0B)),
      (ReviewGrade.good, l.goodLabel, const Color(0xFF10B981)),
      (ReviewGrade.easy, l.easyLabel, const Color(0xFF0EA5E9)),
    ];

    return Row(
      children: [
        for (final (grade, label, color) in buttons) ...[
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
              ),
              onPressed: onGrade == null ? null : () => onGrade!(grade),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          if (grade != ReviewGrade.easy) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
