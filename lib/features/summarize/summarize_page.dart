import 'dart:async';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/study_text.dart';
import '../study_ai/study_tools_row.dart';
import 'audio_clip.dart';
import 'audio_input.dart';
import 'document_text.dart';
import 'export_page.dart';
import 'file_input.dart';
import 'model_settings_sheet.dart';
import 'model_usage.dart';
import 'style_profile.dart';
import 'style_samples_page.dart';
import 'summary_page_view.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';

class SummarizePage extends ConsumerStatefulWidget {
  const SummarizePage({super.key});

  @override
  ConsumerState<SummarizePage> createState() => _SummarizePageState();
}

class _SummarizePageState extends ConsumerState<SummarizePage> {
  final _lecture = TextEditingController();
  final _outputScroll = ScrollController();

  ExtractedDocument? _extracted;

  /// الملفات اللي الموديل بيقراها بنفسه (PDF).
  /// Files the model reads itself (PDF).
  final List<LectureFile> _docs = [];

  /// التسجيلات — مسجّلة من الميكروفون أو مرفوعة.
  /// The recordings, whether captured here or uploaded.
  final List<AudioClip> _clips = [];

  MicRecorder? _recorder;

  /// بيحدّث العداد وهو بيسجّل. المسجّل مش بيبعت أحداث لكل ثانية.
  /// Ticks the counter while recording; the recorder emits no per-second event.
  Timer? _tick;

  /// اللي بيحصل دلوقتي — بيتعرض وقت التفريغ الطويل.
  /// What is happening right now; shown through the long transcription wait.
  String? _phase;

  /// كسر الاكتمال من 0 لـ 1، وnull لما يكون مفيش تقدّم معروف (البث مثلاً).
  /// The completed fraction from 0 to 1; null when there is no known progress,
  /// as while the summary streams.
  double? _progress;

  SummaryPage? _page;

  /// مرجع للصفحة المرسومة عشان نصوّرها وقت التصدير.
  /// Handle on the drawn page so it can be captured for export.
  final _exportKey = GlobalKey();
  String? _subjectId;
  String _output = '';
  bool _running = false;
  SummarizerException? _error;
  StreamSubscription<String>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    _recorder?.dispose();
    _lecture.dispose();
    _outputScroll.dispose();
    super.dispose();
  }

  bool get _hasInput =>
      _lecture.text.trim().isNotEmpty || _docs.isNotEmpty || _clips.isNotEmpty;

  // ----------------------------------------------------- التسجيل / recording

  Future<void> _startRecording() async {
    final recorder = MicRecorder();
    try {
      await recorder.start();
    } on SummarizerException catch (e) {
      recorder.dispose();
      if (mounted) setState(() => _error = e);
      return;
    }
    if (!mounted) {
      await recorder.cancel();
      return;
    }

    setState(() {
      _recorder = recorder;
      _error = null;
    });
    // ثانية بثانية: العداد هو الدليل الوحيد إن التسجيل ماشي فعلاً.
    // Once a second: the counter is the only sign the recording is running.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (recorder.atTotalLimit) _finishRecording(limitHit: true);
    });
  }

  Future<void> _finishRecording({bool limitHit = false}) async {
    final recorder = _recorder;
    if (recorder == null) return;

    _tick?.cancel();
    _tick = null;

    final stamp = TimeOfDay.fromDateTime(DateTime.now());
    final name = '${context.l.recordingNoun} '
        '${stamp.hour.toString().padLeft(2, '0')}:'
        '${stamp.minute.toString().padLeft(2, '0')}';

    final clip = await recorder.stop(name: name);
    recorder.dispose();
    if (!mounted) return;

    setState(() {
      _recorder = null;
      if (!clip.isEmpty) _clips.add(clip);
    });

    if (clip.isEmpty) {
      showSnack(context, context.l.recordingEmpty);
    } else {
      showSnack(
        context,
        limitHit ? context.l.recordingLimitHit : context.l.recordingSaved,
      );
    }
  }

  Future<void> _discardRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;
    _tick?.cancel();
    _tick = null;
    setState(() => _recorder = null);
    await recorder.cancel();
    recorder.dispose();
  }

  // -------------------------------------------------------- الملفات / files

  Future<void> _pickFile() async {
    // كل حاجة جوه try: لو اختيار الملف نفسه فشل، المستخدم لازم يشوف السبب
    // بدل ما الزرار يبان كأنه مش شغال.
    // Everything inside the try: if picking itself fails, the user must see why
    // instead of a button that looks dead.
    try {
      final files = await pickLocalFiles(
        extensions: [...supportedDocumentExtensions, ...supportedAudioExtensions],
      );
      if (files.isEmpty || !mounted) return;

      for (final file in files) {
        if (isAudioFile(file.name)) {
          _addAudioFile(file);
        } else if (isModelReadable(file.name)) {
          // الـ PDF بيتبعت للموديل زي ما هو — مش بنحاول نفك نصه في المتصفح.
          // PDFs go to the model untouched; we don't try to unpack them here.
          setState(() {
            _docs.add(LectureFile(
              name: file.name,
              mimeType: file.mimeType,
              bytes: file.bytes,
            ));
            _error = null;
          });
        } else {
          _addExtracted(file);
        }
      }
    } on UnsupportedDocumentException {
      if (mounted) showSnack(context, context.l.unsupportedFileType);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  void _addAudioFile(PickedFile file) {
    // ملف مرفوع مقطع واحد: مش بنقدر نقسّمه من غير ما نفك ترميزه ونعيد ضغطه.
    // التسجيل من التطبيق بيتقسّم وهو بيتسجّل، فمفيش حد على طوله.
    // An uploaded file is one part: splitting it would mean decoding and
    // re-encoding it here. Recording in the app splits as it goes, so its
    // length is not capped the same way.
    final clip = AudioClip(
      name: file.name,
      mimeType: file.mimeType.startsWith('audio/')
          ? file.mimeType
          : audioMimeFor(file.name),
      parts: [file.bytes],
      duration: Duration.zero,
    );
    setState(() {
      _clips.add(clip);
      _error = null;
    });
  }

  void _addExtracted(PickedFile file) {
    final doc = extractDocumentText(file.name, file.bytes);
    if (doc.isEmpty) {
      showSnack(context, context.l.fileHasNoText);
      return;
    }
    setState(() {
      _extracted = doc;
      // النص بيتضاف لللي موجود بدل ما يمسحه: ممكن ترفع أكتر من ملف.
      // The text is added to what is there rather than replacing it: more than
      // one file can be uploaded.
      final existing = _lecture.text.trim();
      _lecture.text = existing.isEmpty ? doc.text : '$existing\n\n${doc.text}';
      _error = null;
    });
  }

  // -------------------------------------------------- التفريغ / transcription

  /// بيفرّغ اللي لسه ما اتفرّغش ويرجّع النص كله.
  /// Transcribes whatever has not been transcribed yet and returns all the text.
  Future<String?> _transcribeAll(Summarizer summarizer) async {
    final total = _clips.fold<int>(0, (sum, c) => sum + c.parts.length);
    var index = 0;

    for (var i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      if (clip.transcript != null) {
        index += clip.parts.length;
        continue;
      }

      final pieces = <String>[];
      for (final part in clip.files) {
        final done = index / total;
        final slice = 1 / total;
        index++;
        if (!mounted) return null;

        try {
          // الرفع خطوة لوحدها في الشاشة: على نت بطيء هو أطول جزء في العملية،
          // ولو اتسمى "تفريغ" المستخدم يفتكر إنها علّقت.
          // Uploading is its own step on screen: on a slow line it is the
          // longest part of the wait, and calling it "transcribing" makes it
          // look stuck.
          UploadedFile? uploaded;
          if (part.needsUpload) {
            setState(() {
              _phase = context.l.uploadingPart(index, total);
              _progress = done;
            });
            uploaded = await summarizer.upload(
              part,
              // الرفع بياخد تلاتة أرباع الشريط للمقطع الواحد: هو فعلاً الجزء
              // الأطول، والباقي للتفريغ.
              // The upload takes three quarters of a part's slice: it really is
              // the longer half, and the rest belongs to the transcription.
              onProgress: (fraction) {
                if (!mounted) return;
                setState(() => _progress = done + slice * 0.75 * fraction);
              },
            );
            if (!mounted) return null;
          }

          setState(() {
            _phase = context.l.transcribingPart(index, total);
            _progress = done + slice * (part.needsUpload ? 0.75 : 0.15);
          });
          final text = await summarizer.transcribe(part, uploaded: uploaded);
          if (text.isNotEmpty) pieces.add(text);
          if (mounted) setState(() => _progress = index / total);
        } on SummarizerException catch (e) {
          if (mounted) setState(() => _error = e);
          return null;
        }
      }

      if (!mounted) return null;
      setState(() => _clips[i] = clip.withTranscript(pieces.join('\n\n')));
    }

    final all = _clips
        .map((c) => c.transcript ?? '')
        .where((t) => t.trim().isNotEmpty)
        .join('\n\n');
    return all;
  }

  void _showTranscript(AudioClip clip) {
    final l = context.l;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(clip.name),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              clip.transcript ?? '',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: clip.transcript ?? ''),
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) showSnack(context, l.copied);
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(l.copyText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.close),
          ),
        ],
      ),
    );
  }

  void _stop() {
    _sub?.cancel();
    _sub = null;
    setState(() {
      _running = false;
      _phase = null;
      _progress = null;
    });
  }

  Future<void> _generate() async {
    if (!_hasInput) {
      showSnack(context, context.l.needLectureText);
      return;
    }

    final allSamples = ref.read(styleSamplesProvider).value ?? const <StyleSample>[];
    final samples = pickStyleSamples(allSamples, _subjectId);
    final summarizer = ref.read(activeSummarizerProvider);

    // لو شكل صفحتك متحلل، بنطلب تلخيص منظم نقدر نرسمه ونصدّره صورة.
    // With a saved layout we ask for structured blocks we can draw and export.
    final profiles = ref.read(styleProfilesProvider).value ?? const {};
    final rawProfile = profiles[_subjectId] ?? profiles[null];

    setState(() {
      _running = true;
      _output = '';
      _page = null;
      _error = null;
      _phase = null;
      _progress = null;
    });

    // الصوت بيتحوّل لنص الأول. التلخيص من الصوت مباشرة بيخلي الموديل يلخص وهو
    // بيسمع، فبيضيع كلام — والتفريغ كمان بيتخزن فينفع تراجعه أو تحفظه.
    // Audio becomes text first. Summarizing straight from audio makes the model
    // summarize while listening, which loses what was said — and the
    // transcript is kept, so it can be read back or saved.
    var text = _lecture.text.trim();
    if (_clips.isNotEmpty) {
      final transcript = await _transcribeAll(summarizer);
      if (!mounted) return;
      if (transcript == null) {
        setState(() {
          _running = false;
          _phase = null;
          _progress = null;
        });
        return;
      }
      text = [text, transcript].where((t) => t.trim().isNotEmpty).join('\n\n');
      if (text.trim().isEmpty && _docs.isEmpty) {
        setState(() {
          _running = false;
          _phase = null;
          _progress = null;
          _error = SummarizerException(context.l.transcriptEmpty);
        });
        return;
      }
    }

    if (!mounted) return;
    setState(() {
      _phase = context.l.generating;
      _progress = null;
    });

    if (rawProfile != null) {
      try {
        final page = await summarizer.summarizeAsPage(
          lectureText: text,
          files: _docs,
          samples: samples,
          profile: StyleProfile.fromJson(rawProfile),
        );
        if (mounted) {
          setState(() {
            _page = page;
            _running = false;
            _phase = null;
          });
        }
      } on SummarizerException catch (e) {
        if (mounted) {
          setState(() {
            _running = false;
            _error = e;
          });
        }
      }
      return;
    }

    try {
      final stream = summarizer.summarize(
        lectureText: text,
        files: _docs,
        samples: samples,
      );
      _sub = stream.listen(
        (chunk) {
          if (!mounted) return;
          setState(() => _output += chunk);
          // نخلي آخر سطر ظاهر وهو بيتكتب.
          // Keep the newest line in view while it streams.
          if (_outputScroll.hasClients) {
            _outputScroll.jumpTo(_outputScroll.position.maxScrollExtent);
          }
        },
        onError: (Object e) {
          if (!mounted) return;
          setState(() {
            _running = false;
            _error = e is SummarizerException ? e : SummarizerException('$e');
          });
        },
        onDone: () {
          if (mounted) {
            setState(() {
              _running = false;
              _phase = null;
            });
          }
        },
        cancelOnError: true,
      );
    } on SummarizerException catch (e) {
      setState(() {
        _running = false;
        _error = e;
      });
    }
  }

  Future<void> _saveAsNote() async {
    final l = context.l;
    final source = _extracted?.fileName ??
        (_docs.isNotEmpty ? _docs.first.name : null) ??
        (_clips.isNotEmpty ? _clips.first.name : null);
    final title = source?.replaceAll(RegExp(r'\.[^.]+$'), '') ??
        _output.split('\n').first.replaceAll(RegExp(r'[#*]'), '').trim();

    try {
      await ref.read(repositoryProvider).addNote(Note(
            id: '',
            title: title.isEmpty ? l.theSummary : title,
            body: readableMath(_page?.toPlainText() ?? _output.trim()),
            subjectId: _subjectId,
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
    final scheme = Theme.of(context).colorScheme;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final allSamples = ref.watch(styleSamplesProvider).value ?? const <StyleSample>[];
    final samples = pickStyleSamples(allSamples, _subjectId);

    // من غير موديل مختار مفيش تلخيص. بنقفل الزرار ونقول السبب بدل ما نسيب
    // المستخدم يضغط ويستنى ويلاقي رسالة خطأ.
    // No model means no summary. Disable the button and say why, rather than
    // letting the user press it and wait for an error.
    final appSettings = ref.watch(settingsProvider);
    final modelChosen =
        appSettings.autoModel || appSettings.geminiModel.isNotEmpty;

    final hasInput = _hasInput;
    final hasResult = _page != null || _output.trim().isNotEmpty;
    final profiles = ref.watch(styleProfilesProvider).value ?? const {};
    final hasLayout = (profiles[_subjectId] ?? profiles[null]) != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PageBody(
        maxWidth: 840,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),

            // ------------------------------------------- 1. المحتوى / content
            StepCard(
              step: 1,
              done: hasInput,
              title: l.stepContent,
              subtitle: l.stepContentHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // زرارين متساويين: التسجيل مش ميزة مخبية جنب رفع الملف، هو
                  // الطريقة التانية اللي المحاضرة بتوصل بيها.
                  // Two buttons of equal weight: recording is not a feature
                  // tucked beside uploading, it is the other way a lecture
                  // arrives.
                  if (_recorder == null)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final record = FilledButton.icon(
                          onPressed: _running ? null : _startRecording,
                          icon: const Icon(Icons.mic_rounded, size: 19),
                          label: Text(l.recordLecture),
                        );
                        final upload = OutlinedButton.icon(
                          onPressed: _running ? null : _pickFile,
                          icon: const Icon(Icons.upload_file_rounded, size: 19),
                          label: Text(l.pickLectureFile),
                        );

                        if (constraints.maxWidth < 400) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              record,
                              const SizedBox(height: Insets.sm),
                              upload,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: record),
                            const SizedBox(width: Insets.md),
                            Expanded(child: upload),
                          ],
                        );
                      },
                    )
                  else
                    _RecordingPanel(
                      recorder: _recorder!,
                      onPause: () => setState(_recorder!.pause),
                      onResume: () => setState(_recorder!.resume),
                      onFinish: _finishRecording,
                      onDiscard: _discardRecording,
                    ),

                  const SizedBox(height: Insets.sm),
                  Text(
                    '${l.supportedFiles} · ${l.supportedAudio}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),

                  if (_docs.isNotEmpty || _clips.isNotEmpty) ...[
                    const SizedBox(height: Insets.lg),
                    for (final doc in _docs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Insets.sm),
                        child: _SourceRow(
                          icon: Icons.picture_as_pdf_rounded,
                          title: doc.name,
                          subtitle: '${doc.megabytes.toStringAsFixed(1)} MB',
                          onRemove: _running
                              ? null
                              : () => setState(() => _docs.remove(doc)),
                        ),
                      ),
                    for (final clip in _clips)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Insets.sm),
                        child: _SourceRow(
                          icon: Icons.graphic_eq_rounded,
                          title: clip.name,
                          subtitle: _clipSubtitle(context, clip),
                          onRemove: _running
                              ? null
                              : () => setState(() => _clips.remove(clip)),
                          action: clip.transcript == null
                              ? null
                              : TextButton(
                                  onPressed: () => _showTranscript(clip),
                                  child: Text(l.viewTranscript),
                                ),
                        ),
                      ),
                  ],

                  if (_extracted != null) ...[
                    const SizedBox(height: Insets.md),
                    _ExtractionInfo(doc: _extracted!),
                  ],

                  const SizedBox(height: Insets.lg),
                  Row(
                    children: [
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Insets.md),
                        child: Text(
                          l.orPasteText,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  TextField(
                    controller: _lecture,
                    maxLines: 8,
                    minLines: 4,
                    // الكتابة مش بتلغي المرفقات: ممكن ترفع السلايدات وتكتب
                    // ملاحظاتك من المحاضرة، والاتنين بيروحوا مع بعض.
                    // Typing does not drop the attachments: the slides can be
                    // uploaded and your own notes typed, and both travel
                    // together.
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l.lectureText,
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.lg),

            // ---------------------------------------------- 2. الأسلوب / style
            StepCard(
              step: 2,
              done: samples.isNotEmpty,
              title: l.stepStyle,
              subtitle: l.stepStyleHint,
              trailing: _ModelButton(
                needsModel: !modelChosen,
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const ModelSettingsSheet(),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SubjectDropdown(
                    subjects: subjects,
                    value: _subjectId,
                    onChanged: (v) => setState(() => _subjectId = v),
                  ),
                  const SizedBox(height: Insets.lg),
                  _StyleBanner(
                    usedCount: samples.length,
                    totalCount: allSamples.length,
                    hasLayout: hasLayout,
                    onManage: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const StyleSamplesPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Insets.lg),

            // --------------------------------------------- 3. النتيجة / result
            StepCard(
              step: 3,
              done: hasResult && !_running,
              title: l.stepResult,
              subtitle: l.stepResultHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_running)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _stop,
                          icon: const Icon(Icons.stop_rounded, size: 19),
                          label: Text(l.stopGenerating),
                        ),
                        if (_phase != null) ...[
                          const SizedBox(height: Insets.lg),
                          ProgressBar(label: _phase!, value: _progress),
                        ],
                      ],
                    )
                  else
                    FilledButton.icon(
                      onPressed: modelChosen ? _generate : null,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                      label: Text(
                        modelChosen ? l.generateSummary : l.chooseModelFirst,
                      ),
                    ),

                  if (_error != null) ...[
                    const SizedBox(height: Insets.lg),
                    _ErrorBox(error: _error!),
                  ],

                  // الصفحة المرسومة بتخطيط المستخدم.
                  // The page drawn in the layout read from the notebook.
                  if (_page != null) ...[
                    const SizedBox(height: Insets.xl),
                    _StyledResult(
                      page: _page!,
                      profile: StyleProfile.fromJson(
                        (profiles[_subjectId] ?? profiles[null]) ?? const {},
                      ),
                      exportKey: _exportKey,
                      onSaveNote: _saveAsNote,
                    ),
                  ],

                  // التلخيص النصي لما ما يكونش في تخطيط محفوظ.
                  // The plain summary when no layout has been saved.
                  if (_output.isNotEmpty || (_running && _page == null)) ...[
                    const SizedBox(height: Insets.xl),
                    if (_running)
                      Row(
                        children: [
                          const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: Insets.md),
                          Text(
                            l.generating,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    if (_output.isNotEmpty) ...[
                      const SizedBox(height: Insets.md),
                      Container(
                        padding: const EdgeInsets.all(Insets.lg),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerLow,
                          borderRadius: Radii.all(Radii.md),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 440),
                          child: SingleChildScrollView(
                            controller: _outputScroll,
                            child: StudyText(_output),
                          ),
                        ),
                      ),
                    ],
                    if (!_running && _output.trim().isNotEmpty) ...[
                      const SizedBox(height: Insets.lg),
                      StudyToolsRow(
                        title: l.theSummary,
                        source: _output,
                        subjectId: _subjectId,
                      ),
                      const SizedBox(height: Insets.lg),
                      Wrap(
                        spacing: Insets.md,
                        runSpacing: Insets.md,
                        children: [
                          FilledButton.icon(
                            onPressed: _saveAsNote,
                            icon: const Icon(Icons.save_alt_rounded, size: 19),
                            label: Text(l.saveAsNote),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: readableMath(_output.trim()),
                                ),
                              );
                              if (context.mounted) showSnack(context, l.copied);
                            },
                            icon: const Icon(Icons.copy_rounded, size: 19),
                            label: Text(l.copyText),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// بيعرض الموديل المستخدم وبيفتح إعداداته بضغطة.
/// Shows the model in use and opens its settings in one tap.
class _ModelButton extends ConsumerWidget {
  const _ModelButton({required this.onTap, this.needsModel = false});

  final VoidCallback onTap;
  final bool needsModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final usage = ref.watch(modelUsageProvider);

    // في الوضع التلقائي بنعرض آخر موديل رد فعلاً بدل كلمة "تلقائي" لوحدها،
    // عشان تعرف بإيه بتلخص من غير ما تفتح الإعدادات.
    // In auto mode we show the model that last answered rather than just
    // "Automatic", so you can see what you are summarizing with at a glance.
    final lastUsed = usage.counts.isEmpty ? null : usage.counts.keys.last;
    final label = settings.autoModel
        ? (lastUsed ?? context.l.autoLabel)
        : settings.geminiModel;

    return OutlinedButton.icon(
      onPressed: onTap,
      style: needsModel
          ? OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error),
            )
          : null,
      icon: Icon(
        needsModel ? Icons.warning_amber_rounded : Icons.auto_awesome_rounded,
        size: 18,
      ),
      label: Text(
        needsModel ? context.l.chooseModel : label,
        overflow: TextOverflow.ellipsis,
        textDirection: needsModel ? null : TextDirection.ltr,
      ),
    );
  }
}

/// بيقول للمستخدم إيه اللي التلخيص هيتبعه فعلاً: كام مثال، وهل في تخطيط محفوظ.
/// Tells the user what the summary will actually follow: how many examples, and
/// whether a saved layout exists.
class _StyleBanner extends StatelessWidget {
  const _StyleBanner({
    required this.usedCount,
    required this.totalCount,
    required this.hasLayout,
    required this.onManage,
  });

  final int usedCount;
  final int totalCount;
  final bool hasLayout;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final empty = usedCount == 0;

    return InfoBanner(
      tone: empty ? BannerTone.warn : BannerTone.info,
      icon: empty ? Icons.warning_amber_rounded : Icons.auto_awesome_rounded,
      message: empty
          ? l.noSamplesWarning
          : '${l.samplesUsedHere}: $usedCount / $totalCount'
              '${hasLayout ? ' · ${l.pageLook}' : ''}',
      action: TextButton(onPressed: onManage, child: Text(l.styleSamples)),
    );
  }
}

/// وصف المقطع تحت اسمه: مدته وعدد أجزائه وحالة تفريغه.
/// A clip's line under its name: how long, how many parts, and whether it has
/// been transcribed.
String _clipSubtitle(BuildContext context, AudioClip clip) {
  final l = context.l;
  final bits = <String>[];

  if (clip.duration > Duration.zero) bits.add(_clock(clip.duration));
  bits.add('${clip.megabytes.toStringAsFixed(1)} MB');
  if (clip.parts.length > 1) bits.add(l.audioParts(clip.parts.length));

  final transcript = clip.transcript;
  if (transcript != null) {
    final words = transcript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    bits.add('${l.transcribedLabel} · ${l.wordCount(words)}');
  }
  return bits.join(' · ');
}

String _clock(Duration d) {
  final minutes = d.inMinutes.toString().padLeft(2, '0');
  final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
  return d.inHours > 0 ? '${d.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}

/// لوحة التسجيل وهو شغال.
/// The panel shown while a recording runs.
class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({
    required this.recorder,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onDiscard,
  });

  final MicRecorder recorder;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final live = recorder.state == RecorderState.recording;
    final size = recorder.estimatedBytes / (1024 * 1024);

    return Container(
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: Radii.all(Radii.md),
        border: Border.all(
          color: live ? scheme.error.withValues(alpha: 0.5) : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              // نقطة حمرا بتنبض وهو بيسجّل، وساكنة لما يتوقف — الفرق لازم يبان
              // من غير ما تقرا.
              // A red dot that pulses while recording and rests when paused;
              // the difference must be visible without reading.
              _PulsingDot(active: live),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Text(
                  live ? l.recording : l.recordingPaused,
                  style: text.labelLarge?.copyWith(
                    color: live ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                _clock(recorder.elapsed),
                style: text.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Text(
            '~${size.toStringAsFixed(1)} MB · ${l.audioParts(recorder.partCount)}',
            style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: live ? onPause : onResume,
                  icon: Icon(
                    live ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 19,
                  ),
                  label: Text(live ? l.pause : l.resume),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onFinish,
                  icon: const Icon(Icons.check_rounded, size: 19),
                  label: Text(l.stopRecording),
                ),
              ),
              const SizedBox(width: Insets.sm),
              IconButton(
                tooltip: l.discardRecording,
                onPressed: onDiscard,
                icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.active});

  final bool active;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.error;
    return FadeTransition(
      opacity: widget.active
          ? Tween(begin: 0.35, end: 1.0).animate(_c)
          : const AlwaysStoppedAnimation(0.4),
      child: Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// صف مصدر واحد في قايمة المصادر.
/// One source's row in the list of sources.
class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRemove,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRemove;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
          Insets.md, Insets.sm, Insets.sm, Insets.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: Radii.all(Radii.md),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: scheme.primary),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          ?action,
          IconButton(
            tooltip: context.l.removeSource,
            iconSize: 18,
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ExtractionInfo extends StatelessWidget {
  const _ExtractionInfo({required this.doc});

  final ExtractedDocument doc;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.description_outlined, size: 15, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${l.extractedFrom} ${doc.fileName} · ${doc.blocks} ${l.blocksFound} · '
            '~${doc.approxTokens} ${l.approxTokens}',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error});

  final SummarizerException error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.message,
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          if (error.hint != null) ...[
            const SizedBox(height: 6),
            Text(
              error.hint!,
              style: TextStyle(
                color: scheme.onErrorContainer.withValues(alpha: 0.85),
                fontSize: 12,
                height: 1.6,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// الصفحة المرسومة بشكل المستخدم، مع أزرار التصدير.
/// The page drawn in the user's own layout, with its export actions.
class _StyledResult extends StatefulWidget {
  const _StyledResult({
    required this.page,
    required this.profile,
    required this.exportKey,
    required this.onSaveNote,
  });

  final SummaryPage page;
  final StyleProfile profile;
  final GlobalKey exportKey;
  final Future<void> Function() onSaveNote;

  @override
  State<_StyledResult> createState() => _StyledResultState();
}

class _StyledResultState extends State<_StyledResult> {
  bool _exporting = false;

  String get _fileName {
    final base = widget.page.title.trim().isEmpty ? 'summary' : widget.page.title.trim();
    // أسماء الملفات بتتكسر مع المحارف دي على بعض الأنظمة.
    // These characters break file names on some systems.
    return base.replaceAll(RegExp(r'[\/:*?"<>|]'), '-');
  }

  Future<void> _export({required bool asPdf}) async {
    setState(() => _exporting = true);
    try {
      if (asPdf) {
        downloadBytes(
          '$_fileName.pdf',
          'application/pdf',
          await capturePdf(widget.exportKey),
        );
      } else {
        downloadBytes(
          '$_fileName.png',
          'image/png',
          await capturePng(widget.exportKey),
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // الحدود دي هي اللي بتتصور وقت التصدير، فبتتلف الصفحة نفسها بس.
        // This boundary is what gets captured, so it wraps the page alone.
        //
        // وتكبير الخط بتاع التطبيق متشال من هنا: الصفحة دي ملف هيتصدَّر، ولو
        // إعداد في التطبيق غيّر مقاسها تبقى المعاينة مش هي اللي اتحفظت.
        // The app's text scaling is dropped here: this page is a file about to
        // be exported, and if an app setting resized it the preview would stop
        // being what got saved.
        MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: RepaintBoundary(
            key: widget.exportKey,
            child: SummaryPageView(page: widget.page, profile: widget.profile),
          ),
        ),
        const SizedBox(height: Insets.lg),
        // تلات أزرار في صف واحد بيتزنقوا على الموبايل، فبيبقوا فوق بعض.
        // Three buttons in one row crowd a phone, so they stack there.
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = [
              FilledButton.icon(
                onPressed: _exporting ? null : () => _export(asPdf: false),
                icon: const Icon(Icons.image_outlined, size: 19),
                label: Text(l.exportPng),
              ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _export(asPdf: true),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                label: Text(l.exportPdf),
              ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : widget.onSaveNote,
                icon: const Icon(Icons.save_alt_rounded, size: 19),
                label: Text(l.saveAsNote),
              ),
            ];

            if (constraints.maxWidth < 460) {
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

            return Row(
              children: [
                for (final b in buttons) ...[
                  Expanded(child: b),
                  if (b != buttons.last) const SizedBox(width: Insets.md),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
