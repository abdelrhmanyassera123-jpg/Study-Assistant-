import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/summarize/audio_clip.dart';
import 'package:study_assistant/features/summarize/summarizer.dart';

AudioClip clip(List<int> partSizes, {String mime = 'audio/webm'}) => AudioClip(
      name: 'تسجيل 10:30',
      mimeType: mime,
      parts: [for (final size in partSizes) Uint8List(size)],
      duration: const Duration(minutes: 22),
    );

void main() {
  group('parts', () {
    test('a single part keeps the recording name as it is', () {
      final files = clip([1000]).files;

      expect(files, hasLength(1));
      expect(files.single.name, 'تسجيل 10:30');
      expect(files.single.mimeType, 'audio/webm');
    });

    // التفريغ بيتم مقطع مقطع، والترقيم هو اللي بيخلي رسالة الخطأ تقول أنهي
    // جزء وقع بدل ما تقول "التسجيل".
    // Transcription runs part by part, and the numbering is what lets an error
    // name the part that failed instead of just "the recording".
    test('several parts are numbered in order', () {
      final files = clip([1000, 1000, 1000]).files;

      expect(files.map((f) => f.name), [
        'تسجيل 10:30 (1)',
        'تسجيل 10:30 (2)',
        'تسجيل 10:30 (3)',
      ]);
    });

    test('size counts every part, not just the first', () {
      expect(clip([1024 * 1024, 1024 * 1024]).megabytes, 2);
    });

    // التسجيل من التطبيق بيتقسّم وهو ماشي فمفيش مقطع بيعدي السقف؛ الملف
    // المرفوع هو اللي ممكن يعدّيه، والفرق ده هو اللي بيحدد الرسالة.
    // A recording made here splits as it goes so no part can exceed the ceiling;
    // an uploaded file can, and that difference decides the message.
    test('an oversized part is spotted before anything is sent', () {
      expect(clip([1000, 1000]).hasOversizedPart, isFalse);
      expect(clip([LectureFile.maxBytes + 1]).hasOversizedPart, isTrue);
    });

    test('an empty recording is empty, not a zero-byte part', () {
      expect(clip(const []).isEmpty, isTrue);
      expect(clip([10]).isEmpty, isFalse);
    });
  });

  group('transcript', () {
    test('is kept on the clip so a part is never transcribed twice', () {
      final original = clip([100]);
      expect(original.transcript, isNull);

      final done = original.withTranscript('الجهد = التيار × المقاومة');

      expect(done.transcript, 'الجهد = التيار × المقاومة');
      expect(done.parts, same(original.parts));
      expect(done.duration, original.duration);
    });
  });

  group('uploaded files', () {
    test('phone recordings are recognised as audio', () {
      expect(isAudioFile('محاضرة.m4a'), isTrue);
      expect(isAudioFile('lecture.MP3'), isTrue);
      expect(isAudioFile('lecture.ogg'), isTrue);
    });

    test('lecture documents are not', () {
      expect(isAudioFile('lecture.pdf'), isFalse);
      expect(isAudioFile('slides.pptx'), isFalse);
    });

    // بعض المتصفحات بتسيب نوع الملف فاضي، والموديل بيرفض من غير نوع صحيح.
    // Some browsers leave the file's type blank, and the model refuses without
    // a correct one.
    test('the type is inferred from the extension', () {
      expect(audioMimeFor('محاضرة.m4a'), 'audio/mp4');
      expect(audioMimeFor('rec.MP3'), 'audio/mp3');
      expect(audioMimeFor('rec.opus'), 'audio/ogg');
      expect(audioMimeFor('rec.wav'), 'audio/wav');
    });
  });
}
