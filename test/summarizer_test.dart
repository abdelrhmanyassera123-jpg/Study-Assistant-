import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_assistant/features/summarize/gemini_summarizer.dart';
import 'package:study_assistant/features/summarize/summarizer.dart';
import 'package:study_assistant/models/models.dart';

StyleSample sample(String body, {String? subjectId, String title = ''}) => StyleSample(
      id: 's',
      title: title,
      body: body,
      subjectId: subjectId,
      createdAt: DateTime.now(),
    );

const config = GeminiConfig(
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
  String errorBody = '{"error":"nope"}',
  String? answeredBy,
  Map<String, dynamic>? errorLine,
  bool splitAcrossPackets = false,
  void Function(http.BaseRequest req, Map<String, dynamic> body)? capture,
}) {
  return MockClient.streaming((request, bodyStream) async {
    if (capture != null) {
      final raw = await bodyStream.bytesToString();
      capture(request, jsonDecode(raw) as Map<String, dynamic>);
    }

    if (status != 200) {
      return http.StreamedResponse(Stream.value(utf8.encode(errorBody)), status);
    }

    final lines = <String>[
      if (answeredBy != null) jsonEncode({'model': answeredBy}),
      if (errorLine != null) jsonEncode(errorLine),
      for (final c in chunks) jsonEncode({'text': c}),
      jsonEncode({'done': true}),
    ];

    if (!splitAcrossPackets) {
      return http.StreamedResponse(
        Stream.fromIterable(lines.map((l) => utf8.encode('$l\n'))),
        200,
      );
    }

    // الشبكة مش بتحترم حدود السطور — بنقسّم في نص السطر عشان نتأكد إن التجميع
    // شغال حتى لو السطر اتقطع بين حزمتين.
    // Networks don't respect line boundaries, so split mid-line to prove the
    // decoder reassembles chunks correctly.
    final bytes = utf8.encode('${lines.join('\n')}\n');
    final third = bytes.length ~/ 3;
    return http.StreamedResponse(
      Stream.fromIterable([
        bytes.sublist(0, third),
        bytes.sublist(third, third * 2),
        bytes.sublist(third * 2),
      ]),
      200,
    );
  });
}

void main() {
  group('streaming', () {
    test('joins the chunks into the full summary', () async {
      final s = GeminiSummarizer(
        config,
        client: fakeFunction(['**الفكرة**\n', 'الجهد = ', 'التيار × المقاومة']),
      );

      final out =
          await s.summarize(lectureText: 'محاضرة', samples: [sample('مثال')]).join();

      expect(out, '**الفكرة**\nالجهد = التيار × المقاومة');
    });

    test('reassembles lines split across network packets', () async {
      final s = GeminiSummarizer(
        config,
        client: fakeFunction(['واحد ', 'اتنين ', 'تلاتة'], splitAcrossPackets: true),
      );

      final out = await s.summarize(lectureText: 'محاضرة', samples: const []).join();

      expect(out, 'واحد اتنين تلاتة');
    });

    test('stops at the done marker', () async {
      final s = GeminiSummarizer(config, client: fakeFunction(['أ', 'ب']));
      final pieces =
          await s.summarize(lectureText: 'x', samples: const []).toList();
      expect(pieces, ['أ', 'ب']);
    });

    test('surfaces an error line mid-stream', () {
      final s = GeminiSummarizer(
        config,
        client: fakeFunction(const [], errorLine: {'error': 'model unavailable'}),
      );

      expect(
        s.summarize(lectureText: 'x', samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });
  });

  group('request shape', () {
    test('sends the user token and never a provider key', () async {
      http.BaseRequest? seen;
      Map<String, dynamic>? body;
      final s = GeminiSummarizer(
        config,
        client: fakeFunction(['ok'], capture: (r, b) {
          seen = r;
          body = b;
        }),
      );

      await s.summarize(lectureText: 'محاضرة', samples: const []).join();

      expect(seen!.headers['Authorization'], 'Bearer user-jwt');
      expect(body!['action'], 'summarize');
      expect(body!['model'], 'gemini-test');
      expect(body!.containsKey('prompt'), isTrue);
      // مفتاح المزود لازم يفضل على السيرفر — عمره ما يظهر في طلب من المتصفح.
      // The provider key stays server-side; it must never ride a browser request.
      expect(body!.keys, isNot(contains('key')));
      expect(body!.keys, isNot(contains('apiKey')));
    });

    test('refuses a lecture that cannot fit instead of truncating it', () {
      // القص الصامت أخطر من الرفض: بيطلّع تلخيص واثق وناقص.
      // Silent truncation is worse than refusing: it yields a confident,
      // half-informed summary.
      final s = GeminiSummarizer(config, client: fakeFunction(['never reached']));

      expect(
        s.summarize(lectureText: 'ا' * 900000, samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });

    test('asks for automatic selection when no model is pinned', () async {
      // الموديل الفاضي مش خطأ: معناه سيب الخدمة تختار وتنتقل لما واحد يفشل.
      // An empty model isn't an error: it means let the service choose and move
      // on when one fails.
      Map<String, dynamic>? body;
      final s = GeminiSummarizer(
        const GeminiConfig(
          functionUrl: 'https://x/functions/v1/summarize',
          accessToken: 'jwt',
          anonKey: 'anon',
        ),
        client: fakeFunction(['ok'], capture: (_, b) => body = b),
      );

      await s.summarize(lectureText: 'x', samples: const []).join();

      expect(body!['model'], 'auto');
    });

    test('counts usage against the model that actually answered', () async {
      // في الوضع التلقائي الخدمة هي اللي بتختار، فالعدّاد لازم يمشي على اللي
      // ردّ مش على اللي طلبناه.
      // In auto mode the service chooses, so usage must follow the model that
      // answered rather than the one requested.
      final recorded = <String>[];
      final s = GeminiSummarizer(
        const GeminiConfig(
          functionUrl: 'https://x/functions/v1/summarize',
          accessToken: 'jwt',
          anonKey: 'anon',
        ),
        client: fakeFunction(['ok'], answeredBy: 'gemini-2.5-flash'),
        onRequest: recorded.add,
      );

      final out = await s.summarize(lectureText: 'x', samples: const []).join();

      expect(recorded, ['gemini-2.5-flash']);
      // سطر الموديل مش جزء من التلخيص.
      // The model line is not part of the summary.
      expect(out, 'ok');
    });

    test('refuses before calling anything when signed out', () {
      final s = GeminiSummarizer(
        const GeminiConfig(
          functionUrl: 'https://x/functions/v1/summarize',
          accessToken: '',
          anonKey: 'anon',
          model: 'gemini-test',
        ),
        client: fakeFunction(['never reached']),
      );

      expect(
        s.summarize(lectureText: 'x', samples: const []),
        emitsError(isA<SummarizerException>()),
      );
    });
  });

  group('error messages', () {
    Future<void> expectMessage(int status, Matcher matcher) async {
      final s = GeminiSummarizer(config, client: fakeFunction(const [], status: status));
      await expectLater(
        s.summarize(lectureText: 'x', samples: const []),
        emitsError(isA<SummarizerException>().having((e) => e.message, 'message', matcher)),
      );
    }

    // أكواد HTTP الخام ما بتقولش للمستخدم يعمل إيه — كل واحد بيتترجم لسبب وحل.
    // Raw HTTP codes tell the user nothing; each maps to a cause and a fix.
    test('404 names the unavailable model', () => expectMessage(404, contains('gemini-test')));
    test('429 explains the quota', () => expectMessage(429, contains('حصتك')));
    test('503 explains the overload', () => expectMessage(503, contains('مزحوم')));
    test('401 suggests signing in again', () => expectMessage(401, contains('سجّل خروج')));
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
  });
}
