import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../core/paste_images.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/study_text.dart';
import '../study_ai/study_ai.dart';
import 'document_text.dart';
import 'file_input.dart';
import 'image_shrink.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';

/// المحاضرة اللي الحل هيمشي على طريقتها — فاضية لو الطالب ما رفعش حاجة.
/// The lecture the solution follows; empty when the student uploaded none.
class SolveLecture {
  const SolveLecture({this.text = '', this.files = const []});

  final String text;
  final List<LectureFile> files;

  bool get isEmpty => text.trim().isEmpty && files.isEmpty;
}

/// "حل سؤال": الطالب يكتب السؤال أو يصوّره، والموديل يفهّمه السؤال الأول
/// وبعدين يحله خطوة بخطوة — على طريقة المحاضرة لو مرفوعة. وتحت الحل يقدر
/// يسأل على أي خطوة مش فاهمها.
/// "Solve a question": the student types the question or photographs it, and
/// the model first makes it clear, then solves it step by step — the
/// lecture's way when one is uploaded. Beneath the solution they can ask
/// about any step they do not follow.
class SolvePanel extends ConsumerStatefulWidget {
  const SolvePanel({
    super.key,
    required this.hasLecture,
    required this.loadLecture,
    this.subjectId,
  });

  /// فيه محاضرة مرفوعة فوق في الصفحة.
  /// A lecture is uploaded above on the page.
  final bool hasLecture;

  /// بيجيب المحاضرة (ويفرّغ التسجيلات لو فيه). null لو التفريغ فشل — الصفحة
  /// بتعرض السبب.
  /// Fetches the lecture (transcribing recordings if any). null when
  /// transcription failed; the page shows why.
  final Future<SolveLecture?> Function() loadLecture;
  final String? subjectId;

  @override
  ConsumerState<SolvePanel> createState() => _SolvePanelState();
}

class _SolvePanelState extends ConsumerState<SolvePanel> {
  final _question = TextEditingController();
  final _follow = TextEditingController();
  final _questionFocus = FocusNode();
  final _followFocus = FocusNode();
  final List<LectureFile> _images = [];

  /// صور سؤال المتابعة اللي جاي — بتتبعت معاه وبعدين تتمسح.
  /// Pictures for the next follow-up; sent with it, then cleared.
  final List<LectureFile> _followImages = [];

  /// صور كل سؤال متابعة اتبعت، عشان تتعرض جنبه.
  /// Each sent follow-up's picture count, shown beside it.
  final List<int> _followImageCounts = [];

  StreamSubscription<List<PastedImage>>? _pasteSub;

  String? _solution;
  final List<AskTurn> _followUps = [];
  SolveLecture _lecture = const SolveLecture();

  bool _running = false;
  SummarizerException? _error;

  /// بيزيد مع كل طلب أو إيقاف، عشان رد قديم وصل متأخر ما يتعرضش.
  /// Bumped on every request or stop, so a stale reply arriving late is
  /// ignored.
  int _run = 0;

  @override
  void initState() {
    super.initState();
    // صورة اتلصقت (Ctrl+V أو "لصق") وخانة من خانات الحل عليها الفوكس: بتتضاف
    // للسؤال، أو لسؤال المتابعة لو ده اللي بيتكتب.
    // A picture pasted (Ctrl+V or "Paste") while one of the solve fields has
    // focus: added to the question, or to the follow-up if that is the one
    // being typed.
    _pasteSub = PasteImages.stream.listen((pasted) {
      if (_running) return;
      if (_followFocus.hasFocus && _solution != null) {
        _addPasted(pasted, _followImages);
      } else if (_questionFocus.hasFocus) {
        _addPasted(pasted, _images);
      }
    });
  }

  @override
  void dispose() {
    _pasteSub?.cancel();
    _question.dispose();
    _follow.dispose();
    _questionFocus.dispose();
    _followFocus.dispose();
    super.dispose();
  }

  Future<void> _addPasted(List<PastedImage> pasted, List<LectureFile> into) async {
    for (final p in pasted) {
      var ready = PickedFile(name: p.name, bytes: p.bytes, mimeType: p.mimeType);
      try {
        ready = await shrinkImage(ready);
      } catch (_) {}
      into.add(LectureFile(
        name: ready.name,
        mimeType: ready.mimeType.startsWith('image/') ? ready.mimeType : 'image/png',
        bytes: ready.bytes,
      ));
    }
    if (!mounted) return;
    setState(() {});
    showSnack(context, context.l.imagesPasted(pasted.length));
  }

  /// زرار "الصق": للموبايل لما الكيبورد ما بيلصقش الصورة جوه الخانة.
  /// The "paste" button: for phones whose keyboard will not paste a picture
  /// into the field.
  Future<void> _pasteButton(List<LectureFile> into) async {
    final l = context.l;
    final pasted = await PasteImages.readClipboard();
    if (!mounted) return;
    if (pasted == null) return showSnack(context, l.pasteUnsupported);
    if (pasted.isEmpty) return showSnack(context, l.clipboardNoImage);
    await _addPasted(pasted, into);
  }

  bool get _arabic => ref.read(settingsProvider).languageCode == 'ar';

  Future<void> _addImages() async {
    final picked = await pickLocalFiles(
      extensions: [...imageExtensions, 'pdf'],
      mimeTypes: const ['image/*', 'application/pdf'],
    );
    for (final f in picked) {
      if (isModelReadable(f.name)) {
        _images.add(LectureFile(name: f.name, mimeType: 'application/pdf', bytes: f.bytes));
        continue;
      }
      var ready = f;
      try {
        ready = await shrinkImage(f);
      } catch (_) {}
      _images.add(LectureFile(
        name: ready.name,
        mimeType: ready.mimeType.startsWith('image/') ? ready.mimeType : 'image/jpeg',
        bytes: ready.bytes,
      ));
    }
    if (mounted) setState(() {});
  }

  /// نص السؤال للمتابعة: لو كان صورة بس، الحل نفسه فيه السؤال متفسّر.
  /// The question's text for follow-ups: if it was a picture only, the
  /// solution itself restates it.
  String get _questionText =>
      _question.text.trim().isEmpty ? '(السؤال كان صورة — شوف "فهم السؤال" في الحل)' : _question.text;

  Future<void> _solve() async {
    final l = context.l;
    if (_question.text.trim().isEmpty && _images.isEmpty) {
      showSnack(context, l.needQuestion);
      return;
    }
    final run = ++_run;
    setState(() {
      _running = true;
      _error = null;
      _solution = null;
      _followUps.clear();
      _followImageCounts.clear();
    });

    final lecture = await widget.loadLecture();
    if (!mounted || run != _run) return;
    if (lecture == null) {
      setState(() => _running = false);
      return;
    }
    _lecture = lecture;

    await _stream(
      run,
      ref.read(activeSummarizerProvider).solve(
            question: _question.text,
            questionImages: List.of(_images),
            lectureText: lecture.text,
            lectureFiles: lecture.files,
            arabic: _arabic,
          ),
      (text) => _solution = text,
    );
  }

  Future<void> _ask([String? preset]) async {
    final q = (preset ?? _follow.text).trim();
    final solution = _solution;
    final images = List.of(_followImages);
    if ((q.isEmpty && images.isEmpty) || solution == null || _running) return;
    final run = ++_run;
    final history = [AskTurn(question: _questionText, answer: solution), ..._followUps];
    setState(() {
      _running = true;
      _error = null;
      _follow.clear();
      _followImages.clear();
      _followUps.add(AskTurn(question: q, answer: ''));
      _followImageCounts.add(images.length);
    });
    final index = _followUps.length - 1;

    await _stream(
      run,
      ref.read(activeSummarizerProvider).solve(
            question: _questionText,
            lectureText: _lecture.text,
            history: history,
            followUp: q,
            followUpImages: images,
            arabic: _arabic,
          ),
      (text) => _followUps[index] = AskTurn(question: q, answer: text),
    );
  }

  Future<void> _stream(int run, Stream<String> stream, void Function(String text) show) async {
    final written = StringBuffer();
    try {
      await for (final chunk in stream) {
        if (!mounted || run != _run) return;
        written.write(chunk);
        setState(() => show(written.toString()));
      }
    } on SummarizerException catch (e) {
      if (mounted && run == _run) setState(() => _error = e);
    }
    if (mounted && run == _run) setState(() => _running = false);
  }

  void _stop() => setState(() {
        _run++;
        _running = false;
      });

  String get _everything => [
        if (_question.text.trim().isNotEmpty) '${context.l.theQuestion}:\n${_question.text.trim()}',
        _solution ?? '',
        for (final t in _followUps) '— ${t.question}\n${t.answer}',
      ].where((s) => s.trim().isNotEmpty).join('\n\n');

  Future<void> _saveNote() async {
    final l = context.l;
    final first = _question.text.trim().split('\n').first;
    final title = first.isEmpty ? l.theSolution : '${l.theSolution}: ${first.length > 60 ? '${first.substring(0, 60)}…' : first}';
    try {
      await ref.read(repositoryProvider).addNote(Note(
            id: '',
            title: title,
            body: readableMath(_everything),
            subjectId: widget.subjectId,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ));
      ref.invalidate(notesProvider);
      if (mounted) showSnack(context, l.savedAsNote);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          icon: widget.hasLecture ? Icons.menu_book_rounded : Icons.lightbulb_outline_rounded,
          message: widget.hasLecture ? l.solveWithLecture : l.solveNoLecture,
        ),
        const SizedBox(height: Insets.md),
        TextField(
          controller: _question,
          focusNode: _questionFocus,
          minLines: 3,
          maxLines: 8,
          enabled: !_running,
          decoration: InputDecoration(hintText: l.solveQuestionHint, alignLabelWithHint: true),
        ),
        const SizedBox(height: Insets.sm),
        Wrap(
          spacing: Insets.sm,
          runSpacing: Insets.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: _running ? null : _addImages,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(l.solveAddPhoto),
            ),
            OutlinedButton.icon(
              onPressed: _running ? null : () => _pasteButton(_images),
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: Text(l.pasteImage),
            ),
            for (final img in _images)
              InputChip(
                avatar: Icon(
                  img.mimeType == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                  size: 18,
                ),
                label: Text(img.name, overflow: TextOverflow.ellipsis),
                onDeleted: _running ? null : () => setState(() => _images.remove(img)),
              ),
          ],
        ),
        const SizedBox(height: Insets.lg),
        if (_running && _solution == null)
          OutlinedButton.icon(
            onPressed: _stop,
            icon: const Icon(Icons.stop_rounded, size: 19),
            label: Text(l.stopGenerating),
          )
        else
          FilledButton.icon(
            onPressed: _running ? null : _solve,
            icon: const Icon(Icons.psychology_alt_outlined, size: 19),
            label: Text(_solution == null ? l.solveButton : l.solveAgain),
          ),
        if (_running && _solution == null) ...[
          const SizedBox(height: Insets.lg),
          ProgressBar(label: l.solving),
        ],
        if (_error != null) ...[
          const SizedBox(height: Insets.lg),
          InfoBanner(
            icon: Icons.error_outline_rounded,
            tone: BannerTone.error,
            message: [_error!.message, if (_error!.hint != null) _error!.hint!].join('\n'),
          ),
        ],
        if (_solution != null) ...[
          const SizedBox(height: Insets.xl),
          _Bubble(child: StudyText(_solution!)),
          for (var i = 0; i < _followUps.length; i++) ...[
            const SizedBox(height: Insets.md),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.md),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_followUps[i].question.isNotEmpty)
                      Text(_followUps[i].question, style: TextStyle(color: scheme.onPrimaryContainer)),
                    if (i < _followImageCounts.length && _followImageCounts[i] > 0)
                      Text(
                        '📎 ${l.imagesCount(_followImageCounts[i])}',
                        style: TextStyle(color: scheme.onPrimaryContainer),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Insets.sm),
            _Bubble(
              child: _followUps[i].answer.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(Insets.sm),
                      child: LinearProgressIndicator(),
                    )
                  : StudyText(_followUps[i].answer),
            ),
          ],
          if (!_running) ...[
            const SizedBox(height: Insets.lg),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final q in [l.solveQuickSimpler, l.solveQuickStep, l.solveQuickExample])
                  ActionChip(label: Text(q), onPressed: () => _ask(q)),
              ],
            ),
            const SizedBox(height: Insets.sm),
            if (_followImages.isNotEmpty) ...[
              Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: [
                  for (final img in _followImages)
                    InputChip(
                      avatar: const Icon(Icons.image_outlined, size: 18),
                      label: Text(img.name, overflow: TextOverflow.ellipsis),
                      onDeleted: () => setState(() => _followImages.remove(img)),
                    ),
                ],
              ),
              const SizedBox(height: Insets.sm),
            ],
            TextField(
              controller: _follow,
              focusNode: _followFocus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _ask(),
              decoration: InputDecoration(
                hintText: l.solveFollowUpHint,
                prefixIcon: IconButton(
                  tooltip: l.pasteImage,
                  onPressed: () => _pasteButton(_followImages),
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                suffixIcon: IconButton(
                  tooltip: l.send,
                  onPressed: () => _ask(),
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ),
            const SizedBox(height: Insets.md),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: _saveNote,
                  icon: const Icon(Icons.save_alt_rounded, size: 19),
                  label: Text(l.saveAsNote),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: readableMath(_everything)));
                    if (context.mounted) showSnack(context, l.copied);
                  },
                  icon: const Icon(Icons.copy_rounded, size: 19),
                  label: Text(l.copyText),
                ),
              ],
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: Insets.md),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_rounded, size: 18),
                  label: Text(l.stopGenerating),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}
