import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/tex_text.dart';
import 'style_profile.dart';

Future<void> openImageQuiz(
  BuildContext context, {
  required List<SummaryBlock> figures,
  String? subjectId,
}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => ImageQuizPage(figures: figures, subjectId: subjectId),
    ));

/// اختبار على صور التلخيص: الصورة لوحدها، وإنت تقول هي إيه قبل ما تشوف.
/// A quiz on the summary's pictures: the picture alone, and you say what it
/// is before you look.
///
/// الصور في التشريح والأجهزة هي اللي بتيجي في الامتحان "سمّي الجزء ده"،
/// وقرايتها جنب الكلام غير إنك تتعرف عليها من غير الكلام.
/// In anatomy and equipment, pictures are what the exam asks you to "name";
/// reading one next to its text is not the same as recognising it alone.
class ImageQuizPage extends ConsumerStatefulWidget {
  const ImageQuizPage({super.key, required this.figures, this.subjectId});

  final List<SummaryBlock> figures;
  final String? subjectId;

  @override
  ConsumerState<ImageQuizPage> createState() => _ImageQuizPageState();
}

class _ImageQuizPageState extends ConsumerState<ImageQuizPage> {
  late final List<SummaryBlock> _order = [...widget.figures]..shuffle();
  int _index = 0;
  bool _revealed = false;
  int _known = 0;
  bool _saving = false;
  bool _saved = false;

  bool get _done => _index >= _order.length;

  List<SummaryBlock> get _savable =>
      widget.figures.where((f) => f.imageUrl != null).toList();

  void _answer(bool knew) {
    setState(() {
      if (knew) _known++;
      _index++;
      _revealed = false;
    });
  }

  Future<void> _saveCards() async {
    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    try {
      // صفحات السلايدات صور كبيرة جوه التطبيق مش روابط، فمش بتتحفظ في كارت.
      // Slide pages are large in-app images rather than links, so they are
      // not saved into a card.
      for (final f in _savable) {
        await repo.addCard(Flashcard(
          id: '',
          front: '[[img:${f.imageUrl}]]\n${context.l.whatIsThisPicture}',
          back: readableMath(f.text.isEmpty ? f.query : f.text),
          subjectId: widget.subjectId,
          dueAt: DateTime.now(),
          createdAt: DateTime.now(),
        ));
      }
      ref.invalidate(cardsProvider);
      if (mounted) {
        setState(() => _saved = true);
        showSnack(context, context.l.cardsSaved(_savable.length));
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.imageQuizTitle),
        actions: [
          if (!_done)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              child: Center(child: Text('${_index + 1} / ${_order.length}')),
            ),
        ],
      ),
      body: PageBody(
        maxWidth: 640,
        child: _done
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Insets.section),
                  Text(
                    l.imageQuizScore(_known, _order.length),
                    textAlign: TextAlign.center,
                    style: text.headlineSmall,
                  ),
                  const SizedBox(height: Insets.xl),
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      _order.shuffle();
                      _index = 0;
                      _known = 0;
                    }),
                    icon: const Icon(Icons.replay_rounded),
                    label: Text(l.tryAgain),
                  ),
                  const SizedBox(height: Insets.md),
                  OutlinedButton.icon(
                    onPressed: _saving || _saved || _savable.isEmpty ? null : _saveCards,
                    icon: const Icon(Icons.style_outlined),
                    label: Text(_saved ? l.savedAsCards : l.saveAsCards),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: Insets.md),
                  Container(
                    height: 340,
                    padding: const EdgeInsets.all(Insets.md),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: Radii.all(Radii.md),
                    ),
                    child: _order[_index].imageData != null
                        ? Image.memory(_order[_index].imageData!, fit: BoxFit.contain)
                        : Image.network(
                            _order[_index].imageUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.image_not_supported_outlined),
                          ),
                  ),
                  const SizedBox(height: Insets.xl),
                  Text(l.whatIsThisPicture,
                      textAlign: TextAlign.center, style: text.titleMedium),
                  const SizedBox(height: Insets.lg),
                  if (!_revealed)
                    FilledButton(
                      onPressed: () => setState(() => _revealed = true),
                      child: Text(l.showAnswer),
                    )
                  else ...[
                    AppCard(
                      child: TexText(
                        _order[_index].text.isEmpty
                            ? _order[_index].query
                            : _order[_index].text,
                        textAlign: TextAlign.center,
                        style: text.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _answer(false),
                            child: Text(l.didntKnow),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _answer(true),
                            child: Text(l.knewIt),
                          ),
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
