import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
  void Function(http.BaseRequest req, Uint8List bytes)? onUpload,
  Map<String, dynamic>? uploadReply,
  int uploadStatus = 200,
}) {
  return MockClient.streaming((request, bodyStream) async {
    // الرفع بيتحدد من الرابط، وجسمه بايتات مش JSON.
    // An upload is named in the URL and its body is bytes, not JSON.
    if (request.url.queryParameters['action'] == 'upload') {
      final bytes = await bodyStream.toBytes();
      onUpload?.call(request, bytes);
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(uploadReply ??
            {
              'uri': 'https://generativelanguage.googleapis.com/v1beta/files/x1',
              'name': 'files/x1',
              'mime_type': 'audio/mp4',
              'state': 'ACTIVE',
            }))),
        uploadStatus,
      );
    }

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

/// بيقلّد رد نداءات JSON (كروت/امتحان/جدول): NDJSON ببينج اختياري وسطر أخير.
/// Fakes a structured-json reply (cards/exam/schedule): NDJSON with optional
/// heartbeats and one final line.
http.Client fakeJson({
  int status = 200,
  String errorBody = '{"error":"nope"}',
  int pendingLines = 0,
  Map<String, dynamic>? finalLine,
}) {
  return MockClient.streaming((request, bodyStream) async {
    if (status != 200) {
      return http.StreamedResponse(Stream.value(utf8.encode(errorBody)), status);
    }
    final lines = <String>[
      for (var i = 0; i < pendingLines; i++) jsonEncode({'pending': true}),
      jsonEncode(finalLine ?? {'result': <String, dynamic>{}}),
    ];
    return http.StreamedResponse(
      Stream.fromIterable(lines.map((l) => utf8.encode('$l\n'))),
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

  group('transcription', () {
    test('sends the audio with the transcribing instructions, not the style ones',
        () async {
      Map<String, dynamic>? body;
      final s = GeminiSummarizer(
        config,
        client: fakeFunction(['السلام عليكم، ', 'نبدأ المحاضرة'],
            capture: (_, b) => body = b),
      );

      final text = await s.transcribe(LectureFile(
        name: 'تسجيل (1)',
        mimeType: 'audio/webm',
        bytes: Uint8List.fromList([1, 2, 3]),
      ));

      expect(text, 'السلام عليكم، نبدأ المحاضرة');
      expect(body!['system'], StudyPrompt.transcribeSystem);
      expect(body!['system'], isNot(StudyPrompt.system));
      expect(body!['system'], isNot(contains('بأسلوب طالب')));
      expect((body!['files'] as List).single['mime_type'], 'audio/webm');
    });

    // التفريغ نقل مش صياغة: أي حرارة فوق الصفر بتخلي الموديل "يحسّن" الكلام
    // اللي مش سامعه كويس.
    // Transcription copies rather than phrases: any temperature above zero lets
    // the model "improve" what it could not hear.
    test('asks for zero temperature', () async {
      Map<String, dynamic>? body;
      final s = GeminiSummarizer(
        config,
        client: fakeFunction(['x'], capture: (_, b) => body = b),
      );

      await s.transcribe(LectureFile(
        name: 'a',
        mimeType: 'audio/webm',
        bytes: Uint8List(3),
      ));

      expect(body!['temperature'], 0);
    });

    // المحاضرة الساعتين مش بتعدي جوه الطلب مهما عملنا. بترفع مرة، وبعدين
    // التفريغ بيشاور على رابطها — من غير ده الملف الكبير كان بيترفض خالص.
    // A two-hour lecture cannot ride inside the request whatever we do. It
    // uploads once and the transcription points at its URI; without this the
    // large file was simply refused.
    test('a large recording is uploaded once, then referenced by URI', () async {
      http.BaseRequest? uploadRequest;
      Uint8List? uploadedBytes;
      Map<String, dynamic>? body;

      final s = GeminiSummarizer(
        config,
        client: fakeFunction(
          ['اللي اتقال'],
          capture: (_, b) => body = b,
          onUpload: (r, bytes) {
            uploadRequest = r;
            uploadedBytes = bytes;
          },
        ),
      );

      final audio = LectureFile(
        name: 'محاضرة الفيزياء.m4a',
        mimeType: 'audio/mp4',
        bytes: Uint8List(LectureFile.inlineBytes + 1),
      );

      final text = await s.transcribe(audio);

      expect(text, 'اللي اتقال');
      expect(uploadedBytes, hasLength(audio.bytes.length));
      expect(uploadRequest!.headers['x-file-size'], '${audio.bytes.length}');
      expect(uploadRequest!.headers['x-file-mime'], 'audio/mp4');

      final part = (body!['files'] as List).single as Map<String, dynamic>;
      expect(part['file_uri'], contains('/files/x1'));
      expect(part.containsKey('data'), isFalse);
    });

    // الرحلة الزيادة لجوجل مش هتفيد في مقطع صغير، والتسجيل من التطبيق كله
    // مقاطع صغيرة.
    // The extra trip to Google buys nothing for a small part, and a recording
    // made in the app is all small parts.
    test('a small part still travels inside the request', () async {
      var uploads = 0;
      Map<String, dynamic>? body;

      final s = GeminiSummarizer(
        config,
        client: fakeFunction(
          ['x'],
          capture: (_, b) => body = b,
          onUpload: (_, _) => uploads++,
        ),
      );

      await s.transcribe(LectureFile(
        name: 'مقطع',
        mimeType: 'audio/webm',
        bytes: Uint8List(200 * 1024),
      ));

      expect(uploads, 0);
      final part = (body!['files'] as List).single as Map<String, dynamic>;
      expect(part['data'], isNotNull);
      expect(part.containsKey('file_uri'), isFalse);
    });

    test('a failed upload says the file could not be read', () async {
      final s = GeminiSummarizer(
        config,
        client: fakeFunction(
          const ['x'],
          uploadReply: {
            'uri': 'https://generativelanguage.googleapis.com/v1beta/files/x1',
            'name': 'files/x1',
            'state': 'FAILED',
          },
        ),
      );

      await expectLater(
        s.transcribe(LectureFile(
          name: 'broken.m4a',
          mimeType: 'audio/mp4',
          bytes: Uint8List(LectureFile.inlineBytes + 1),
        )),
        throwsA(isA<SummarizerException>()
            .having((e) => e.message, 'message', contains('مش قادرة تقراه'))),
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

    // السلايدات والتسجيل مصدرين لنفس المحاضرة. لو النص اتشال لما يبقى في ملف،
    // شرح المحاضر كله بيضيع والتلخيص بيطلع من العناوين بس.
    // Slides and a recording are two sources for one lecture. Dropping the text
    // whenever a file is present throws away everything the lecturer said and
    // leaves a summary built from headings.
    test('keeps the transcript when a file is attached too', () {
      final prompt = StudyPrompt.build(
        lectureText: 'المحاضر قال إن الجهد بيتقاس بالفولت',
        hasFile: true,
        samples: const [],
      );

      expect(prompt, contains('الملف المرفق'));
      expect(prompt, contains('المحاضر قال إن الجهد بيتقاس بالفولت'));
    });

    test('points at the file alone when there is no text', () {
      final prompt =
          StudyPrompt.build(lectureText: '', hasFile: true, samples: const []);

      expect(prompt, contains('(المحاضرة في الملف المرفق)'));
    });

    test('falls back to a plain summary when there are no examples', () {
      final prompt = StudyPrompt.build(lectureText: 'محتوى', samples: const []);

      expect(prompt, isNot(contains('مثال 1')));
      expect(prompt, contains('محتوى'));
    });
  });

  group('structured json calls', () {
    // نداء JSON (زي الجدول والكروت) بيوصل NDJSON دلوقتي بدل رد واحد، عشان
    // الاتصال ما يتقفلش وهو مستني رد Gemini الطويل على مستند كذا صفحة.
    // A JSON call (like the schedule or cards) now arrives as NDJSON instead
    // of one reply, so the connection stays open while a multi-page document
    // keeps Gemini busy.
    test('skips heartbeat lines and reads the final result', () async {
      final s = GeminiSummarizer(
        config,
        client: fakeJson(
          pendingLines: 2,
          finalLine: {
            'model': 'gemini-2.5-flash',
            'result': {
              'entries': [
                {'title': 'فيزياء', 'day': 'الأحد', 'start': '10:00', 'end': '12:00'},
              ],
            },
          },
        ),
      );

      final schedule = await s.parseSchedule(text: 'جدول');
      expect(schedule.entries, hasLength(1));
      expect(schedule.entries.first.title, 'فيزياء');
    });

    test('an error line carrying a status maps to the same message an HTTP status would',
        () async {
      final s = GeminiSummarizer(
        config,
        client: fakeJson(
          finalLine: {
            'error': 'Gemini returned 429',
            'detail': 'limit: 20',
            'status': 429,
          },
        ),
      );

      await expectLater(
        s.parseSchedule(text: 'جدول'),
        throwsA(isA<SummarizerException>()
            .having((e) => e.message, 'message', contains('حصتك'))),
      );
    });

    test('an HTTP-level failure before the stream opens still surfaces normally',
        () async {
      final s = GeminiSummarizer(config, client: fakeJson(status: 503));

      await expectLater(
        s.parseSchedule(text: 'جدول'),
        throwsA(isA<SummarizerException>()
            .having((e) => e.message, 'message', contains('مزحوم'))),
      );
    });
  });
}
