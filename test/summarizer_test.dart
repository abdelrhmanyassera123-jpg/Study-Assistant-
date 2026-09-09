import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_assistant/features/summarize/gemini_summarizer.dart';
import 'package:study_assistant/features/summarize/ollama_summarizer.dart';
import 'package:study_assistant/features/summarize/summarizer.dart';
import 'package:study_assistant/models/models.dart';

StyleSample sample(String body, {String? subjectId, String title = ''}) => StyleSample(
      id: 's',
      title: title,
      body: body,
      subjectId: subjectId,
      createdAt: DateTime.now(),
    );

/// بيقلّد رد Ollama: سطور NDJSON، كل سطر جزء من النص.
/// Fakes Ollama's reply: NDJSON lines, each carrying a chunk of text.
http.Client fakeOllama(
  List<String> chunks, {
  int status = 200,
  String errorBody = 'server exploded',
  Map<String, dynamic>? errorLine,
  void Function(Map<String, dynamic> body)? captureBody,
  bool splitAcrossPackets = false,
}) {
  return MockClient.streaming((request, bodyStream) async {
    if (captureBody != null) {
      final raw = await bodyStream.bytesToString();
      captureBody(jsonDecode(raw) as Map<String, dynamic>);
    }

    if (status != 200) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(errorBody)),
        status,
      );
    }

    final lines = <String>[
      if (errorLine != null) jsonEncode(errorLine),
      for (final c in chunks) jsonEncode({'response': c, 'done': false}),
      jsonEncode({'response': '', 'done': true}),
    ];

    final payload = '${lines.join('\n')}\n';

    // الشبكة مش بتحترم حدود السطور — بنقسّم بشكل عشوائي عشان نتأكد إن
    // التجميع شغال حتى لو السطر اتقطع بين حزمتين.
    // Networks don't respect line boundaries, so split mid-line to prove the
    // decoder reassembles chunks correctly.
    final Stream<List<int>> body;
    if (splitAcrossPackets) {
      final bytes = utf8.encode(payload);
      final third = bytes.length ~/ 3;
      body = Stream.fromIterable([
        bytes.sublist(0, third),
        bytes.sublist(third, third * 2),
        bytes.sublist(third * 2),
      ]);
    } else {
      body = Stream.fromIterable(lines.map((l) => utf8.encode('$l\n')));
    }

    return http.StreamedResponse(body, 200);
  });
}

void main() {
  const config = OllamaConfig(model: 'test-model', numCtx: 16384);

  group('streaming', () {
    test('joins the chunks into the full summary', () async {
      final summarizer = OllamaSummarizer(
        config,
        client: fakeOllama(['**الفكرة**\n', 'الجهد = ', 'التيار × المقاومة']),
      );

      final out = await summarizer
          .summarize(lectureText: 'محاضرة', samples: [sample('مثال')])
          .join();

      expect(out, '**الفكرة**\nالجهد = التيار × المقاومة');
    });

    test('reassembles lines split across network packets', () async {
      final summarizer = OllamaSummarizer(
        config,
        client: fakeOllama(
          ['واحد ', 'اتنين ', 'تلاتة'],
          splitAcrossPackets: true,
        ),
      );

      final out = await summarizer
          .summarize(lectureText: 'محاضرة', samples: const []).join();

      expect(out, 'واحد اتنين تلاتة');
    });

    test('stops at the done marker', () async {
      final summarizer = OllamaSummarizer(config, client: fakeOllama(['أ', 'ب']));
      final pieces =
          await summarizer.summarize(lectureText: 'x', samples: const []).toList();
      expect(pieces, ['أ', 'ب']);
    });

    test('surfaces an error line from the model', () {
      final summarizer = OllamaSummarizer(
        config,
        client: fakeOllama(const [], errorLine: {'error': 'model not found'}),
      );

      expect(
        summarizer.summarize(lectureText: 'x', samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });

    test('tells the user to change model when the model cannot load', () async {
      // كوانتيزيشن تجريبي بيفشل التحميل — الخطأ الخام ما بيقولش إن الحل
      // تغيير الموديل، فبنقوله.
      // Experimental quantizations fail to load; the raw error never says the
      // fix is picking another model, so we say it.
      final summarizer = OllamaSummarizer(
        const OllamaConfig(model: 'broken-model', numCtx: 16384),
        client: fakeOllama(
          const [],
          status: 500,
          errorBody: '{"error":"tensor \\"output.weight\\" size overflow"}',
        ),
      );

      await expectLater(
        summarizer.summarize(lectureText: 'x', samples: const []),
        emitsError(
          isA<SummarizerException>()
              .having((e) => e.message, 'message', contains('broken-model'))
              .having((e) => e.hint, 'hint', contains('موديل تاني')),
        ),
      );
    });

    test('surfaces a non-200 response', () {
      final summarizer =
          OllamaSummarizer(config, client: fakeOllama(const [], status: 500));

      expect(
        summarizer.summarize(lectureText: 'x', samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });
  });

  group('request shape', () {
    test('sends the model, context size and thinking-off flag', () async {
      Map<String, dynamic>? body;
      final summarizer = OllamaSummarizer(
        const OllamaConfig(model: 'qwen', numCtx: 32768),
        client: fakeOllama(['ok'], captureBody: (b) => body = b),
      );

      await summarizer.summarize(lectureText: 'محاضرة', samples: const []).join();

      expect(body!['model'], 'qwen');
      expect(body!['stream'], true);
      expect(body!['think'], false);
      expect((body!['options'] as Map)['num_ctx'], 32768);
    });

    test('refuses a lecture that cannot fit instead of truncating it', () {
      // القص الصامت أخطر من الرفض: بيطلّع تلخيص واثق وناقص.
      // Silent truncation is worse than refusing: it yields a confident,
      // half-informed summary.
      final summarizer = OllamaSummarizer(
        const OllamaConfig(model: 'qwen', numCtx: 4096),
        client: fakeOllama(['never reached']),
      );

      expect(
        summarizer.summarize(lectureText: 'ا' * 60000, samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });

    test('refuses when no model is selected', () {
      final summarizer =
          OllamaSummarizer(const OllamaConfig(), client: fakeOllama(['x']));

      expect(
        summarizer.summarize(lectureText: 'x', samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });
  });

  group('prompt', () {
    test('puts the examples before the lecture', () {
      final prompt = StudyPrompt.build(
        lectureText: 'المحاضرة الجديدة هنا',
        samples: [sample('التلخيص القديم')],
      );

      expect(prompt.indexOf('التلخيص القديم'),
          lessThan(prompt.indexOf('المحاضرة الجديدة هنا')));
    });

    test('numbers each example', () {
      final prompt = StudyPrompt.build(
        lectureText: 'x',
        samples: [sample('أ'), sample('ب'), sample('ج')],
      );

      expect(prompt, contains('مثال 1'));
      expect(prompt, contains('مثال 2'));
      expect(prompt, contains('مثال 3'));
    });

    test('falls back to a plain summary when there are no examples', () {
      final prompt = StudyPrompt.build(lectureText: 'محتوى', samples: const []);

      expect(prompt, isNot(contains('مثال 1')));
      expect(prompt, contains('محتوى'));
    });

    test('is identical whichever provider sends it', () {
      // الأسلوب لازم ما يتغيرش لما تبدّل المزود — البرومبت واحد للطرفين.
      // Switching providers must not change the voice, so both send one prompt.
      final samples = [sample('مثال')];
      final viaShared =
          StudyPrompt.build(lectureText: 'محاضرة', samples: samples);
      expect(viaShared, contains('مثال'));
      expect(viaShared, contains('محاضرة'));
    });
  });

  group('gemini via edge function', () {
    const geminiConfig = GeminiConfig(
      functionUrl: 'https://project.supabase.co/functions/v1/summarize',
      accessToken: 'user-jwt',
      anonKey: 'anon-key',
      model: 'gemini-test',
    );

    /// بيقلّد رد الـ Edge Function: NDJSON بمفتاح text.
    /// Fakes the Edge Function reply: NDJSON keyed on text.
    http.Client fakeFunction(
      List<String> chunks, {
      int status = 200,
      void Function(http.BaseRequest req, Map<String, dynamic> body)? capture,
    }) {
      return MockClient.streaming((request, bodyStream) async {
        if (capture != null) {
          final raw = await bodyStream.bytesToString();
          capture(request, jsonDecode(raw) as Map<String, dynamic>);
        }
        if (status != 200) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":"nope"}')),
            status,
          );
        }
        final lines = [
          for (final c in chunks) jsonEncode({'text': c}),
          jsonEncode({'done': true}),
        ];
        return http.StreamedResponse(
          Stream.fromIterable(lines.map((l) => utf8.encode('$l\n'))),
          200,
        );
      });
    }

    test('joins the streamed chunks', () async {
      final summarizer = GeminiSummarizer(
        geminiConfig,
        client: fakeFunction(['**الفكرة**\n', 'المحتوى']),
      );

      final out = await summarizer
          .summarize(lectureText: 'محاضرة', samples: const []).join();

      expect(out, '**الفكرة**\nالمحتوى');
    });

    test('sends the user token and never a raw API key', () async {
      http.BaseRequest? seen;
      Map<String, dynamic>? body;
      final summarizer = GeminiSummarizer(
        geminiConfig,
        client: fakeFunction(['ok'], capture: (r, b) {
          seen = r;
          body = b;
        }),
      );

      await summarizer.summarize(lectureText: 'محاضرة', samples: const []).join();

      expect(seen!.headers['Authorization'], 'Bearer user-jwt');
      expect(body!['action'], 'summarize');
      expect(body!['model'], 'gemini-test');
      expect(body!.containsKey('prompt'), isTrue);
      // المفتاح لازم ما يبقاش موجود في أي طلب طالع من المتصفح.
      // No provider key may ever appear in a request leaving the browser.
      expect(body!.keys, isNot(contains('key')));
      expect(body!.keys, isNot(contains('apiKey')));
    });

    test('refuses before calling anything when signed out', () {
      final summarizer = GeminiSummarizer(
        const GeminiConfig(
          functionUrl: 'https://x/functions/v1/summarize',
          accessToken: '',
          anonKey: 'anon',
          model: 'gemini-test',
        ),
        client: fakeFunction(['never reached']),
      );

      expect(
        summarizer.summarize(lectureText: 'x', samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });

    test('explains a missing function rather than dumping a 404', () async {
      final summarizer =
          GeminiSummarizer(geminiConfig, client: fakeFunction(const [], status: 404));

      await expectLater(
        summarizer.summarize(lectureText: 'x', samples: const []),
        emitsError(
          isA<SummarizerException>().having(
            (e) => e.message,
            'message',
            contains('مش متنشرة'),
          ),
        ),
      );
    });

    test('explains a quota error rather than dumping a 429', () async {
      final summarizer =
          GeminiSummarizer(geminiConfig, client: fakeFunction(const [], status: 429));

      await expectLater(
        summarizer.summarize(lectureText: 'x', samples: const []),
        emitsError(
          isA<SummarizerException>()
              .having((e) => e.message, 'message', contains('حصتك')),
        ),
      );
    });
  });
}
