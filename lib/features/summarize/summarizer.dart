import 'dart:typed_data';

import '../../models/models.dart';
import 'style_profile.dart';

/// ملف محاضرة بيتبعت للموديل زي ما هو بدل ما نستخرج نصه محليًا.
/// A lecture file sent to the model as-is instead of extracting text locally.
///
/// الـ PDF مش زي pptx/docx: مش أرشيف XML نقدر نفكه في المتصفح، وكتير منها
/// مسكون (صور). Gemini بيقرا الـ PDF بنفسه — نص ومسكون — فبنبعتهوله كامل.
/// PDFs are unlike pptx/docx: not an XML archive we can unzip in the browser,
/// and many are scanned images. Gemini reads PDFs directly — text or scanned —
/// so we hand the whole file over.
class LectureFile {
  const LectureFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  /// الحد الأقصى للملف. الترميز base64 بيكبّر الحجم ~33%، وحد الطلب عند
  /// جوجل حوالي 20 ميجا.
  /// Size ceiling: base64 inflates by ~33% and Google's request cap is ~20 MB.
  static const maxBytes = 12 * 1024 * 1024;

  bool get isTooBig => bytes.length > maxBytes;
  double get megabytes => bytes.length / (1024 * 1024);
}

/// خطأ بلغة المستخدم — الواجهة بتعرضه زي ما هو.
/// A user-facing failure; the UI shows [message] as-is.
class SummarizerException implements Exception {
  const SummarizerException(this.message, {this.hint});

  final String message;

  /// اقتراح عملي للحل، لو فيه.
  /// A concrete next step, when there is one.
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}

/// الواجهة اللي كل مزود بينفذها — الصفحة مش بتعرف مين اللي بيرد.
/// The contract every provider implements; the page doesn't know which one answers.
abstract class Summarizer {
  /// بيرجّع التلخيص قطعة قطعة وهو بيتولد.
  /// Yields the summary in chunks as it is produced.
  /// [lectureText] للنص الملزوق أو المستخرج، و[file] للملفات اللي الموديل
  /// بيقراها بنفسه (PDF). واحد منهم لازم يكون موجود.
  /// [lectureText] carries pasted or extracted text; [file] carries files the
  /// model reads itself (PDF). At least one must be present.
  Stream<String> summarize({
    String lectureText = '',
    LectureFile? file,
    required List<StyleSample> samples,
  });

  /// بيحلل صور تلخيصات المستخدم ويرجّع وصف شكل صفحته.
  /// Reads photos of the user's summaries and returns their page layout.
  Future<StyleProfile> analyzeStyle(List<LectureFile> images);

  /// بيلخص ويرجّع بلوكات جاهزة للرسم بدل نص عادي.
  /// Summarizes into drawable blocks instead of prose.
  Future<SummaryPage> summarizeAsPage({
    String lectureText,
    LectureFile? file,
    required List<StyleSample> samples,
    required StyleProfile profile,
  });

  /// الموديلات المتاحة — بتستخدم كمان كفحص للاتصال.
  /// Available models; doubles as the connectivity check.
  Future<List<String>> listModels();
}

/// بناء البرومبت — مشترك بين كل المزودين عشان الأسلوب ما يختلفش لما تبدّل.
/// Prompt construction, shared across providers so switching one doesn't
/// silently change how your summaries come out.
class StudyPrompt {
  const StudyPrompt._();

  static const system = '''
أنت بتلخص محاضرات دراسية بأسلوب طالب معيّن بالظبط.

هتشوف أمثلة من تلخيصات الطالب نفسه، وبعدين محاضرة جديدة.
شغلك إنك تلخص المحاضرة الجديدة بنفس الشكل تمامًا:

- نفس الأقسام وبنفس الترتيب اللي في الأمثلة. متزودش قسم مش موجود عندهم، ومتشيلش قسم موجود.
- نفس طريقة التنسيق: العناوين، التنقيط، إيه اللي بيتعلّم بخط عريض.
- نفس النبرة واللهجة. لو الطالب بيكتب بالعامية، اكتب بالعامية. لو بيكتب بالفصحى، التزم بالفصحى.
- نفس مستوى التفصيل والطول التقريبي.

قواعد مهمة:
- المحتوى كله لازم يكون من المحاضرة المعطاة. متضيفش معلومة من عندك ومتخترعش أمثلة.
- لو المحاضرة مفيهاش حاجة تحط في قسم معين، سيبه فاضي أو شيله بدل ما تخترع.
- اكتب بالعربي.
- ابدأ بالتلخيص على طول. متكتبش مقدمة زي "إليك التلخيص" ولا تعليق في الآخر.
''';

  static String build({
    String lectureText = '',
    bool hasFile = false,
    required List<StyleSample> samples,
  }) {
    final buffer = StringBuffer();
    // لما المحاضرة ملف مرفق، الموديل بيقراه بنفسه فبنشاور عليه بدل ما نلزق نص.
    // With an attached file the model reads it directly, so we point at it
    // instead of pasting text.
    final lectureBody = hasFile ? '(المحاضرة في الملف المرفق)' : lectureText.trim();

    if (samples.isEmpty) {
      buffer.writeln('### المحاضرة:');
      buffer.writeln();
      buffer.writeln(lectureBody);
      buffer.writeln();
      buffer.writeln('لخّص المحاضرة دي تلخيص مذاكرة منظم بالعربي.');
      return buffer.toString();
    }

    buffer.writeln('### دي أمثلة من تلخيصاتي أنا — ادرس شكلها وأسلوبها:');
    buffer.writeln();
    for (var i = 0; i < samples.length; i++) {
      buffer.writeln('--- مثال ${i + 1} ---');
      if (samples[i].title.trim().isNotEmpty) {
        buffer.writeln('(${samples[i].title.trim()})');
      }
      buffer.writeln(samples[i].body.trim());
      buffer.writeln();
    }

    buffer.writeln('### المحاضرة الجديدة:');
    buffer.writeln();
    buffer.writeln(lectureBody);
    buffer.writeln();
    buffer.writeln('لخّص المحاضرة الجديدة دي بنفس أسلوبي وشكلي بالظبط.');

    return buffer.toString();
  }

  /// تقدير تقريبي لعدد التوكنز — العربي حوالي 2.6 حرف للتوكن.
  /// Rough token estimate; Arabic runs about 2.6 characters per token.
  static int approxTokens(String text) => (text.length / 2.6).round();
}
