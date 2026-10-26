import 'dart:async';


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/launch_intent.dart';
import '../../core/math_text.dart';
import '../../core/settings.dart';
import '../../core/share_target.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../jobs/jobs_panel.dart';
import '../jobs/lecture_job.dart';
import '../study_ai/study_ai.dart';
import 'audio_clip.dart';
import 'audio_input.dart';
import 'document_text.dart';
import 'file_input.dart';
import 'image_shrink.dart';
import 'model_settings_sheet.dart';
import 'model_usage.dart';
import 'style_profile.dart';
import 'style_samples_page.dart';
import 'summary_images.dart';
import 'styled_result.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';
import 'solve_panel.dart';

class SummarizePage extends ConsumerStatefulWidget {
  const SummarizePage({super.key});

  @override
  ConsumerState<SummarizePage> createState() => _SummarizePageState();
}

class _SummarizePageState extends ConsumerState<SummarizePage> {
  final _lecture = TextEditingController();

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

  /// الورق اللي اتعمل: تلخيص وشرح ومراجعة، كل واحد بيفضل محفوظ لما تبدّل.
  /// The paper made so far: summary, explanation and review, each kept while
  /// switching between them.
  final Map<StudyOutput, SummaryPage> _pages = {};

  /// الورقة اللي ظاهرة دلوقتي.
  /// The page showing right now.
  SummaryPage? get _page => _pages[_mode];

  /// المعروض دلوقتي: تلخيص أو شرح أو مراجعة.
  /// What is showing: summary, explanation or review.
  StudyOutput _mode = StudyOutput.summary;

  /// تاب "حل سؤال" — مش ورقة من المحاضرة زي التلاتة التانيين، فبيتمسك لوحده.
  /// The "solve a question" tab: not a page made from the lecture like the
  /// other three, so it is kept apart.
  bool _solving = false;
  static const _solveTab = 'solve';
  ExplainLevel _level = ExplainLevel.normal;

  /// النص اللي اتلخص (تفريغ + نص ملزوق) — بيتحفظ عشان "إيه اللي اتنسى".
  /// The text that was summarized (transcript + pasted text), kept for "what
  /// was missed".
  String _source = '';

  String? _subjectId;
  bool _running = false;
  SummarizerException? _error;

  /// بيزيد مع كل تلخيص أو إيقاف، عشان رد قديم وصل متأخر ما يتعرضش.
  /// Bumped on every run or stop, so a stale reply arriving late is ignored.
  int _runId = 0;

  /// المحاضرة اللي التطبيق اتفتح عشان يسجّلها من التنبيه. لو موجودة، التسجيل
  /// أول ما يقف بيتبعت للتلخيص في الخلفية لوحده.
  /// The lecture the reminder opened the app to record. When set, the
  /// recording goes to the background summary by itself as soon as it stops.
  ScheduleEntry? _autoEntry;
  Timer? _autoStop;

  ImageMode _imageMode = ImageMode.web;

  /// وصف الرفع للخلفية وهو شغال ("بيرفع 2 من 5").
  /// The background upload's progress while it runs ("uploading 2 of 5").
  String? _queuePhase;

  @override
  void initState() {
    super.initState();
    // ملف جاي من مشاركة نظام (Android share sheet) — لو موجود، بيتضاف بعد
    // أول فريم بنفس منطق اختيار الملف اليدوي.
    // A file that arrived via the OS share sheet — if there is one, it is
    // added after the first frame using the same logic as picking a file by
    // hand.
    final shared = SharedFile.take();
    if (shared != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (shared.text.isNotEmpty) {
          final existing = _lecture.text.trim();
          setState(() => _lecture.text =
              existing.isEmpty ? shared.text : '$existing\n\n${shared.text}');
        }
        var added = 0;
        for (final file in shared.files) {
          if (await _addPickedFile(file)) added++;
        }
        if (mounted && (added > 0 || shared.text.isNotEmpty)) {
          showSnack(context, context.l.sharedAdded(added, shared.text.isNotEmpty));
        }
      });
    }

    savedImageMode().then((m) {
      if (mounted) setState(() => _imageMode = m);
    });

    final record = LaunchIntent.takeRecord();
    if (record != null) _armFromSchedule(record);
    final job = LaunchIntent.takeJob();
    if (job != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openJobResult(context, job);
      });
    }
  }

  /// بيجهّز الشاشة لمحاضرة من الجدول: المادة متختارة، والتسجيل على زرار واحد.
  /// Readies the screen for a timetable lecture: the subject chosen, and the
  /// recording one tap away.
  Future<void> _armFromSchedule(String entryId) async {
    final schedule = await ref.read(scheduleProvider.future);
    final matches = schedule.where((e) => e.id == entryId);
    if (matches.isEmpty || !mounted) return;
    final entry = matches.first;
    setState(() {
      _autoEntry = entry;
      if (entry.subjectId != null) _subjectId = entry.subjectId;
    });
  }

  /// التسجيل بيقف لوحده بعد ميعاد نهاية المحاضرة بعشر دقايق، عشان لو نسيته
  /// ما يفضلش يسجّل ساعات.
  /// The recording stops on its own ten minutes after the lecture's end, so
  /// a forgotten one does not run for hours.
  void _scheduleAutoStop() {
    final end = _autoEntry?.endMinutes;
    if (end == null) return;
    final now = DateTime.now();
    final stopAt = DateTime(now.year, now.month, now.day).add(Duration(minutes: end + 10));
    final wait = stopAt.difference(now);
    if (wait.isNegative || wait > const Duration(hours: 4)) return;
    _autoStop?.cancel();
    _autoStop = Timer(wait, () {
      if (mounted && _recorder != null) _finishRecording();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _autoStop?.cancel();
    _recorder?.dispose();
    _lecture.dispose();
    super.dispose();
  }

  /// السلايدات المرفوعة كـ PDF، بالترتيب اللي اتبعتت بيه للموديل — رقم "doc"
  /// في بلوك الصورة بيشاور على ترتيبها هنا.
  /// The slides uploaded as PDF, in the order they were sent to the model —
  /// an image block's "doc" number points into this order.
  List<Uint8List> get _pdfs => [
        for (final d in _docs)
          if (d.mimeType == 'application/pdf') d.bytes,
      ];

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
    _scheduleAutoStop();
  }

  Future<void> _finishRecording({bool limitHit = false}) async {
    final recorder = _recorder;
    if (recorder == null) return;

    _tick?.cancel();
    _tick = null;
    _autoStop?.cancel();

    final stamp = TimeOfDay.fromDateTime(DateTime.now());
    final name = _autoEntry?.title ??
        '${context.l.recordingNoun} '
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
    } else if (_autoEntry != null) {
      await _queueInBackground();
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
        extensions: [
          ...supportedDocumentExtensions,
          ...supportedAudioExtensions,
          ...imageExtensions,
        ],
        // على أندرويد الفلتر بالامتداد لوحده بيخفي ملفات الـ m4a من الاختيار
        // لأن النظام بيترجمه لنوع مختلف عن اللي مسجّل بيه الملف.
        // On Android, filtering by extension alone hides m4a files from the
        // picker: the system maps it to a type other than the one the file
        // was saved with.
        mimeTypes: const ['audio/*', 'image/*', ...documentMimeTypes],
      );
      if (files.isEmpty || !mounted) return;

      for (final file in files) {
        await _addPickedFile(file);
      }
    } on LegacyOfficeException catch (e) {
      if (mounted) showSnack(context, context.l.legacyOfficeFile(e.extension));
    } on UnsupportedDocumentException {
      if (mounted) showSnack(context, context.l.unsupportedFileType);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  /// بيوجّه ملف (من الاختيار اليدوي أو من مشاركة النظام) لمساره الصح حسب
  /// نوعه — صوت، PDF، أو نص يتستخرج.
  /// Routes a file (whether hand-picked or arriving via the OS share sheet)
  /// to the right path by type — audio, PDF, or extractable text.
  ///
  /// بيرجّع false لو النوع مش مدعوم — بعد ما يقول للمستخدم، بدل ما يرمي خطأ
  /// يوقّع الشاشة (الملف ممكن يكون جاي من مشاركة من أي تطبيق).
  /// Returns false for an unsupported type, after telling the user, instead
  /// of throwing and breaking the screen (the file may come from a share in
  /// any app).
  Future<bool> _addPickedFile(PickedFile file) async {
    if (isAudioFile(file.name)) {
      _addAudioFile(file);
    } else if (isImageFile(file.name)) {
      // الصورة بتصغر الأول: صورة موبايل 5 ميجا ما تفرقش في القراية عن نص ميجا.
      // The picture is shrunk first: a 5 MB phone photo reads no better than
      // half a megabyte.
      var ready = file;
      try {
        ready = await shrinkImage(file);
      } catch (_) {}
      if (!mounted) return false;
      setState(() {
        _docs.add(LectureFile(
          name: ready.name,
          mimeType: ready.mimeType.startsWith('image/') ? ready.mimeType : 'image/jpeg',
          bytes: ready.bytes,
        ));
        _error = null;
      });
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
    } else if (isExtractable(file.name)) {
      return _addExtracted(file);
    } else {
      if (mounted) showSnack(context, '${context.l.unsupportedFileType} (${file.name})');
      return false;
    }
    return true;
  }

  void _addAudioFile(PickedFile file) {
    // ملف مرفوع مقطع واحد: مش بنقدر نقسّمه من غير ما نفك ترميزه ونعيد ضغطه.
    // التسجيل من التطبيق بيتقسّم وهو بيتسجّل، فمفيش حد على طوله.
    // An uploaded file is one part: splitting it would mean decoding and
    // re-encoding it here. Recording in the app splits as it goes, so its
    // length is not capped the same way.
    // النوع من الامتداد مش من المتصفح: كروم بيقول على الـ m4a إنه
    // `audio/x-m4a`، وجوجل بترفض النوع ده رغم إنها بتقبل نفس الملف كـ
    // `audio/mp4`.
    // The type comes from the extension, not the browser: Chrome calls an m4a
    // `audio/x-m4a`, which Google rejects even though it accepts the very
    // same file as `audio/mp4`.
    final clip = AudioClip(
      name: file.name,
      mimeType: audioMimeFor(file.name),
      parts: [file.bytes],
      duration: Duration.zero,
    );
    setState(() {
      _clips.add(clip);
      _error = null;
    });
  }

  Future<bool> _addExtracted(PickedFile file) async {
    final l = context.l;
    final ExtractedDocument doc;
    try {
      doc = extractDocumentText(file.name, file.bytes);
    } on LegacyOfficeException {
      rethrow;
    } on UnsupportedDocumentException {
      rethrow;
    } catch (_) {
      // ZIP بايظ أو ملف متسمّي pptx وهو مش كده — رسالة مفهومة بدل نص
      // الاستثناء الإنجليزي.
      // A broken ZIP, or a file named pptx that is not one: a readable
      // message instead of the exception's English text.
      if (mounted) showSnack(context, l.fileUnreadable(file.name));
      return false;
    }

    // سلايدات أغلبها صور: الصور نفسها بتتبعت للموديل يقراها، والنص القليل
    // اللي فيها بيروح معاها.
    // Slides that are mostly pictures: the pictures themselves go to the
    // model to read, with whatever little text they have alongside.
    if (doc.mostlyPictures) {
      final images = <LectureFile>[];
      for (final image in doc.images) {
        var ready = PickedFile(name: image.name.split('/').last, bytes: image.bytes, mimeType: image.mimeType);
        try {
          ready = await shrinkImage(ready);
        } catch (_) {}
        images.add(LectureFile(
          name: '${file.name} · ${ready.name}',
          mimeType: ready.mimeType.startsWith('image/') ? ready.mimeType : 'image/jpeg',
          bytes: ready.bytes,
        ));
      }
      if (!mounted) return false;
      setState(() {
        _docs.addAll(images);
        if (!doc.isEmpty) {
          final existing = _lecture.text.trim();
          _lecture.text = existing.isEmpty ? doc.text : '$existing\n\n${doc.text}';
        }
        _extracted = doc;
        _error = null;
      });
      showSnack(context, l.slidesAsPictures(images.length));
      return true;
    }

    if (doc.isEmpty) {
      if (mounted) showSnack(context, l.fileHasNoText);
      return false;
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
    return true;
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
              // ملف كبير بيتبعت على أجزاء: النص ده بيتغيّر مع كل جزء، فيثبت
              // للمستخدم إن حاجة بتحصل فعلًا حتى لو الشريط نفسه بيتحرك ببطء.
              // A large file goes out in chunks: this text changes with each
              // one, proving to the user that something is really happening
              // even when the bar itself moves slowly.
              onChunk: (chunk, totalChunks) {
                if (!mounted) return;
                setState(() => _phase = context.l.uploadingChunk(chunk, totalChunks));
              },
            );
            if (!mounted) return null;
          }

          setState(() {
            _phase = context.l.transcribingPart(index, total);
            _progress = done + slice * (part.needsUpload ? 0.75 : 0.15);
          });
          final text = await summarizer.transcribe(part, uploaded: uploaded);
          // "(مفيش كلام)" مش نص فاضي — ده حرفيًا اللي بيطلب من الموديل يكتبه
          // لمقطع ساكت (شوف StudyPrompt.transcribeSystem). لو اتسابت، بتعدي
          // فحص "مفيش حاجة تتلخص" وتتبعت للموديل كأنها محتوى محاضرة حقيقي —
          // ومع أمثلة أسلوب حقيقية جنبها، الموديل بيرجّع محتوى مثال قديم
          // بدل ما يقول "مفيش صوت" بوضوح.
          // "(مفيش كلام)" is not empty text — it is literally what the model
          // is told to write for a silent segment (see
          // StudyPrompt.transcribeSystem). Left in, it slips past the
          // "nothing to summarize" check and gets sent as if it were real
          // lecture content — and alongside genuine style examples, the
          // model returns an old example's content instead of clearly
          // saying "no speech."
          final trimmed = text.trim();
          if (trimmed.isNotEmpty && trimmed != StudyPrompt.noSpeechMarker) {
            pieces.add(text);
          }
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
    _runId++;
    setState(() {
      _running = false;
      _phase = null;
      _progress = null;
    });
  }

  /// نص المحاضرة: الملزوق وتفريغ التسجيلات. null لو التفريغ وقف أو فشل —
  /// والشاشة بتكون اتظبطت وقتها.
  /// The lecture's text: what was pasted plus the recordings' transcripts.
  /// Null when transcription stopped or failed, with the screen already reset.
  ///
  /// الصوت بيتحوّل لنص الأول. التلخيص من الصوت مباشرة بيخلي الموديل يلخص وهو
  /// بيسمع، فبيضيع كلام — والتفريغ كمان بيتخزن فينفع تراجعه أو تحفظه، ومش
  /// بيتعاد لو طلبت شرح بعد التلخيص.
  /// Audio becomes text first. Summarizing straight from audio makes the model
  /// summarize while listening, which loses what was said — and the
  /// transcript is kept, so it can be read back or saved, and is not redone
  /// when an explanation follows the summary.
  Future<String?> _lectureText(Summarizer summarizer) async {
    var text = _lecture.text.trim();
    if (_clips.isEmpty) return text;

    final transcript = await _transcribeAll(summarizer);
    if (!mounted) return null;
    if (transcript == null) {
      setState(() {
        _running = false;
        _phase = null;
        _progress = null;
      });
      return null;
    }
    text = [text, transcript].where((t) => t.trim().isNotEmpty).join('\n\n');
    if (text.trim().isEmpty && _docs.isEmpty) {
      setState(() {
        _running = false;
        _phase = null;
        _progress = null;
        _error = SummarizerException(context.l.transcriptEmpty);
      });
      return null;
    }
    return text;
  }

  /// المحاضرة للحل: اللي مرفوع فوق (والتسجيلات بعد تفريغها)، أو فاضية.
  /// The lecture for a solution: whatever is uploaded above (recordings once
  /// transcribed), or nothing.
  Future<SolveLecture?> _solveLecture() async {
    if (!_hasInput) return const SolveLecture();
    final summarizer = ref.read(activeSummarizerProvider);
    setState(() {
      _running = true;
      _error = null;
      _phase = null;
      _progress = null;
    });
    final text = await _lectureText(summarizer);
    if (!mounted) return null;
    setState(() {
      _running = false;
      _phase = null;
      _progress = null;
    });
    if (text == null) return null;
    return SolveLecture(text: text, files: List.of(_docs));
  }

  Future<void> _generate() async {
    if (!_hasInput) {
      showSnack(context, context.l.needLectureText);
      return;
    }

    final allSamples = ref.read(styleSamplesProvider).value ?? const <StyleSample>[];
    final samples = pickStyleSamples(allSamples, _subjectId);
    final summarizer = ref.read(activeSummarizerProvider);

    // التلخيص دايمًا بلوكات مرسومة: النص المتدفق ما ينفعش يبقى فيه صور ولا
    // يتقسم صفحات. لو مفيش شكل متحلل من كراستك، بيترسم بالشكل الافتراضي.
    // The summary is always drawable blocks: streamed prose can hold neither
    // pictures nor pages. Without a layout read from the notebook, the
    // default look is used.
    final profiles = ref.read(styleProfilesProvider).value ?? const {};
    final rawProfile = profiles[_subjectId] ?? profiles[null];
    final run = ++_runId;
    final kind = _mode;
    final l = context.l;

    setState(() {
      _running = true;
      _pages.remove(kind);
      _error = null;
      _phase = null;
      _progress = null;
    });

    final text = await _lectureText(summarizer);
    if (text == null || !mounted) return;
    setState(() {
      _phase = switch (kind) {
        StudyOutput.summary => l.generating,
        StudyOutput.explain => l.explaining,
        StudyOutput.review => l.preparingReview,
      };
      _progress = null;
    });

    _source = text;
    try {
      var page = await summarizer.summarizeAsPage(
        lectureText: text,
        files: _docs,
        samples: samples,
        profile: rawProfile == null
            ? const StyleProfile()
            : StyleProfile.fromJson(rawProfile),
        images: _imageMode,
        kind: kind,
        level: _level,
      );
      if (!mounted || run != _runId) return;
      if (page.blocks.any((b) => b.type == BlockType.image)) {
        setState(() => _phase = l.findingImages);
        page = await attachImages(page, pdfs: _pdfs, mode: _imageMode);
        if (!mounted || run != _runId) return;
      }
      setState(() {
        _pages[kind] = page;
        _running = false;
        _phase = null;
      });
    } on SummarizerException catch (e) {
      if (mounted && run == _runId) {
        setState(() {
          _running = false;
          _phase = null;
          _error = e;
        });
      }
    }
  }

  // ------------------------------------------------ الخلفية / background

  Map<String, dynamic> _jobRequest({required bool hasDocs, String? subjectId}) {
    final settings = ref.read(settingsProvider);
    final profiles = ref.read(styleProfilesProvider).value ?? const {};
    final raw = profiles[subjectId] ?? profiles[null];
    return buildJobRequest(
      samples: pickStyleSamples(
        ref.read(styleSamplesProvider).value ?? const <StyleSample>[],
        subjectId,
      ),
      profile: raw == null ? const StyleProfile() : StyleProfile.fromJson(raw),
      hasDocs: hasDocs,
      images: _imageMode,
      model: settings.autoModel || settings.geminiModel.isEmpty
          ? 'auto'
          : settings.geminiModel,
    );
  }

  static String _extFor(String mime) => switch (mime.split(';').first) {
        'audio/webm' => 'webm',
        'audio/mp4' => 'm4a',
        'audio/ogg' => 'ogg',
        'audio/mpeg' || 'audio/mp3' => 'mp3',
        'audio/wav' => 'wav',
        'audio/aac' => 'aac',
        'audio/flac' => 'flac',
        'application/pdf' => 'pdf',
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/heic' => 'heic',
        _ => 'bin',
      };

  /// بيبعت اللي في الشاشة يتلخص على السيرفر: تقفل التطبيق براحتك، والتلخيص
  /// والكروت والملاحظة بيتعملوا ويوصلك إشعار.
  /// Sends what is on screen to be summarized on the server: close the app
  /// freely; the summary, cards and note get made and a notification arrives.
  Future<void> _queueInBackground() async {
    final l = context.l;
    if (!_hasInput) {
      showSnack(context, l.needLectureText);
      return;
    }

    final audio = [
      for (final clip in _clips)
        for (var i = 0; i < clip.parts.length; i++)
          JobFile(
            name: '${clip.name}-$i.${_extFor(clip.mimeType)}',
            mimeType: clip.mimeType,
            bytes: clip.parts[i],
          ),
    ];
    final docs = [
      for (final d in _docs) JobFile(name: d.name, mimeType: d.mimeType, bytes: d.bytes),
    ];
    if ([...audio, ...docs].any((f) => f.bytes.length > maxJobFileBytes)) {
      showSnack(context, l.tooBigForBackground);
      return;
    }

    final now = DateTime.now();
    final entry = _autoEntry;
    final title = entry != null
        ? '${entry.title} ${now.day}/${now.month}'
        : (_extracted?.fileName ??
                (_docs.isNotEmpty ? _docs.first.name : null) ??
                (_clips.isNotEmpty ? _clips.first.name : null) ??
                '${l.lectureNoun} ${now.day}/${now.month}')
            .replaceAll(RegExp(r'\.[^.]+$'), '');

    setState(() => _queuePhase = l.uploadingForBackground(0, audio.length + docs.length));
    try {
      await ref.read(lectureJobsProvider).enqueue(
            title: title,
            subjectId: _subjectId,
            scheduleEntryId: entry?.id,
            audio: audio,
            docs: docs,
            plainText: _lecture.text.trim(),
            request: _jobRequest(hasDocs: docs.isNotEmpty, subjectId: _subjectId),
            onUpload: (done, total) {
              if (mounted) setState(() => _queuePhase = l.uploadingForBackground(done, total));
            },
          );
      if (!mounted) return;
      setState(() {
        _queuePhase = null;
        _clips.clear();
        _docs.clear();
        _extracted = null;
        _lecture.clear();
        _autoEntry = null;
      });
      ref.invalidate(recentJobsProvider);
      showSnack(context, l.queuedForBackground);
    } catch (e) {
      if (!mounted) return;
      setState(() => _queuePhase = null);
      // التسجيل فاضل في الشاشة: لو الرفع وقع، ينفع يتلخص هنا أو يتعاد.
      // The recording stays on screen: if the upload failed, it can be
      // summarized here or retried.
      showSnack(context, '${l.backgroundFailed}\n$e');
    }
  }

  /// بيرفع محاضرات كتير مرة واحدة، كل واحدة شغل لوحدها في الخلفية.
  /// Uploads many lectures at once, each its own background job.
  Future<void> _batchUpload() async {
    final l = context.l;
    final picked = await pickLocalFiles(
      extensions: [
        ...supportedDocumentExtensions,
        ...supportedAudioExtensions,
        ...imageExtensions,
      ],
      mimeTypes: const ['audio/*', 'image/*', ...documentMimeTypes],
    );
    if (picked.isEmpty || !mounted) return;

    // ملفات الوورد والباوربوينت بتتحول نص هنا؛ الـ PDF والصوت بيترفعوا زي ما هما.
    // Word and PowerPoint files become text here; PDFs and audio are uploaded
    // as they are.
    final files = <BatchFile>[];
    final extracted = <BatchFile, String>{};
    for (final f in picked) {
      final audio = isAudioFile(f.name);
      final file = BatchFile(
        name: f.name,
        mimeType: audio ? audioMimeFor(f.name) : f.mimeType,
        bytes: f.bytes,
        modified: f.modified,
      );
      if (!audio && !isModelReadable(f.name) && !isImageFile(f.name)) {
        try {
          final doc = extractDocumentText(f.name, f.bytes);
          if (doc.isEmpty) continue;
          extracted[file] = doc.text;
        } catch (_) {
          continue;
        }
      }
      if (f.bytes.length > maxJobFileBytes) continue;
      files.add(file);
    }

    final schedule = ref.read(scheduleProvider).value ?? const <ScheduleEntry>[];
    final lectures = groupBatch(files, schedule);
    if (lectures.isEmpty) {
      showSnack(context, l.unsupportedFileType);
      return;
    }

    final subjects = ref.read(subjectMapProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.batchConfirmTitle(lectures.length)),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final lec in lectures)
                ListTile(
                  dense: true,
                  leading: Icon(lec.audio.isEmpty
                      ? Icons.description_outlined
                      : Icons.graphic_eq_rounded),
                  title: Text(lec.title),
                  subtitle: Text([
                    subjects[lec.entry?.subjectId ?? _subjectId]?.name ?? l.noSubject,
                    if (lec.docs.isNotEmpty) l.withFiles(lec.docs.length),
                  ].join(' · ')),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.summarizeAll)),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final jobs = ref.read(lectureJobsProvider);
    var queued = 0;
    for (var i = 0; i < lectures.length; i++) {
      final lec = lectures[i];
      final subjectId = lec.entry?.subjectId ?? _subjectId;
      final modelDocs = lec.docs.where((d) => !extracted.containsKey(d)).toList();
      setState(() => _queuePhase = l.batchProgress(i + 1, lectures.length));
      try {
        await jobs.enqueue(
          title: lec.title,
          subjectId: subjectId,
          scheduleEntryId: lec.entry?.id,
          audio: [for (final a in lec.audio) a.asJobFile],
          docs: [for (final d in modelDocs) d.asJobFile],
          plainText: [for (final d in lec.docs) extracted[d] ?? ''].where((t) => t.isNotEmpty).join('\n\n'),
          request: _jobRequest(hasDocs: modelDocs.isNotEmpty, subjectId: subjectId),
        );
        queued++;
      } catch (e) {
        if (mounted) showSnack(context, '${lec.title}: $e');
      }
    }
    if (!mounted) return;
    setState(() => _queuePhase = null);
    ref.invalidate(recentJobsProvider);
    showSnack(context, l.batchQueued(queued));
  }

  Future<void> _saveAsNote() => _saveNote(
        body: _page?.toPlainText() ?? '',
        fallbackTitle: _page?.title.trim() ?? '',
        kind: switch (_mode) {
          StudyOutput.summary => context.l.theSummary,
          StudyOutput.explain => context.l.theExplanation,
          StudyOutput.review => context.l.theReview,
        },
      );

  /// بيحفظ الناتج كملاحظة باسم الملف، ولو مفيش ملف بـ [fallbackTitle].
  /// الشرح والمراجعة بياخدوا نوعهم في العنوان عشان ما يتلخبطوش مع التلخيص.
  /// Saves the output as a note named after the file, else [fallbackTitle].
  /// The explanation and the review carry their kind in the title so they do
  /// not get mixed up with the summary.
  Future<void> _saveNote({
    required String body,
    required String fallbackTitle,
    required String kind,
  }) async {
    final l = context.l;
    final source = _extracted?.fileName ??
        (_docs.isNotEmpty ? _docs.first.name : null) ??
        (_clips.isNotEmpty ? _clips.first.name : null);
    var title = source?.replaceAll(RegExp(r'\.[^.]+$'), '') ?? fallbackTitle;
    if (kind != l.theSummary) title = title.isEmpty ? kind : '$title — $kind';

    try {
      await ref.read(repositoryProvider).addNote(Note(
            id: '',
            title: title.isEmpty ? kind : title,
            body: readableMath(body),
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
    final hasResult = _page != null;
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
            const JobsPanel(),
            const SizedBox(height: Insets.lg),

            // ------------------------------------------- 1. المحتوى / content
            StepCard(
              step: 1,
              done: hasInput,
              title: l.stepContent,
              subtitle: l.stepContentHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_autoEntry != null) ...[
                    InfoBanner(
                      icon: Icons.event_available_rounded,
                      message: l.autoLectureReady(_autoEntry!.title),
                    ),
                    const SizedBox(height: Insets.md),
                  ],
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

                  if (_recorder == null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        onPressed: _running || _queuePhase != null ? null : _batchUpload,
                        icon: const Icon(Icons.library_add_outlined, size: 19),
                        label: Text(l.batchUpload),
                      ),
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
                          icon: doc.mimeType.startsWith('image/')
                              ? Icons.image_outlined
                              : Icons.picture_as_pdf_rounded,
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
                  Text(l.picturesInSummary,
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: Insets.sm),
                  SegmentedButton<ImageMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ImageMode.none,
                        icon: const Icon(Icons.hide_image_outlined, size: 18),
                        label: Text(l.picturesNone),
                      ),
                      ButtonSegment(
                        value: ImageMode.web,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: Text(l.picturesWeb),
                      ),
                      ButtonSegment(
                        value: ImageMode.slides,
                        icon: const Icon(Icons.slideshow_outlined, size: 18),
                        label: Text(l.picturesSlides),
                      ),
                    ],
                    selected: {_imageMode},
                    onSelectionChanged: (s) {
                      setState(() => _imageMode = s.first);
                      saveImageMode(s.first);
                    },
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
                  // نفس المحاضرة، تلات حاجات منها. كل واحدة بتتعمل لما تطلبها
                  // بس — الحصة مشتركة، والتلاتة مع بعض تلات أضعاف الاستهلاك.
                  // One lecture, three things out of it. Each is made only when
                  // asked for: the quota is shared, and all three at once would
                  // cost three times as much.
                  // أربع تابات في موبايل ضيق: الأيقونات بتتشال عشان الكلام يبان.
                  // Four tabs on a narrow phone: the icons go so the words fit.
                  LayoutBuilder(
                    builder: (context, box) {
                      final icons = box.maxWidth >= 460;
                      Icon? icon(IconData d) => icons ? Icon(d, size: 18) : null;
                      return SegmentedButton<Object>(
                        showSelectedIcon: false,
                        style: icons
                            ? null
                            : const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                                padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4)),
                              ),
                        segments: [
                          ButtonSegment(
                            value: StudyOutput.summary,
                            icon: icon(Icons.notes_rounded),
                            label: Text(l.modeSummary, softWrap: false),
                          ),
                          ButtonSegment(
                            value: StudyOutput.explain,
                            icon: icon(Icons.school_outlined),
                            label: Text(l.modeExplain, softWrap: false),
                          ),
                          ButtonSegment(
                            value: StudyOutput.review,
                            icon: icon(Icons.checklist_rounded),
                            label: Text(l.modeReview, softWrap: false),
                          ),
                          ButtonSegment(
                            value: _solveTab,
                            icon: icon(Icons.psychology_alt_outlined),
                            label: Text(l.modeSolve, softWrap: false),
                          ),
                        ],
                        selected: {_solving ? _solveTab : _mode},
                        onSelectionChanged: _running
                            ? null
                            : (s) => setState(() {
                                  _solving = s.first == _solveTab;
                                  if (s.first is StudyOutput) _mode = s.first as StudyOutput;
                                  _error = null;
                                }),
                      );
                    },
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    _solving
                        ? l.modeSolveHint
                        : switch (_mode) {
                            StudyOutput.summary => l.modeSummaryHint,
                            StudyOutput.explain => l.modeExplainHint,
                            StudyOutput.review => l.modeReviewHint,
                          },
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (_mode == StudyOutput.explain && !_solving) ...[
                    const SizedBox(height: Insets.md),
                    Text(l.explainLevel, style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: Insets.sm),
                    SegmentedButton<ExplainLevel>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: ExplainLevel.simple, label: Text(l.levelSimple)),
                        ButtonSegment(value: ExplainLevel.normal, label: Text(l.levelNormal)),
                        ButtonSegment(value: ExplainLevel.deep, label: Text(l.levelDeep)),
                      ],
                      selected: {_level},
                      onSelectionChanged:
                          _running ? null : (s) => setState(() => _level = s.first),
                    ),
                  ],
                  if (_solving) ...[
                    const SizedBox(height: Insets.lg),
                    // التسجيلات بتتفرّغ الأول لو الحل هيمشي على المحاضرة.
                    // Recordings are transcribed first when the solution
                    // follows the lecture.
                    if (_running && _phase != null) ...[
                      ProgressBar(label: _phase!, value: _progress),
                      const SizedBox(height: Insets.lg),
                    ],
                    if (_error != null) ...[
                      _ErrorBox(error: _error!),
                      const SizedBox(height: Insets.lg),
                    ],
                    SolvePanel(
                      hasLecture: hasInput,
                      loadLecture: _solveLecture,
                      subjectId: _subjectId,
                    ),
                  ] else ...[
                  const SizedBox(height: Insets.lg),

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
                        !modelChosen
                            ? l.chooseModelFirst
                            : switch (_mode) {
                                StudyOutput.summary => l.generateSummary,
                                StudyOutput.explain => l.generateExplain,
                                StudyOutput.review => l.generateReview,
                              },
                      ),
                    ),

                  // نفس المحاضرة، بس على السيرفر: ينفع تقفل التطبيق. الشغل في
                  // الخلفية بيعمل التلخيص (ومعاه الكروت والملاحظة) بس.
                  // The same lecture, but on the server: the app can be closed.
                  // The background run makes the summary (with its cards and
                  // note) only.
                  if (!_running && _mode == StudyOutput.summary) ...[
                    const SizedBox(height: Insets.sm),
                    if (_queuePhase != null)
                      ProgressBar(label: _queuePhase!)
                    else
                      OutlinedButton.icon(
                        onPressed: modelChosen && hasInput ? _queueInBackground : null,
                        icon: const Icon(Icons.cloud_upload_outlined, size: 19),
                        label: Text(l.summarizeInBackground),
                      ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: Insets.lg),
                    _ErrorBox(error: _error!),
                  ],

                  // الصفحة المرسومة بتخطيط المستخدم.
                  // The page drawn in the layout read from the notebook.
                  // الشرح بيضيف أمثلة من برّه — الطالب لازم يعرف يفرّقها.
                  // The explanation adds outside examples; the student must be
                  // able to tell them apart.
                  if (_mode == StudyOutput.explain && _page != null) ...[
                    const SizedBox(height: Insets.xl),
                    InfoBanner(message: l.examplesNote),
                  ],

                  if (_page != null) ...[
                    const SizedBox(height: Insets.xl),
                    StyledResult(
                      page: _page!,
                      profile: StyleProfile.fromJson(
                        (profiles[_subjectId] ?? profiles[null]) ?? const {},
                      ),
                      subjectId: _subjectId,
                      source: _source,
                      sourceFiles: _docs,
                      pdfs: _imageMode == ImageMode.slides ? _pdfs : const [],
                      onPageChanged: (page) => setState(() => _pages[_mode] = page),
                      onSaveNote: _saveAsNote,
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

