import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../summarize/summarizer.dart';
import '../summarize/summarizer_provider.dart';
import 'study_ai.dart';

/// بيطلّع كروت من محتوى، وبيسيبك تراجعها قبل ما تتحفظ.
/// Generates cards from material and lets you check them before they are saved.
///
/// المراجعة قبل الحفظ مش خطوة زيادة: الكارت الغلط بيتحفظ في نظام مراجعة هيرجّعه
/// لك شهور — وتصليحه بعدين أصعب من رميه دلوقتي.
/// Reviewing before saving is not a redundant step: a wrong card enters a
/// review system that will hand it back to you for months, and fixing it later
/// is harder than dropping it now.
Future<void> openCardMaker(
  BuildContext context,
  WidgetRef ref, {
  required String source,
  String? subjectId,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CardMaker(source: source, subjectId: subjectId),
  );
  if (saved == true) ref.invalidate(cardsProvider);
}

class _CardMaker extends ConsumerStatefulWidget {
  const _CardMaker({required this.source, this.subjectId});

  final String source;
  final String? subjectId;

  @override
  ConsumerState<_CardMaker> createState() => _CardMakerState();
}

class _CardMakerState extends ConsumerState<_CardMaker> {
  List<GeneratedCard>? _cards;
  final Set<int> _dropped = {};
  late String? _subjectId = widget.subjectId;
  bool _busy = false;
  bool _saving = false;
  SummarizerException? _error;

  @override
  void initState() {
    super.initState();
    // بيبدأ يشتغل من غير ضغطة تانية: المستخدم دوس "اعمل كروت" خلاص.
    // It starts without a second press: the user already pressed "make cards".
    WidgetsBinding.instance.addPostFrameCallback((_) => _make());
  }

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _error = null;
      _cards = null;
      _dropped.clear();
    });
    try {
      final cards =
          await ref.read(activeSummarizerProvider).makeCards(widget.source);
      if (mounted) setState(() => _cards = cards);
    } on SummarizerException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final cards = _cards;
    if (cards == null) return;

    final kept = [
      for (var i = 0; i < cards.length; i++)
        if (!_dropped.contains(i)) cards[i],
    ];
    if (kept.isEmpty) return;

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    try {
      for (final card in kept) {
        await repo.addCard(Flashcard(
          id: '',
          front: readableMath(card.front),
          back: readableMath(card.back),
          subjectId: _subjectId,
          // مستحق دلوقتي: الكارت الجديد المفروض يتشاف في أول مراجعة.
          // Due now: a new card should appear in the very next review.
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) {
        showSnack(context, context.l.cardsSaved(kept.length));
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final cards = _cards;
    final kept = cards == null ? 0 : cards.length - _dropped.length;

    return Padding(
      padding: EdgeInsets.only(
        left: Insets.xl,
        right: Insets.xl,
        top: Insets.xs,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.xxl,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.makeCards, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: Insets.xs),
            Text(
              l.makeCardsHint,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Insets.lg),

            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.xl),
                child: ProgressBar(label: l.makingCards),
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

            if (cards != null) ...[
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cards.length,
                  itemBuilder: (context, i) => _CardRow(
                    card: cards[i],
                    dropped: _dropped.contains(i),
                    onToggle: () => setState(() {
                      if (!_dropped.remove(i)) _dropped.add(i);
                    }),
                  ),
                ),
              ),
              const SizedBox(height: Insets.lg),
              SubjectDropdown(
                subjects: subjects,
                value: _subjectId,
                onChanged: (v) => setState(() => _subjectId = v),
              ),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving || kept == 0 ? null : _save,
                      icon: const Icon(Icons.save_alt_rounded, size: 19),
                      label: Text(l.saveCards(kept)),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  IconButton(
                    tooltip: l.retry,
                    onPressed: _saving ? null : _make,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({
    required this.card,
    required this.dropped,
    required this.onToggle,
  });

  final GeneratedCard card;
  final bool dropped;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Opacity(
      opacity: dropped ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Insets.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: !dropped, onChanged: (_) => onToggle()),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: Insets.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.front,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration:
                            dropped ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.back,
                      style: text.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
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
