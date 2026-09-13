import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/models.dart';
import 'style_profile.dart';
import '../study_ai/study_ai.dart';
import 'summarizer.dart';

/// إعدادات الوصول لـ Gemini — **من ورا Edge Function**، مش مباشرة.
/// Gemini access settings — **through an Edge Function**, never directly.
///
/// المفتاح عمره ما بيوصل للمتصفح. التطبيق بيبعت توكن دخول المستخدم بس،
/// والفنكشن هي اللي عندها المفتاح وبتتأكد إن اللي بينادي مسجّل دخول فعلاً.
/// The API key never reaches the browser. The app sends only the user's access
/// token; the function holds the key and verifies the caller is signed in.
class GeminiConfig {
  const GeminiConfig({
    required this.functionUrl,
    required this.accessToken,
    required this.anonKey,
    this.model = '',
  });

  final String functionUrl;
  final String accessToken;
  final String anonKey;
  final String model;

  /// "auto" بتخلي الخدمة تجرب الموديلات بالترتيب وتنتقل لما واحد يفشل.
  /// "auto" lets the service walk its ranked list, moving on as each fails.
  String get requestedModel => model.isEmpty ? 'auto' : model;
  bool get isAuto => requestedModel == 'auto';

  /// سقف معقول: موديلات Gemini سياقها كبير، بس مش بلا حدود.
  /// A sane ceiling; Gemini's context is large but not unlimited.
  static const inputTokenBudget = 200000;
}

/// بيرفع بايتات ويقول وصل فين — بيتحقن عشان الاختبارات ما تحتاجش متصفح.
/// Uploads bytes and reports progress; injected so the tests need no browser.
typedef ProgressUploader = Future<({int status, String body})> Function({
  required Uri url,
  required Map<String, String> headers,
  required Uint8List bytes,
  void Function(int sent, int total)? onProgress,
});

/// بيلخص عن طريق Gemini، والنداء بيعدي من Supabase Edge Function.
/// Summarizes via Gemini, with the call routed through a Supabase Edge Function.
class GeminiSummarizer implements Summarizer {
  GeminiSummarizer(
    this.config, {
    http.Client? client,
    this.onRequest,
    this.onQuotaLimit,
    this.uploader,
  }) : _client = client ?? http.Client();

  final GeminiConfig config;
  final http.Client _client;

  /// موديل preview أحدث، اتأكد بالاختبار المباشر (رفع جدول حقيقي ومقارنة
  /// الرد يدويًا بالأصل) إنه بيقرا جداول كثيفة أدق بوضوح من الموديل المرتّب
  /// أول عادةً — بس preview يعني جوجل ممكن تغيّره أو تشيله من غير سابق
  /// إنذار، فبيتفضّل بس بترتيب أول مع رجوع تلقائي، مش بيستبدل الترتيب.
  /// A newer preview model, confirmed by direct testing (uploading a real
  /// timetable and hand-checking the reply against the original) to read
  /// dense tables noticeably more accurately than what normally ranks
  /// first. Being "preview" means Google can change or retire it without
  /// notice, so it is only tried first with an automatic fallback, not
  /// substituted for ranking outright.
  static const _preferredScheduleModel = 'gemini-3-flash-preview';

  /// بيتنادى قبل كل طلب توليد — العدّاد الوحيد الصادق للحصة.
  /// Called before each generation request; the only honest quota counter.
  final void Function(String model)? onRequest;

  /// بيرفع البايتات ويقول وصل فين. لما يكون null بنرفع بعميل http العادي من
  /// غير تقدّم — ده وضع الاختبارات.
  /// Uploads the bytes and reports how far it got. When null the plain http
  /// client uploads without progress, which is what the tests use.
  final ProgressUploader? uploader;

  /// بيتنادى لما جوجل تقول الحد المجاني في رسالة تجاوز الحصة.
  /// Called when Google names the free limit in a quota message.
  final void Function(String model, int limit)? onQuotaLimit;

  /// بيستخرج الحد من رسالة 429 — الطريقة الوحيدة لمعرفته، مفيش API بيعرضه.
  /// Pulls the limit out of a 429 body; there is no API that exposes it.
  void _learnLimit(String body) {
    final limit = int.tryParse(
      RegExp(r'limit:\s*(\d+)').firstMatch(body)?.group(1) ?? '',
    );
    final model =
        RegExp(r'model:\s*([\w.\-]+)').firstMatch(body)?.group(1) ?? config.model;
    if (limit != null && model.isNotEmpty) onQuotaLimit?.call(model, limit);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.accessToken}',
        'apikey': config.anonKey,
      };

  @override
  Stream<String> summarize({
    String lectureText = '',
    List<LectureFile> files = const [],
    required List<StyleSample> samples,
  }) async* {
    _requireSignIn();
    _requireFitting(files);

    // الملفات الكبيرة بتترفع الأول؛ الصغيرة بتفضل جوه الطلب.
    // The large files upload first; the small ones stay inside the request.
    final inline = files.where((f) => !f.needsUpload).toList();
    final uploads = <UploadedFile>[];
    for (final file in files.where((f) => f.needsUpload)) {
      uploads.add(await upload(file));
    }

    final prompt = StudyPrompt.build(
      lectureText: lectureText,
      hasFile: files.isNotEmpty,
      samples: samples,
    );

    final approx = StudyPrompt.approxTokens(prompt);
    if (approx > GeminiConfig.inputTokenBudget) {
      throw SummarizerException(
        'المحاضرة طويلة جدًا (~$approx توكن).',
        hint: 'قسّم المحاضرة لجزئين.',
      );
    }

    yield* _stream(
      system: StudyPrompt.system,
      prompt: prompt,
      files: inline,
      uploads: uploads,
      temperature: 0.4,
    );
  }

  @override
  Future<String> transcribe(LectureFile audio, {UploadedFile? uploaded}) async {
    _requireSignIn();
    _requireFitting([audio]);

    // الملف الكبير بيترفع الأول ويتبعت كرابط. الصغير بيتبعت جوه الطلب — رحلة
    // زيادة لجوجل مش هتفيد في مقطع 2 ميجا.
    // A large file is uploaded first and sent as a URI. A small one rides
    // inside the request: a second trip to Google buys nothing for 2 MB.
    final ref = uploaded ?? (audio.needsUpload ? await upload(audio) : null);

    final buffer = StringBuffer();
    await for (final piece in _stream(
      system: StudyPrompt.transcribeSystem,
      prompt: StudyPrompt.transcribePrompt,
      files: ref == null ? [audio] : const [],
      uploads: ref == null ? const [] : [ref],
      // التفريغ نقل مش تأليف: أقل حرارة ممكنة عشان الموديل ما يكمّلش من عنده
      // الكلام اللي مش سامعه كويس.
      // Transcription is transcription, not writing: the lowest temperature, so
      // the model does not invent its way through what it could not hear.
      temperature: 0,
    )) {
      buffer.write(piece);
    }
    return buffer.toString().trim();
  }

  @override
  Future<UploadedFile> upload(
    LectureFile file, {
    void Function(double fraction)? onProgress,
  }) async {
    _requireSignIn();
    _requireFitting([file]);

    final url = Uri.parse('${config.functionUrl}?action=upload');
    final headers = {
      'Authorization': 'Bearer ${config.accessToken}',
      'apikey': config.anonKey,
      'Content-Type': 'application/octet-stream',
      'x-file-mime': file.mimeType,
      'x-file-size': '${file.bytes.length}',
      // الهيدرز بتتبعت ASCII بس، واسم المحاضرة غالبًا عربي.
      // Headers travel as ASCII only, and a lecture's name is usually Arabic.
      'x-file-name': Uri.encodeComponent(file.name),
    };

    final int status;
    final String text;
    try {
      final send = uploader;
      if (send != null) {
        final result = await send(
          url: url,
          headers: headers,
          bytes: file.bytes,
          onProgress: (sent, total) =>
              onProgress?.call(total == 0 ? 0 : sent / total),
        );
        status = result.status;
        text = result.body;
      } else {
        final response =
            await _client.post(url, headers: headers, body: file.bytes);
        status = response.statusCode;
        text = utf8.decode(response.bodyBytes);
      }
    } catch (e) {
      throw SummarizerException(
        'الرفع فشل قبل ما يوصل.',
        hint: 'اتأكد إن النت شغال وجرب تاني. ($e)',
      );
    }

    if (status != 200) {
      if (status == 429) _learnLimit(text);
      throw SummarizerException(
        _statusMessage(status),
        hint: _statusHint(status) ?? (text.isEmpty ? null : text),
      );
    }
    onProgress?.call(1);

    final body = jsonDecode(text) as Map<String, dynamic>;
    final uri = body['uri'] as String?;
    if (uri == null || uri.isEmpty) {
      throw const SummarizerException('الرفع رجع من غير رابط للملف.');
    }

    final uploaded = UploadedFile(
      uri: uri,
      mimeType: (body['mime_type'] as String?) ?? file.mimeType,
      name: (body['name'] as String?) ?? '',
      state: (body['state'] as String?) ?? 'UNKNOWN',
    );

    if (uploaded.state == 'FAILED') {
      throw SummarizerException(
        'الملف اترفع بس الخدمة مش قادرة تقراه.',
        hint: 'اتأكد إنه ملف صوت سليم، أو صدّره mp3 وجرب تاني.',
      );
    }
    return uploaded;
  }

  void _requireSignIn() {
    if (config.accessToken.isEmpty) {
      throw const SummarizerException('لازم تكون مسجّل دخول عشان تستخدم Gemini.');
    }
  }

  /// بيتأكد إن كل ملف جوه السقف قبل ما نبعت حاجة.
  /// Checks every file is inside the ceiling before anything is sent.
  ///
  /// الفحص قبل الإرسال مش بعده: الطلب الكبير بيموت في الـ Edge Function
  /// بـ WORKER_RESOURCE_LIMIT، ودي رسالة ما بتقولش للمستخدم يعمل إيه.
  /// Checked before sending rather than after: an oversized request dies inside
  /// the Edge Function as WORKER_RESOURCE_LIMIT, a message that tells the user
  /// nothing about what to do.
  void _requireFitting(List<LectureFile> files) {
    for (final file in files) {
      if (!file.isTooBig) continue;
      throw SummarizerException(
        '${file.name}: كبير جدًا (${file.megabytes.toStringAsFixed(1)} ميجا).',
        hint: 'الحد ${LectureFile.maxBytes ~/ (1024 * 1024)} ميجا — '
            'صدّر الملف بجودة أقل أو قسّمه.',
      );
    }
  }

  /// أجزاء الملفات في الطلب: المرفوع بالرابط، والصغير ببايتاته.
  /// The file parts of a request: uploaded ones by URI, small ones by bytes.
  List<Map<String, String>> _fileParts(
    List<LectureFile> inline,
    List<UploadedFile> uploads,
  ) =>
      [
        for (final file in uploads)
          {'mime_type': file.mimeType, 'file_uri': file.uri},
        for (final file in inline)
          {'mime_type': file.mimeType, 'data': base64Encode(file.bytes)},
      ];

  /// نداء بث واحد — مشترك بين التلخيص والتفريغ.
  /// One streaming call, shared by summarizing and transcribing.
  Stream<String> _stream({
    required String system,
    required String prompt,
    required List<LectureFile> files,
    required double temperature,
    List<UploadedFile> uploads = const [],
  }) async* {
    final request = http.Request('POST', Uri.parse(config.functionUrl))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'action': 'summarize',
        'model': config.requestedModel,
        'system': system,
        'prompt': prompt,
        'temperature': temperature,
        if (files.isNotEmpty || uploads.isNotEmpty)
          'files': _fileParts(files, uploads),
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw SummarizerException(
        'مش قادر أوصل لخدمة التلخيص.',
        hint: 'اتأكد إن الـ Edge Function متنشرة. ($e)',
      );
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (response.statusCode == 429) _learnLimit(body);
      throw SummarizerException(
        _statusMessage(response.statusCode),
        hint: _statusHint(response.statusCode) ?? (body.isEmpty ? null : body),
      );
    }

    // الفنكشن بترجّع NDJSON — سطر لكل قطعة.
    // The function emits NDJSON: one line per chunk.
    final lines =
        response.stream.transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      if (line.trim().isEmpty) continue;

      final Map<String, dynamic> chunk;
      try {
        chunk = jsonDecode(line) as Map<String, dynamic>;
      } on FormatException {
        continue;
      }

      final error = chunk['error'];
      if (error != null) throw SummarizerException('$error');

      // الخدمة بتقول في أول سطر أي موديل رد — في الوضع التلقائي ده الوحيد
      // اللي بيعرّفنا نحسب الاستهلاك على مين.
      // The service names the answering model on the first line; in auto mode
      // that is the only way to know whose quota was spent.
      final answered = chunk['model'] as String?;
      if (answered != null && answered.isNotEmpty) {
        onRequest?.call(answered);
        continue;
      }

      final piece = chunk['text'] as String?;
      if (piece != null && piece.isNotEmpty) yield piece;

      if (chunk['done'] == true) return;
    }
  }

  @override
  Future<List<String>> listModels() async {
    if (config.accessToken.isEmpty) {
      throw const SummarizerException('لازم تكون مسجّل دخول عشان تستخدم Gemini.');
    }

    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(config.functionUrl),
            headers: _headers,
            body: jsonEncode({'action': 'models'}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw SummarizerException(
        'مش قادر أوصل لخدمة التلخيص.',
        hint: 'اتأكد إن الـ Edge Function متنشرة. ($e)',
      );
    }

    if (response.statusCode != 200) {
      throw SummarizerException(
        _statusMessage(response.statusCode),
        hint: utf8.decode(response.bodyBytes),
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    // مفيش ترتيب هنا بقصد: الفنكشن بترتبهم بالفايدة، والتطبيق بيختار الأول.
    // Deliberately unsorted: the function ranks them by usefulness and the app
    // auto-selects the first, so re-sorting here would undo that.
    return (body['models'] as List<dynamic>? ?? const [])
        .map((m) => '$m')
        .where((n) => n.isNotEmpty)
        .toList();
  }

  @override
  Future<StyleAnalysis> analyzeStyle(List<LectureFile> images) async {
    if (images.isEmpty) {
      throw const SummarizerException('محتاج صورة واحدة على الأقل.');
    }
    for (final image in images) {
      if (image.isTooBig) {
        throw SummarizerException(
          'الصورة "${image.name}" كبيرة جدًا '
          '(${image.megabytes.toStringAsFixed(1)} ميجا).',
        );
      }
    }

    // الحد على الطلب كله مش على الصورة الواحدة، والترميز base64 بيكبّر
    // الحجم حوالي الثلث — فبنقيس المجموع قبل ما نبعت.
    // The cap applies to the whole request, not one image, and base64 inflates
    // by about a third, so the total is checked before sending.
    final totalMb = images.fold<double>(0, (sum, i) => sum + i.megabytes);
    if (totalMb * 1.34 > 8) {
      throw SummarizerException(
        'الصور مع بعض كبيرة جدًا (${totalMb.toStringAsFixed(1)} ميجا).',
        hint: 'ارفع صور أقل في المرة الواحدة.',
      );
    }

    final result = await _postJson({
      'action': 'json',
      'model': config.requestedModel,
      'system': VisualPrompts.analysisSystem,
      'prompt': VisualPrompts.analysisPrompt(images.length),
      'files': [
        for (final image in images)
          {'mime_type': image.mimeType, 'data': base64Encode(image.bytes)},
      ],
    });

    final parsed = decodeModelJson(result);
    if (parsed == null) {
      throw const SummarizerException('الموديل رجّع تحليل مش مفهوم.');
    }
    return StyleAnalysis.fromJson(parsed);
  }

  @override
  Future<SummaryPage> summarizeAsPage({
    String lectureText = '',
    List<LectureFile> files = const [],
    required List<StyleSample> samples,
    required StyleProfile profile,
  }) async {
    _requireFitting(files);

    final inline = files.where((f) => !f.needsUpload).toList();
    final uploads = <UploadedFile>[];
    for (final file in files.where((f) => f.needsUpload)) {
      uploads.add(await upload(file));
    }

    final result = await _postJson({
      'action': 'json',
      'model': config.requestedModel,
      'system': VisualPrompts.blocksSystem(profile),
      'prompt': StudyPrompt.build(
        lectureText: lectureText,
        hasFile: files.isNotEmpty,
        samples: samples,
      ),
      if (files.isNotEmpty)
        'files': _fileParts(inline, uploads),
    });

    final parsed = decodeModelJson(result);
    if (parsed == null) {
      throw const SummarizerException('الموديل رجّع تلخيص مش مفهوم.');
    }
    final page = SummaryPage.fromJson(parsed);
    if (page.blocks.isEmpty) {
      throw const SummarizerException('التلخيص رجع فاضي — جرّب تاني.');
    }
    return page;
  }

  @override
  Future<List<GeneratedCard>> makeCards(String source, {int count = 8}) async {
    _requireSignIn();
    _requireText(source);

    final result = await _postJson({
      'action': 'json',
      'model': config.requestedModel,
      'system': StudyAiPrompts.cardsSystem,
      'prompt': StudyAiPrompts.cardsPrompt(_capped(source), count),
    });

    final rows = decodeModelJson(result)?['cards'];
    if (rows is! List) {
      throw const SummarizerException('الكروت رجعت بشكل مش مفهوم.');
    }

    final cards = <GeneratedCard>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final card = GeneratedCard.fromJson(row.map((k, v) => MapEntry('$k', v)));
      if (card != null) cards.add(card);
    }

    if (cards.isEmpty) {
      throw const SummarizerException(
        'مطلعش كروت من المحتوى ده.',
        hint: 'المحتوى ممكن يكون قصير أوي أو مفيهوش معلومات تتحفظ.',
      );
    }
    return cards;
  }

  @override
  Stream<String> ask({
    required String source,
    required String question,
    List<AskTurn> history = const [],
  }) async* {
    _requireSignIn();
    _requireText(source);

    yield* _stream(
      system: StudyAiPrompts.askSystem,
      prompt: StudyAiPrompts.askPrompt(
        source: _capped(source),
        question: question,
        history: history,
      ),
      files: const [],
      // الإجابة من محتوى موجود: الحرارة الواطية بتخليها تلتزم بيه.
      // The answer comes from material that exists; a low temperature keeps it
      // there.
      temperature: 0.2,
    );
  }

  @override
  Future<List<ExamQuestion>> makeExam({
    required String source,
    int choiceCount = 6,
    int writtenCount = 2,
  }) async {
    _requireSignIn();
    _requireText(source);

    final result = await _postJson({
      'action': 'json',
      'model': config.requestedModel,
      'system': StudyAiPrompts.examSystem,
      'prompt': StudyAiPrompts.examPrompt(
        source: _capped(source),
        choiceCount: choiceCount,
        writtenCount: writtenCount,
      ),
    });

    final rows = decodeModelJson(result)?['questions'];
    if (rows is! List) {
      throw const SummarizerException('الامتحان رجع بشكل مش مفهوم.');
    }

    final questions = <ExamQuestion>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final q = ExamQuestion.fromJson(row.map((k, v) => MapEntry('$k', v)));
      if (q != null) questions.add(q);
    }

    if (questions.isEmpty) {
      throw const SummarizerException('مطلعش أسئلة من المحتوى ده.');
    }
    return questions;
  }

  @override
  Future<ExamResult> gradeExam({
    required String source,
    required List<AnsweredQuestion> answers,
  }) async {
    _requireSignIn();

    final result = await _postJson({
      'action': 'json',
      'model': config.requestedModel,
      'system': StudyAiPrompts.gradeSystem,
      'prompt': StudyAiPrompts.gradePrompt(
        source: _capped(source),
        answers: [
          for (final a in answers)
            (
              index: a.index,
              question: a.question,
              expected: a.expected,
              answer: a.answer,
            ),
        ],
      ),
    });

    final parsed = decodeModelJson(result);
    if (parsed == null) {
      throw const SummarizerException('التصحيح رجع بشكل مش مفهوم.');
    }

    final marks = <WrittenMark>[];
    final rawMarks = parsed['marks'];
    if (rawMarks is List) {
      for (final row in rawMarks) {
        if (row is! Map) continue;
        final mark = WrittenMark.fromJson(row.map((k, v) => MapEntry('$k', v)));
        if (mark != null) marks.add(mark);
      }
    }

    final weak = <String>[];
    final rawWeak = parsed['weak'];
    if (rawWeak is List) {
      for (final w in rawWeak) {
        final text = '$w'.trim();
        if (text.isNotEmpty) weak.add(text);
      }
    }

    return ExamResult(
      marks: marks,
      weakSpots: weak,
      advice: '${parsed['advice'] ?? ''}'.trim(),
    );
  }

  @override
  Future<StudyPlan> makePlan(String facts) async {
    _requireSignIn();
    _requireText(facts);

    final result = await _postJson({
      'action': 'json',
      'model': config.requestedModel,
      'system': StudyAiPrompts.planSystem,
      'prompt': facts,
    });

    final parsed = decodeModelJson(result);
    final rows = parsed?['days'];
    if (rows is! List) {
      throw const SummarizerException('الخطة رجعت بشكل مش مفهوم.');
    }

    final days = <PlanDay>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final weekday = ParsedLecture.weekdayFromName('${row['day'] ?? ''}');
      if (weekday == null) continue;

      final items = <PlanItem>[];
      final rawItems = row['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is! Map) continue;
          final planItem =
              PlanItem.fromJson(item.map((k, v) => MapEntry('$k', v)));
          if (planItem != null) items.add(planItem);
        }
      }
      if (items.isNotEmpty) days.add(PlanDay(weekday: weekday, items: items));
    }

    if (days.isEmpty) {
      throw const SummarizerException('مطلعتش خطة — جرّب تاني.');
    }

    days.sort((a, b) => a.weekday.compareTo(b.weekday));
    return StudyPlan(
      days: days,
      note: '${parsed?['note'] ?? ''}'.trim(),
    );
  }

  void _requireText(String source) {
    if (source.trim().length < 40) {
      throw const SummarizerException(
        'المحتوى قصير أوي.',
        hint: 'لخّص المحاضرة الأول أو احفظها كملاحظة، وبعدين جرّب.',
      );
    }
  }

  /// المحتوى الطويل بيتقص قبل ما يتبعت — الطلب اللي بيعدي السقف بيترفض كله.
  /// Long material is trimmed before it is sent: a request past the ceiling is
  /// refused whole.
  String _capped(String source) {
    const limit = GeminiConfig.inputTokenBudget * 2;
    final text = source.trim();
    return text.length <= limit ? text : text.substring(0, limit);
  }

  @override
  Future<ParsedSchedule> parseSchedule({
    String text = '',
    List<LectureFile> images = const [],
    void Function(double fraction)? onProgress,
  }) async {
    _requireSignIn();
    _requireFitting(images);

    if (text.trim().isEmpty && images.isEmpty) {
      throw const SummarizerException('محطتش جدول ولا صورة.');
    }

    // كل ملف هنا بيترفع الأول بدل ما يتحط base64 جوه الطلب — حتى الصغير.
    // مفيش تصغير للـ PDF زي الصور، وحتى ملف مية كيلو حصل يطلّع 546 (الفنكشن
    // بتخلّص ذاكرتها وهي بتبني جسم الطلب لجوجل)، غالبًا بسبب طلبات تانية
    // شغالة على نفس الفنكشن الدافية في نفس الوقت. الرفع بيتمرر تمرير من غير
    // ما يتجمّع في الذاكرة، فبيفضل مأمون تحت أي ضغط.
    // Every file here uploads first instead of riding as base64 inside the
    // request — even a small one. PDFs are not shrunk the way images are, and
    // even a 100 KB file has triggered 546 (the function running out of
    // memory while building the request to Google), most likely from other
    // requests sharing the same warm function at the same time. Uploading
    // streams through without ever gathering bytes in memory, so it stays
    // safe under load regardless of file size.
    //
    // الرفع ياخد جزء من الشريط لو في ملفات (تقدّم حقيقي بالبايت)، والباقي —
    // وهو الأطول بمراحل، مستند معقد بياخد دقيقة ودقيقتين — بيتحرك مع كل
    // بينج من `_postJson` من غير ما يوصل النهاية أبدًا قبل ما الرد يوصل
    // فعلاً، عشان الشريط يفضل صادق مهما طال الانتظار.
    // Uploads take a slice of the bar when there are files (real byte
    // progress); the rest — the much longer part, a minute or two for a
    // complex document — moves with each heartbeat from `_postJson` without
    // ever reaching the end before the reply actually arrives, so the bar
    // stays honest no matter how long the wait runs.
    final uploadShare = images.isEmpty ? 0.0 : 0.2;
    // باقي الشريط بعد الرفع مقسوم بين مرحلتين: اكتشاف التركيب (أخف بكتير)
    // واستخراج المحاضرات (الأتقل، وده اللي بياخد معظم الوقت).
    // The rest of the bar after upload splits across two phases: structure
    // discovery (much lighter) and entry extraction (the heavy one, taking
    // most of the time).
    final structureEnd = uploadShare + (1 - uploadShare) * 0.25;

    final uploads = <UploadedFile>[];
    for (var i = 0; i < images.length; i++) {
      uploads.add(await upload(
        images[i],
        onProgress: (fraction) =>
            onProgress?.call(uploadShare * (i + fraction) / images.length),
      ));
    }
    onProgress?.call(uploadShare);

    final files = images.isNotEmpty ? _fileParts(const [], uploads) : null;

    // مرحلة 1: اكتشاف تركيب الجدول بس (أعمدة الوقت والأقسام) — مهمة أصغر
    // بكتير من استخراج كل المحاضرات، وأدق لأنها مش شايلة كل حاجة مرة واحدة.
    // Phase 1: discover just the table's structure (time columns, sections)
    // — a much smaller task than extracting every lecture, and more accurate
    // for not carrying everything at once.
    var pendingCount = 0;
    final structureResult = await _postJson(
      {
        'action': 'json',
        'model': config.requestedModel,
        // اتأكد بالاختبار المباشر إنه بيقرا الجداول الكثيفة دي أدق من
        // الموديل العادي المرتّب أول — متجاهلة لو المستخدم اختار موديل
        // بعينه، ومع رجوع تلقائي للترتيب العادي لو مش متاح لمفتاحه.
        // Confirmed by direct testing to read these dense tables more
        // accurately than the normally-top-ranked model — ignored when the
        // user picked a specific model, and falls back to normal ranking
        // when unavailable on their key.
        'preferred_model': _preferredScheduleModel,
        'system': StudyPrompt.scheduleStructureSystem,
        'prompt': StudyPrompt.scheduleStructurePrompt(text),
        if (files != null) 'files': files,
      },
      onPending: () {
        pendingCount++;
        final waitFraction = 1 - 1 / (pendingCount + 1);
        onProgress?.call(uploadShare + (structureEnd - uploadShare) * waitFraction);
      },
    );
    onProgress?.call(structureEnd);

    final structure = decodeModelJson(structureResult);

    // بنبني شريط الأعمدة إحنا بالحساب، مش بنسيب الموديل يعدّدها — تعدادها
    // كان بيتلخبط ("استراحة" بتتكرر غلط، وترتيب غلط) حتى لما نطلبها صريحة.
    // قراية بداية اليوم ونهايته وطول العمود مهمة أبسط بكتير وبتغلط أقل.
    // We build the column ladder ourselves by arithmetic instead of letting
    // the model enumerate it — enumeration kept getting scrambled ("Break"
    // duplicated wrongly, out of order) even when asked for explicitly.
    // Reading the day's start, end, and slot length is a much simpler task
    // that errors far less.
    final dayStartMin = ParsedLecture.minutesFromClock('${structure?['day_start'] ?? ''}');
    final dayEndMin = ParsedLecture.minutesFromClock('${structure?['day_end'] ?? ''}');
    final slotMinutes = num.tryParse('${structure?['slot_minutes'] ?? ''}')?.toInt() ?? 0;

    final timeColumns = <String>[];
    if (dayStartMin != null && dayEndMin != null && slotMinutes > 0) {
      String clock(int m) =>
          '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      for (var t = dayStartMin; t < dayEndMin; t += slotMinutes) {
        timeColumns.add('${clock(t)}-${clock(t + slotMinutes)}');
      }
    }

    final groups = <String>[];
    final rawGroups = structure?['groups'];
    if (rawGroups is List) {
      for (final g in rawGroups) {
        final name = '$g'.trim();
        if (name.isNotEmpty && !groups.contains(name)) groups.add(name);
      }
    }
    final groupLabel = '${structure?['group_label'] ?? ''}'.trim();

    final days = <String>[
      for (final d in (structure?['days'] as List?) ?? const []) '$d'.trim(),
    ]..removeWhere((d) => d.isEmpty);

    // مرحلة 2: استخراج المحاضرات، شايلة تركيب المرحلة الأولى كحقيقة مؤكدة.
    // لو الأيام معروفة، بنطلب كل يوم في نداء لوحده — جدول أسبوع كامل في رد
    // واحد بيبقى تقيل وممكن ياخد وقت يقرب من مهلة السيرفر، ورد يوم واحد
    // بيفضل صغير ودايمًا سريع.
    // Phase 2: extract the lectures, carrying phase one's structure as an
    // established fact. When the days are known, each is requested in its
    // own call — a whole week in one reply gets heavy and can brush against
    // the server's time ceiling, while a single day's reply stays small and
    // reliably fast.
    final dayScopes = days.isEmpty ? const <String?>[null] : days;
    final rows = <dynamic>[];

    for (var i = 0; i < dayScopes.length; i++) {
      final day = dayScopes[i];
      pendingCount = 0;
      try {
        final entriesResult = await _postJson(
          {
            'action': 'json',
            'model': config.requestedModel,
            'preferred_model': _preferredScheduleModel,
            'system': StudyPrompt.scheduleEntriesSystem(
              timeColumns: timeColumns,
              groups: groups,
              groupLabel: groupLabel,
              day: day,
            ),
            'prompt': StudyPrompt.scheduleEntriesPrompt(text, day: day),
            if (files != null) 'files': files,
          },
          onPending: () {
            pendingCount++;
            final waitFraction = 1 - 1 / (pendingCount + 1);
            final callStart = structureEnd +
                (1 - structureEnd) * i / dayScopes.length;
            final callEnd = structureEnd +
                (1 - structureEnd) * (i + 1) / dayScopes.length;
            onProgress?.call(callStart + (callEnd - callStart) * waitFraction);
          },
        );

        final dayRows = decodeModelJson(entriesResult)?['entries'];
        if (dayRows is List) rows.addAll(dayRows);
      } on SummarizerException {
        // يوم واحد فشل (حصة خلصت، تايم آوت) مبرّرش نضيع كل الأيام التانية
        // اللي فعلاً نجحت — نكمل الباقي ونسيب اللي فشل من غير جدوله.
        // One day failing (quota spent, timeout) is not a reason to lose
        // every other day that actually succeeded — keep going and leave the
        // failed one unscheduled.
      }
      onProgress?.call(
        structureEnd + (1 - structureEnd) * (i + 1) / dayScopes.length,
      );
    }

    if (rows.isEmpty) {
      throw const SummarizerException('الجدول رجع بشكل مش مفهوم.');
    }

    // الصف الناقص بيتشال بدل ما يوقف الباقي: جدول فيه 12 محاضرة وواحدة
    // مقروءة غلط لسه أنفع من رسالة خطأ.
    // A malformed row is dropped rather than stopping the rest: a timetable
    // with twelve lectures and one misread row still beats an error message.
    final entries = <ParsedLecture>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final lecture = ParsedLecture.fromJson(
        row.map((k, v) => MapEntry('$k', v)),
      );
      if (lecture != null) entries.add(lecture);
    }

    if (entries.isEmpty) {
      throw const SummarizerException(
        'مفيش محاضرات اتقريت من الجدول.',
        hint: 'اتأكد إن الصورة واضحة، أو الزق الجدول كنص.',
      );
    }

    entries.sort((a, b) => a.weekday != b.weekday
        ? a.weekday.compareTo(b.weekday)
        : a.startMinutes.compareTo(b.startMinutes));

    // الأقسام اللي ظهرت في المحاضرات بتتضاف لو الموديل نساها في القايمة.
    // Sections that turned up on the lectures are added when the model left
    // them out of its own list.
    for (final entry in entries) {
      if (entry.group.isNotEmpty && !groups.contains(entry.group)) {
        groups.add(entry.group);
      }
    }

    return ParsedSchedule(
      entries: entries,
      groups: groups,
      groupLabel: groupLabel,
      note: '${structure?['note'] ?? ''}'.trim(),
    );
  }

  /// نداء واحد بيرجّع JSON — مشترك بين التحليل والتلخيص المنظم.
  /// One JSON-returning call, shared by the analysis and the structured summary.
  ///
  /// الرد NDJSON: بينج كل 15 ثانية لحد ما جوجل يرد، وآخر سطر فيه النتيجة أو
  /// الخطأ. نفس آلية `_stream` بالظبط، ومتحقّق منها محليًا بسيرفر Node قبل
  /// النشر: البايتات بتوصل لحظة بلحظة، والتقسيم على أسطر شغال حتى لو كذا
  /// سطر جم في نفس الحزمة.
  /// The reply is NDJSON: a heartbeat every 15s while waiting on Google, then
  /// a final line with the result or the error. Same mechanism as `_stream`,
  /// and verified locally with a Node server before shipping: bytes arrive
  /// incrementally, and line-splitting holds up even when several lines land
  /// in one packet.
  Future<Object?> _postJson(
    Map<String, dynamic> payload, {
    void Function()? onPending,
  }) async {
    if (config.accessToken.isEmpty) {
      throw const SummarizerException('لازم تكون مسجّل دخول عشان تستخدم Gemini.');
    }

    final request = http.Request('POST', Uri.parse(config.functionUrl))
      ..headers.addAll(_headers)
      ..body = jsonEncode(payload);

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(const Duration(seconds: 30));
    } catch (e) {
      throw SummarizerException(
        'مش قادر أوصل لخدمة التلخيص.',
        hint: 'اتأكد إن الـ Edge Function متنشرة. ($e)',
      );
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      if (response.statusCode == 429) _learnLimit(body);
      throw SummarizerException(
        _statusMessage(response.statusCode),
        hint: _statusHint(response.statusCode) ?? body,
      );
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        // بينج كل 15 ثانية من عندهم؛ 50 ثانية من غير حرف يبقى الاتصال اتقطع.
        // Heartbeats arrive every 15s from their side; 50s with nothing means
        // the connection itself dropped.
        .timeout(const Duration(seconds: 50));

    try {
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;

        final Map<String, dynamic> chunk;
        try {
          chunk = jsonDecode(line) as Map<String, dynamic>;
        } on FormatException {
          continue;
        }

        if (chunk['pending'] == true) {
          onPending?.call();
          continue;
        }

        final error = chunk['error'];
        if (error != null) {
          final status = chunk['status'] as int?;
          final detail = chunk['detail'] as String?;
          final body = [error, detail].whereType<String>().join('\n');
          if (status == 429) _learnLimit(body);
          throw SummarizerException(
            status != null ? _statusMessage(status) : '$error',
            hint: status != null ? (_statusHint(status) ?? body) : detail,
          );
        }

        final answered = chunk['model'] as String?;
        if (answered != null && answered.isNotEmpty) onRequest?.call(answered);

        return chunk['result'];
      }
    } on TimeoutException {
      throw const SummarizerException(
        'خدمة التلخيص ماردتش من زمان.',
        hint: 'جرب تاني.',
      );
    }

    throw const SummarizerException('خدمة التلخيص رجعت رد فاضي.');
  }

  String _statusMessage(int status) => switch (status) {
        401 || 403 => 'الخدمة رفضت الطلب — سجّل خروج ودخول تاني.',
        404 => config.isAuto
            ? 'مفيش موديل متاح لمفتاحك دلوقتي.'
            : 'الموديل "${config.model}" مش متاح لمفتاحك.',
        429 => 'خلصت حصتك المجانية من الموديل ده.',
        500 => 'المفتاح ناقص أو غلط في الخدمة.',
        // 503 شائع جدًا على الخطة المجانية — الفنكشن بتعيد المحاولة 3 مرات
        // قبل ما توصل هنا، فوصولها معناه إن الموديل مزحوم فعلاً.
        // 503 is very common on the free tier; the function already retried
        // three times, so reaching here means the model is genuinely busy.
        503 => 'الموديل مزحوم عند جوجل دلوقتي.',
        // 546 من Supabase مش من جوجل: الفنكشن خلصت ذاكرتها وهي بتناول الملف.
        // 546 comes from Supabase, not Google: the function ran out of memory
        // while relaying the file.
        546 => 'الملفات كبيرة على خدمة التلخيص.',
        _ => 'خدمة التلخيص رجّعت خطأ $status.',
      };

  String? _statusHint(int status) => switch (status) {
        404 => config.isAuto
            ? 'اتأكد إن المفتاح شغال من إعدادات التلخيص.'
            : 'شغّل الاختيار التلقائي من إعدادات التلخيص.',
        429 => config.isAuto
            ? 'كل الموديلات المتاحة خلصت حصتها — استنى دقيقة وجرّب تاني.'
            : 'شغّل الاختيار التلقائي عشان ينتقل لموديل تاني لوحده.',
        503 => 'استنى دقيقة وجرّب تاني، أو غيّر الموديل من الإعدادات '
            '(gemini-2.5-flash عادة أقل ازدحامًا).',
        546 => 'ارفع صور أقل في المرة الواحدة، أو ملف PDF أصغر.',
        _ => null,
      };
}
