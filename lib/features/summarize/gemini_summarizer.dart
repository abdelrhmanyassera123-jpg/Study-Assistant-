import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/models.dart';
import 'style_profile.dart';
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

  /// سقف معقول: موديلات Gemini سياقها كبير، بس مش بلا حدود.
  /// A sane ceiling; Gemini's context is large but not unlimited.
  static const inputTokenBudget = 200000;
}

/// بيلخص عن طريق Gemini، والنداء بيعدي من Supabase Edge Function.
/// Summarizes via Gemini, with the call routed through a Supabase Edge Function.
class GeminiSummarizer implements Summarizer {
  GeminiSummarizer(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final GeminiConfig config;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${config.accessToken}',
        'apikey': config.anonKey,
      };

  @override
  Stream<String> summarize({
    String lectureText = '',
    LectureFile? file,
    required List<StyleSample> samples,
  }) async* {
    if (config.model.isEmpty) {
      throw const SummarizerException(
        'مفيش موديل متحدد.',
        hint: 'اختار موديل من إعدادات التلخيص.',
      );
    }
    if (config.accessToken.isEmpty) {
      throw const SummarizerException('لازم تكون مسجّل دخول عشان تستخدم Gemini.');
    }

    if (file != null && file.isTooBig) {
      throw SummarizerException(
        'الملف كبير جدًا (${file.megabytes.toStringAsFixed(1)} ميجا).',
        hint: 'الحد الأقصى ${LectureFile.maxBytes ~/ (1024 * 1024)} ميجا — '
            'قسّم الملف أو صدّره بجودة أقل.',
      );
    }

    final prompt = StudyPrompt.build(
      lectureText: lectureText,
      hasFile: file != null,
      samples: samples,
    );

    final approx = StudyPrompt.approxTokens(prompt);
    if (approx > GeminiConfig.inputTokenBudget) {
      throw SummarizerException(
        'المحاضرة طويلة جدًا (~$approx توكن).',
        hint: 'قسّم المحاضرة لجزئين.',
      );
    }

    final request = http.Request('POST', Uri.parse(config.functionUrl))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'action': 'summarize',
        'model': config.model,
        'system': StudyPrompt.system,
        'prompt': prompt,
        if (file != null)
          'file': {
            'mime_type': file.mimeType,
            'data': base64Encode(file.bytes),
          },
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
      throw SummarizerException(
        _statusMessage(response.statusCode),
        hint: _statusHint(response.statusCode) ?? (body.isEmpty ? null : body),
      );
    }

    // الفنكشن بترجّع NDJSON — نفس شكل Ollama عشان الطرفين يتعاملوا بنفس الطريقة.
    // The function emits NDJSON, deliberately the same shape as Ollama so both
    // paths parse identically.
    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());

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

    final result = await _postJson({
      'action': 'json',
      'model': config.model,
      'system': VisualPrompts.analysisSystem,
      'prompt': VisualPrompts.analysisPrompt,
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
    LectureFile? file,
    required List<StyleSample> samples,
    required StyleProfile profile,
  }) async {
    if (config.model.isEmpty) {
      throw const SummarizerException(
        'مفيش موديل متحدد.',
        hint: 'اختار موديل من إعدادات التلخيص.',
      );
    }
    if (file != null && file.isTooBig) {
      throw SummarizerException(
        'الملف كبير جدًا (${file.megabytes.toStringAsFixed(1)} ميجا).',
      );
    }

    final result = await _postJson({
      'action': 'json',
      'model': config.model,
      'system': VisualPrompts.blocksSystem(profile),
      'prompt': StudyPrompt.build(
        lectureText: lectureText,
        hasFile: file != null,
        samples: samples,
      ),
      if (file != null)
        'files': [
          {'mime_type': file.mimeType, 'data': base64Encode(file.bytes)},
        ],
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

  /// نداء واحد بيرجّع JSON — مشترك بين التحليل والتلخيص المنظم.
  /// One JSON-returning call, shared by the analysis and the structured summary.
  Future<Object?> _postJson(Map<String, dynamic> payload) async {
    if (config.accessToken.isEmpty) {
      throw const SummarizerException('لازم تكون مسجّل دخول عشان تستخدم Gemini.');
    }

    final http.Response response;
    try {
      response = await _client
          .post(Uri.parse(config.functionUrl),
              headers: _headers, body: jsonEncode(payload))
          // التحليل البصري بياخد وقت أطول من التلخيص العادي.
          // Vision analysis takes longer than a plain summary.
          .timeout(const Duration(minutes: 3));
    } catch (e) {
      throw SummarizerException(
        'مش قادر أوصل لخدمة التلخيص.',
        hint: 'اتأكد إن الـ Edge Function متنشرة. ($e)',
      );
    }

    if (response.statusCode != 200) {
      throw SummarizerException(
        _statusMessage(response.statusCode),
        hint: _statusHint(response.statusCode) ??
            utf8.decode(response.bodyBytes),
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final error = body['error'];
    if (error != null) throw SummarizerException('$error');
    return body['result'];
  }

  String _statusMessage(int status) => switch (status) {
        401 || 403 => 'الخدمة رفضت الطلب — سجّل خروج ودخول تاني.',
        404 => 'الموديل "${config.model}" مش متاح لمفتاحك.',
        429 => 'خلصت حصتك المجانية من الموديل ده.',
        500 => 'المفتاح ناقص أو غلط في الخدمة.',
        // 503 شائع جدًا على الخطة المجانية — الفنكشن بتعيد المحاولة 3 مرات
        // قبل ما توصل هنا، فوصولها معناه إن الموديل مزحوم فعلاً.
        // 503 is very common on the free tier; the function already retried
        // three times, so reaching here means the model is genuinely busy.
        503 => 'الموديل مزحوم عند جوجل دلوقتي.',
        _ => 'خدمة التلخيص رجّعت خطأ $status.',
      };

  String? _statusHint(int status) => switch (status) {
        404 => 'اختار موديل تاني من إعدادات التلخيص.',
        429 => 'استنى دقيقة، أو اختار موديل أقدم من الإعدادات — '
            'الموديلات الأحدث حصتها المجانية أضيق (gemini-2.5-flash أوسع).',
        503 => 'استنى دقيقة وجرّب تاني، أو غيّر الموديل من الإعدادات '
            '(gemini-2.5-flash عادة أقل ازدحامًا).',
        _ => null,
      };
}
