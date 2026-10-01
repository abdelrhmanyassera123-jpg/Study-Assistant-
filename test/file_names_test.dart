import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/core/file_names.dart';

void main() {
  test('a name without an extension gets one from its type', () {
    expect(withExtension('audio-20261001', 'audio/x-m4a'), 'audio-20261001.m4a');
    expect(withExtension('IMG_1', 'image/jpeg'), 'IMG_1.jpg');
    expect(withExtension('voice', 'audio/ogg; codecs=opus'), 'voice.ogg');
  });

  test('a name that already has an extension is left alone', () {
    expect(withExtension('PTT-20261001-WA0003.opus', 'audio/ogg'), 'PTT-20261001-WA0003.opus');
    expect(withExtension('lecture 3.pdf', 'application/octet-stream'), 'lecture 3.pdf');
  });

  test('an unknown type keeps the name as it is', () {
    expect(withExtension('archive', 'application/zip'), 'archive');
  });
}
