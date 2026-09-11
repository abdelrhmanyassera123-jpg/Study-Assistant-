import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../widgets/common.dart';
import '../../widgets/study_text.dart';
import '../summarize/summarizer.dart';
import '../summarize/summarizer_provider.dart';
import 'study_ai.dart';

Future<void> openAskPage(
  BuildContext context, {
  required String title,
  required String source,
}) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => AskPage(title: title, source: source),
      ),
    );

/// محادثة عن محاضرة واحدة.
/// A conversation about one lecture.
///
/// المصدر هو المحاضرة اللي قدامك بس — مش معرفة الموديل العامة. الطالب بيذاكر
/// للامتحان من الكلام ده، وإجابة صح في المطلق بس مش في المحاضرة بتبقى غلط في
/// ورقة الإجابة.
/// The source is the lecture in front of you, not the model's general
/// knowledge. The student revises this material for an exam, and an answer that
/// is true in general but absent from the lecture is wrong on the answer sheet.
class AskPage extends ConsumerStatefulWidget {
  const AskPage({super.key, required this.title, required this.source});

  final String title;
  final String source;

  @override
  ConsumerState<AskPage> createState() => _AskPageState();
}

class _AskPageState extends ConsumerState<AskPage> {
  final _question = TextEditingController();
  final _scroll = ScrollController();
  final List<AskTurn> _turns = [];

  String _pending = '';
  String _streaming = '';
  bool _running = false;
  StreamSubscription<String>? _sub;
  SummarizerException? _error;

  @override
  void dispose() {
    _sub?.cancel();
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: Motion.normal,
      curve: Motion.ease,
    );
  }

  Future<void> _send() async {
    final question = _question.text.trim();
    if (question.isEmpty || _running) return;

    setState(() {
      _pending = question;
      _streaming = '';
      _running = true;
      _error = null;
      _question.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());

    final stream = ref.read(activeSummarizerProvider).ask(
          source: widget.source,
          question: question,
          // آخر أربع لفّات بس: السياق الطويل بيزود التكلفة من غير ما يزود الفهم.
          // Only the last four turns: a long history costs more without
          // understanding more.
          history: _turns.length <= 4
              ? _turns
              : _turns.sublist(_turns.length - 4),
        );

    _sub = stream.listen(
      (chunk) {
        if (!mounted) return;
        setState(() => _streaming += chunk);
        _toBottom();
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _running = false;
          _error = e is SummarizerException ? e : SummarizerException('$e');
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() {
          if (_streaming.trim().isNotEmpty) {
            _turns.add(AskTurn(question: _pending, answer: _streaming.trim()));
          }
          _pending = '';
          _streaming = '';
          _running = false;
        });
        _toBottom();
      },
      cancelOnError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(
                bottom: Insets.sm, right: Insets.xl, left: Insets.xl),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                l.askGrounded,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _turns.isEmpty && _pending.isEmpty
                ? _Suggestions(onPick: (q) {
                    _question.text = q;
                    _send();
                  })
                : PageBody(
                    controller: _scroll,
                    maxWidth: 760,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final turn in _turns) ...[
                          _Bubble(text: turn.question, mine: true),
                          _Bubble(text: turn.answer, mine: false),
                        ],
                        if (_pending.isNotEmpty)
                          _Bubble(text: _pending, mine: true),
                        if (_running || _streaming.isNotEmpty)
                          _Bubble(
                            text: _streaming.isEmpty ? '…' : _streaming,
                            mine: false,
                          ),
                        if (_error != null) ...[
                          const SizedBox(height: Insets.md),
                          InfoBanner(
                            message: _error!.message,
                            icon: Icons.error_outline_rounded,
                            tone: BannerTone.error,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  Insets.lg, Insets.sm, Insets.lg, Insets.lg),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _question,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: l.askHint),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  IconButton.filled(
                    onPressed: _running ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// أسئلة جاهزة تبدأ بيها — الشاشة الفاضية أصعب حاجة في أي محادثة.
/// Openers to start from: an empty conversation screen is the hardest part of
/// any chat.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;

    return PageBody(
      maxWidth: 620,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Insets.section),
          Icon(Icons.forum_rounded, size: 34, color: scheme.primary),
          const SizedBox(height: Insets.lg),
          Text(
            l.askTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Insets.xxl),
          for (final q in l.askOpeners)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: OutlinedButton(
                onPressed: () => onPick(q),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(q),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.mine});

  final String text;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: Insets.md),
          padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg, vertical: Insets.md),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerLowest,
            borderRadius: Radii.all(Radii.lg),
            border: mine ? null : Border.all(color: scheme.outlineVariant),
          ),
          child: mine
              ? Text(
                  text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onPrimaryContainer),
                )
              : StudyText(text),
        ),
      ),
    );
  }
}

/// نسخ إجابة — بيتنادى من ضغطة مطوّلة على الفقاعة.
/// Copies an answer; called from a long press on the bubble.
Future<void> copyAnswer(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, context.l.copied);
}
