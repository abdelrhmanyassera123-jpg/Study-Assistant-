import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/models.dart';
import 'summarizer.dart';

/// إعدادات الاتصال بـ Ollama المحلي.
/// Connection settings for the local Ollama server.
class OllamaConfig {
  const OllamaConfig({
    this.baseUrl = 'http://localhost:11434',
    this.model = '',
    this.numCtx = 16384,
  });

  final String baseUrl;
  final String model;

  /// حجم السياق للنداء الواحد. بنبعته صراحة لأن الموديل المحفوظ ممكن يكون
  /// متظبط على قيمة صغيرة (8192 مثلاً) مش كفاية لمحاضرة كاملة.
  /// Per-request context size. Sent explicitly because a saved model may carry
  /// a small default (8192, say) that a full lecture won't fit into.
  final int numCtx;

  /// بنسيب مساحة للتلخيص نفسه وللتعليمات — مش كل السياق للمدخلات.
  /// Leave room for the summary and the instructions; the input can't claim
  /// the whole window.
  int get inputTokenBudget => (numCtx * 0.7).round();
}

/// بيلخص بموديل شغال على جهاز المستخدم عن طريق Ollama.
/// Summarizes with a model running on the user's own machine via Ollama.
class OllamaSummarizer implements Summarizer {
  OllamaSummarizer(this.config, {http.Client? client})
      : _client = client ?? http.Client();

  final OllamaConfig config;
  final http.Client _client;

  @override
  Stream<String> summarize({
    required String lectureText,
    required List<StyleSample> samples,
  }) async* {
    if (config.model.isEmpty) {
      throw const SummarizerException(
        'مفيش موديل متحدد.',
        hint: 'اختار موديل من إعدادات التلخيص.',
      );
    }

    final prompt = StudyPrompt.build(lectureText: lectureText, samples: samples);

    // بنرفض بدل ما نقص المدخلات في السر — التلخيص الناقص أسوأ من رسالة واضحة.
    // Refuse rather than silently truncate; a quietly clipped lecture produces
    // a confidently wrong summary.
    final approx = StudyPrompt.approxTokens(prompt);
    if (approx > config.inputTokenBudget) {
      throw SummarizerException(
        'المحاضرة أطول من سياق الموديل (~$approx توكن، والمتاح '
        '~${config.inputTokenBudget}).',
        hint: 'كبّر حجم السياق من الإعدادات، أو قسّم المحاضرة لجزئين.',
      );
    }

    final request = http.Request('POST', Uri.parse('${config.baseUrl}/api/generate'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': config.model,
        'system': StudyPrompt.system,
        'prompt': prompt,
        'stream': true,
        // التفكير بيبطّأ من غير فايدة هنا — المهمة اتباع قالب، مش استنتاج.
        // Thinking costs time without helping here: the task is following a
        // template, not reasoning.
        'think': false,
        // بنسيب الموديل محمّل عشان التلخيص اللي بعده يبدأ فورًا بدل تحميل تاني.
        // Keep the model resident so the next summary skips the reload.
        'keep_alive': '30m',
        'options': {
          'num_ctx': config.numCtx,
          // حرارة منخفضة: عايزين اتباع أمين للأسلوب، مش إبداع.
          // Low temperature: faithful style-following, not invention.
          'temperature': 0.4,
        },
      });

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e) {
      throw SummarizerException(
        'مش قادر أوصل لـ Ollama على ${config.baseUrl}.',
        hint: 'اتأكد إن Ollama شغال، وإن OLLAMA_ORIGINS متظبط يسمح للمتصفح. ($e)',
      );
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw SummarizerException(
        _loadFailure(body)
            // موديلات كتير على Ollama بكوانتيزيشن تجريبي مش بتتحمّل أصلاً،
            // والخطأ الخام مش بيقول للمستخدم إن الحل هو تغيير الموديل.
            // Plenty of Ollama models ship quantizations that simply fail to
            // load, and the raw error never tells the user to swap models.
            ? 'الموديل "${config.model}" مش قادر يشتغل.'
            : 'Ollama رجّع خطأ ${response.statusCode}.',
        hint: _loadFailure(body)
            ? 'جرّب موديل تاني من إعدادات التلخيص.\n$body'
            : (body.isEmpty ? null : body),
      );
    }

    // الرد NDJSON: كل سطر كائن لوحده فيه جزء من النص.
    // The response is NDJSON: one JSON object per line, each a text chunk.
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

      final piece = chunk['response'] as String?;
      if (piece != null && piece.isNotEmpty) yield piece;

      if (chunk['done'] == true) return;
    }
  }

  /// بيفرق بين "الموديل نفسه مش بيتحمّل" وبين أي خطأ تاني من الخادم.
  /// Tells "this model cannot load" apart from any other server error.
  static bool _loadFailure(String body) {
    final b = body.toLowerCase();
    return b.contains('overflow') ||
        b.contains('unable to load') ||
        b.contains('failed to load') ||
        b.contains('unsupported') ||
        b.contains('tensor');
  }

  @override
  Future<List<String>> listModels() async {
    final http.Response response;
    try {
      response = await _client
          .get(Uri.parse('${config.baseUrl}/api/tags'))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      throw SummarizerException(
        'مش قادر أوصل لـ Ollama على ${config.baseUrl}.',
        hint: 'شغّل Ollama واتأكد إن OLLAMA_ORIGINS بيسمح للمتصفح. ($e)',
      );
    }

    if (response.statusCode != 200) {
      throw SummarizerException('Ollama رجّع خطأ ${response.statusCode}.');
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return (body['models'] as List<dynamic>? ?? const [])
        .map((m) => (m as Map<String, dynamic>)['name'] as String? ?? '')
        .where((n) => n.isNotEmpty)
        .toList()
      ..sort();
  }
}
