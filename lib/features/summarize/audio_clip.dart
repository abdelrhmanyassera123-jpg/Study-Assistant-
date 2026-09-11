import 'dart:typed_data';

import 'summarizer.dart';

/// تسجيل صوتي مقسّم لمقاطع.
/// A recording, split into parts.
///
/// المحاضرة ساعة أو اتنين، والطلب الواحد للموديل محدود بحجم الذاكرة في الـ Edge
/// Function. فبدل ما نحط سقف على وقت التسجيل، بنقسمه لمقاطع كل واحد يعدي
/// لوحده، وبنلزق تفريغهم ورا بعض.
/// A lecture runs an hour or two, and one request to the model is bounded by
/// the Edge Function's memory. So instead of capping how long you may record,
/// the recording is split into parts that each fit on their own, and their
/// transcripts are joined back together.
class AudioClip {
  const AudioClip({
    required this.name,
    required this.mimeType,
    required this.parts,
    required this.duration,
    this.transcript,
  });

  final String name;
  final String mimeType;
  final List<Uint8List> parts;
  final Duration duration;

  /// النص بعد التفريغ — بيتحسب مرة واحدة ويتخزن، التفريغ غالي.
  /// The text after transcription: computed once and kept, since transcribing
  /// costs a model call.
  final String? transcript;

  AudioClip withTranscript(String text) => AudioClip(
        name: name,
        mimeType: mimeType,
        parts: parts,
        duration: duration,
        transcript: text,
      );

  int get bytes => parts.fold(0, (sum, p) => sum + p.length);
  double get megabytes => bytes / (1024 * 1024);
  bool get isEmpty => parts.isEmpty;

  /// المقاطع كملفات جاهزة تتبعت واحد ورا التاني.
  /// The parts as files, ready to be sent one after another.
  List<LectureFile> get files => [
        for (var i = 0; i < parts.length; i++)
          LectureFile(
            name: parts.length == 1 ? name : '$name (${i + 1})',
            mimeType: mimeType,
            bytes: parts[i],
          ),
      ];

  /// أي مقطع أكبر من الحد ما ينفعش يتبعت — بيحصل مع ملف مرفوع مش مع تسجيلنا.
  /// A part over the ceiling cannot be sent; this happens with an uploaded
  /// file, never with our own recording.
  bool get hasOversizedPart => parts.any((p) => p.length > LectureFile.maxBytes);
}

/// الصيغ اللي بنقبلها كملف صوت مرفوع.
/// The audio formats accepted as an upload.
///
/// اتجربوا كلهم على Gemini بنداء حقيقي: `webm` و`mp4`/`m4a` (تسجيلات الموبايل)
/// و`aac` بيعدوا، زي الصيغ الموثّقة عندهم.
/// All of these were tried against Gemini with a real call: `webm`, `mp4`/`m4a`
/// (what phones record) and `aac` pass, alongside their documented formats.
const supportedAudioExtensions = [
  'm4a',
  'mp3',
  'wav',
  'aac',
  'ogg',
  'opus',
  'oga',
  'flac',
  'webm',
  'mp4',
  'aiff',
];

/// بيستنتج نوع الصوت من الامتداد لما المتصفح يسيبه فاضي.
/// Infers the audio type from the extension when the browser leaves it blank.
String audioMimeFor(String fileName) {
  return switch (fileName.split('.').last.toLowerCase()) {
    'm4a' || 'mp4' => 'audio/mp4',
    'mp3' => 'audio/mp3',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    'ogg' || 'oga' || 'opus' => 'audio/ogg',
    'flac' => 'audio/flac',
    'webm' => 'audio/webm',
    'aiff' => 'audio/aiff',
    _ => 'audio/mpeg',
  };
}

bool isAudioFile(String fileName) =>
    supportedAudioExtensions.contains(fileName.split('.').last.toLowerCase());
