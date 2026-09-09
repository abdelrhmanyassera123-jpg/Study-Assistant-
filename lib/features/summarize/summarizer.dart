import '../../models/models.dart';

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

/// مين بيلخص: موديل محلي على جهازك، ولا Gemini من ورا Edge Function.
/// Who does the summarizing: a local model, or Gemini behind an Edge Function.
enum SummarizerProvider {
  /// مجاني وخاص تمامًا، بس محتاج جهازك يكون شغال.
  /// Free and fully private, but only while your machine is on.
  ollama,

  /// بيشتغل من أي جهاز. المفتاح بيقعد على السيرفر مش في المتصفح.
  /// Works from anywhere. The key lives on the server, never in the browser.
  gemini,
}

/// الواجهة اللي كل مزود بينفذها — الصفحة مش بتعرف مين اللي بيرد.
/// The contract every provider implements; the page doesn't know which one answers.
abstract class Summarizer {
  /// بيرجّع التلخيص قطعة قطعة وهو بيتولد.
  /// Yields the summary in chunks as it is produced.
  Stream<String> summarize({
    required String lectureText,
    required List<StyleSample> samples,
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
    required String lectureText,
    required List<StyleSample> samples,
  }) {
    final buffer = StringBuffer();

    if (samples.isEmpty) {
      buffer.writeln('### المحاضرة:');
      buffer.writeln();
      buffer.writeln(lectureText.trim());
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
    buffer.writeln(lectureText.trim());
    buffer.writeln();
    buffer.writeln('لخّص المحاضرة الجديدة دي بنفس أسلوبي وشكلي بالظبط.');

    return buffer.toString();
  }

  /// تقدير تقريبي لعدد التوكنز — العربي حوالي 2.6 حرف للتوكن.
  /// Rough token estimate; Arabic runs about 2.6 characters per token.
  static int approxTokens(String text) => (text.length / 2.6).round();
}
