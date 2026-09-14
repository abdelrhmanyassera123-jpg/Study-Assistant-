import 'dart:typed_data';

import '../../models/models.dart';
import '../study_ai/study_ai.dart';
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

  /// فوق الحد ده الملف بيترفع لوحده بدل ما يتبعت جوه الطلب.
  /// Past this the file is uploaded on its own instead of riding inside the
  /// request.
  ///
  /// الملف اللي جوه الطلب بيتفك من JSON ويتعاد بناؤه، فبيتخزن مرتين تلاتة في
  /// ذاكرة الـ Edge Function المحدودة — وده كان بيدي WORKER_RESOURCE_LIMIT.
  /// الملف الكبير بيتمرر تمرير للـ Files API من غير ما يتجمع في الذاكرة.
  /// A file inside the request is parsed out of JSON then rebuilt, so it sits
  /// in the Edge Function's small memory two or three times over — which is
  /// what produced WORKER_RESOURCE_LIMIT. A large file is streamed through to
  /// the Files API without ever being gathered.
  static const inlineBytes = 3 * 1024 * 1024;

  /// أقصى حجم بنقبله أصلاً — حد المتصفح والصبر مش حد الخدمة.
  /// The largest file accepted at all: a limit of browser memory and patience
  /// rather than of the service.
  static const maxBytes = 300 * 1024 * 1024;

  bool get needsUpload => bytes.length > inlineBytes;
  bool get isTooBig => bytes.length > maxBytes;
  double get megabytes => bytes.length / (1024 * 1024);
  bool get isAudio => mimeType.startsWith('audio/');
}

/// ملف اترفع للموديل مرة واحدة، وبيتشار له بالرابط بعد كده.
/// A file uploaded to the model once, then referenced by URI.
///
/// المحاضرة الساعتين ممكن تبقى 80 ميجا. ترميزها base64 جوه كل طلب معناه إنها
/// ما تعديش أصلاً؛ الرفع بيحصل مرة، والتفريغ بيشاور على الرابط.
/// A two-hour lecture can be 80 MB. Base64-ing it into every request means it
/// never gets through at all; uploading happens once and the transcription
/// points at the URI.
class UploadedFile {
  const UploadedFile({
    required this.uri,
    required this.mimeType,
    required this.name,
    required this.state,
  });

  final String uri;
  final String mimeType;
  final String name;

  /// جوجل بتعالج الصوت قبل ما يبقى صالح للقراية.
  /// Google processes audio before it can be read.
  final String state;

  bool get isReady => state == 'ACTIVE';
}

/// محاضرة اتقريت من جدول المستخدم قبل ما تتحفظ.
/// A lecture read out of the user's timetable, before it is saved.
///
/// مش `ScheduleEntry` على طول: اللي راجع من الموديل لازم يتراجع بالعين الأول،
/// والـ id والمادة بيتحطوا وقت الحفظ.
/// Not a `ScheduleEntry` straight away: what comes back from the model is
/// reviewed by eye first, and the id and subject are attached when saving.
class ParsedLecture {
  const ParsedLecture({
    required this.title,
    required this.weekday,
    required this.startMinutes,
    this.endMinutes,
    this.location = '',
    this.lecturer = '',
    this.group = '',
  });

  final String title;
  final int weekday;
  final int startMinutes;
  final int? endMinutes;
  final String location;
  final String lecturer;

  /// القسم أو المجموعة اللي المحاضرة دي ليها — فاضية معناها للكل.
  /// The section or group this lecture belongs to; empty means everyone's.
  final String group;

  /// بيقرا صف واحد من رد الموديل، ويرجّع null لو الصف ناقص أو غلط.
  /// Reads one row of the model's reply, returning null when the row is
  /// incomplete or malformed.
  ///
  /// الموديل بيرجّع أسماء أيام مش أرقام — الأرقام بيغلط فيها (هل الأسبوع بيبدأ
  /// السبت ولا الاتنين؟) والأسماء بيعرفها كويس.
  /// The model returns day names rather than numbers: it gets numbering wrong
  /// (does the week start on Saturday or Monday?) while it knows names well.
  static ParsedLecture? fromJson(Map<String, dynamic> m) {
    final title = '${m['title'] ?? ''}'.trim();
    final weekday = weekdayFromName('${m['day'] ?? ''}');
    final start = minutesFromClock('${m['start'] ?? ''}');
    if (title.isEmpty || weekday == null || start == null) return null;

    return ParsedLecture(
      title: title,
      weekday: weekday,
      startMinutes: start,
      endMinutes: minutesFromClock('${m['end'] ?? ''}'),
      location: '${m['location'] ?? ''}'.trim(),
      lecturer: '${m['lecturer'] ?? ''}'.trim(),
      group: '${m['group'] ?? ''}'.trim(),
    );
  }

  /// بيحوّل اسم اليوم لرقمه (1 = الاتنين ... 7 = الأحد).
  /// Turns a day's name into its number (1 = Monday ... 7 = Sunday).
  static int? weekdayFromName(String raw) {
    final name = raw.trim().toLowerCase();
    if (name.isEmpty) return null;

    const days = <int, List<String>>{
      1: ['الاثنين', 'الإثنين', 'الاتنين', 'monday', 'mon'],
      2: ['الثلاثاء', 'التلات', 'الثلاث', 'tuesday', 'tue'],
      3: ['الأربعاء', 'الاربعاء', 'الأربع', 'wednesday', 'wed'],
      4: ['الخميس', 'thursday', 'thu'],
      5: ['الجمعة', 'friday', 'fri'],
      6: ['السبت', 'saturday', 'sat'],
      7: ['الأحد', 'الاحد', 'sunday', 'sun'],
    };

    for (final entry in days.entries) {
      for (final option in entry.value) {
        if (name.contains(option)) return entry.key;
      }
    }
    // الرقم مقبول كمان لو الموديل أصر يبعته.
    // A number is accepted too, if the model insists on sending one.
    final n = int.tryParse(name);
    return (n != null && n >= 1 && n <= 7) ? n : null;
  }

  /// "10:30" أو "10:30 ص" -> دقايق من نص الليل.
  /// "10:30" or "10:30 am" -> minutes from midnight.
  static int? minutesFromClock(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final match = RegExp(r'(\d{1,2})\s*[:.\u060C]?\s*(\d{2})?').firstMatch(text);
    if (match == null) return null;

    var hour = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    if (hour == null || hour > 23 || minute > 59) return null;

    final lower = text.toLowerCase();
    final isPm = lower.contains('pm') || text.contains('م');
    final isAm = lower.contains('am') || text.contains('ص');
    if (isPm && hour < 12) hour += 12;
    if (isAm && hour == 12) hour = 0;

    return hour * 60 + minute;
  }
}

/// جدول اتقرا: محاضراته، والأقسام اللي جواه، وإزاي اتعرفت.
/// A timetable as read: its lectures, the sections inside it, and how they were
/// recognised.
///
/// جداول الكليات بتبقى مدمجة: نفس الفترة فيها محاضرة لقسم أ في قاعة، ولقسم ب
/// في قاعة تانية. اللي بياخدها كلها على إنها جدوله بيلاقي نفسه في تلات قاعات
/// في نفس الوقت.
/// College timetables come merged: the same slot holds a lecture for section A
/// in one room and for section B in another. Taking all of them as your own
/// puts you in three rooms at once.
class ParsedSchedule {
  const ParsedSchedule({
    required this.entries,
    this.groups = const [],
    this.groupLabel = '',
    this.note = '',
    this.failedDays = const [],
  });

  final List<ParsedLecture> entries;

  /// أسماء الأقسام اللي في الجدول. فاضية معناها جدول لقسم واحد.
  /// The section names found. Empty means a timetable for one section.
  final List<String> groups;

  /// اسم نوعهم زي ما هو مكتوب: قسم، مجموعة، شعبة، فرقة.
  /// What they are called as written: section, group, division, year.
  final String groupLabel;

  /// سطر بيقول الأقسام اتعرفت إزاي — عشان تقدر تتأكد من قراءته.
  /// A line saying how the sections were recognised, so the reading can be
  /// checked.
  final String note;

  /// أيام حاولنا نستخرج محاضراتها وفشلنا (حصة خلصت، تايم آوت) فمالهاش
  /// محاضرات في "entries" أصلاً — الجدول ناقص بسببها بصمت من غير الحقل ده.
  /// Days a lecture-extraction attempt failed for (quota spent, timeout) and
  /// so have no entries at all — the schedule is silently missing them
  /// without this field.
  final List<String> failedDays;

  bool get needsChoice => groups.length > 1;

  /// بيفصل "A-G1" لقسم رئيسي "A" ومجموعة فرعية "G1"، أو يرجّع القيمة زي ما
  /// هي كقسم لوحده لو مفيهاش "-" (مفيش تقسيم مستويين).
  /// Splits "A-G1" into main section "A" and subgroup "G1", or returns the
  /// value as a standalone section when there is no "-" (no two-level split).
  static (String, String?) _splitGroup(String raw) {
    final trimmed = raw.trim();
    final i = trimmed.indexOf('-');
    if (i <= 0) return (trimmed, null);
    final section = trimmed.substring(0, i).trim();
    final subgroup = trimmed.substring(i + 1).trim();
    return (section, subgroup.isEmpty ? null : subgroup);
  }

  /// بيرجّع صيغة تسمح بالمقارنة من غير حساسية لحالة الحروف أو صفر بادئ أو
  /// حرف "G" ممكن يتلزق أو يتشال — الموديل مش دايمًا بيكرر نفس الصيغة
  /// بالظبط، خصوصًا لما استخراج المحاضرات بيتقسم على كذا نداء منفصل (يوم
  /// لكل نداء) وكل نداء ممكن يكتبها شكل شوية مختلف عن التاني.
  /// A comparable form insensitive to letter case, a leading zero, or a "G"
  /// that may or may not be attached — the model does not always repeat the
  /// exact same spelling, especially once entry extraction is split across
  /// several separate calls (one per day) that can each phrase it slightly
  /// differently.
  static String _normalize(String raw) {
    final digits = RegExp(r'\d+').firstMatch(raw)?.group(0);
    if (digits != null) return digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return raw.trim().toLowerCase();
  }

  /// الأقسام الرئيسية، وتحت كل واحد المجموعات الفرعية اللي جواه (لو في).
  /// The main sections, each mapped to the subgroups found inside it (if any).
  Map<String, List<String>> get sections {
    final map = <String, List<String>>{};
    for (final g in groups) {
      final (section, subgroup) = _splitGroup(g);
      final subs = map.putIfAbsent(section, () => []);
      if (subgroup != null && !subs.contains(subgroup)) subs.add(subgroup);
    }
    return map;
  }

  /// محاضرات قسم واحد (ومجموعته الفرعية لو اتحددت) + المحاضرات اللي للكل.
  /// One section's lectures (and its subgroup, if given) plus the ones that
  /// belong to everyone.
  List<ParsedLecture> forGroup(String? section, [String? subgroup]) {
    if (section == null || section.isEmpty) return entries;
    final wantSection = _normalize(section);
    final wantSubgroup = subgroup == null ? null : _normalize(subgroup);
    return entries.where((e) {
      if (e.group.isEmpty) return true;
      final (esection, esubgroup) = _splitGroup(e.group);
      if (_normalize(esection) != wantSection) return false;
      if (wantSubgroup == null || esubgroup == null) return true;
      return _normalize(esubgroup) == wantSubgroup;
    }).toList();
  }
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
  /// [lectureText] للنص الملزوق أو المستخرج أو المفرّغ من الصوت، و[files]
  /// للملفات اللي الموديل بيقراها بنفسه (PDF). واحد منهم لازم يكون موجود،
  /// وممكن يتبعتوا مع بعض: سلايدات مرفقة + تفريغ التسجيل لنفس المحاضرة.
  /// [lectureText] carries pasted, extracted or transcribed text; [files]
  /// carries files the model reads itself (PDF). At least one must be present,
  /// and both can travel together: attached slides plus the recording's
  /// transcript for the same lecture.
  Stream<String> summarize({
    String lectureText = '',
    List<LectureFile> files = const [],
    required List<StyleSample> samples,
  });

  /// بيحوّل تسجيل صوتي لنص.
  /// Turns a recording into text.
  ///
  /// مقطع واحد في النداء الواحد: المقاطع الطويلة بتتفرّغ واحد ورا التاني
  /// وتفريغهم بيتلزق، عشان طول المحاضرة ما يبقاش محدود بحجم الطلب.
  /// One part per call: long recordings are transcribed part after part and
  /// their text joined, so a lecture's length is not bounded by one request.
  Future<String> transcribe(LectureFile audio, {UploadedFile? uploaded});

  /// بيرفع ملف كبير مرة واحدة عشان يتشار له بعد كده بالرابط.
  /// Uploads a large file once so it can be referenced by URI afterwards.
  ///
  /// [onProgress] بياخد كسر من 0 لـ 1 — الرفع على نت بطيء بياخد دقايق، ولازم
  /// المستخدم يشوفه ماشي.
  /// [onProgress] takes a fraction from 0 to 1: on a slow line the upload runs
  /// for minutes, and the user has to see it moving.
  Future<UploadedFile> upload(
    LectureFile file, {
    void Function(double fraction)? onProgress,
  });

  /// بيعمل كروت مراجعة من محتوى مذاكرة.
  /// Builds review cards out of study material.
  Future<List<GeneratedCard>> makeCards(String source, {int count});

  /// بيجاوب على سؤال في محاضرة، والإجابة بتيجي وهي بتتكتب.
  /// Answers a question about a lecture, streaming as it writes.
  Stream<String> ask({
    required String source,
    required String question,
    List<AskTurn> history,
  });

  /// بيعمل أسئلة امتحان من المحتوى.
  /// Builds exam questions from the material.
  Future<List<ExamQuestion>> makeExam({
    required String source,
    int choiceCount,
    int writtenCount,
  });

  /// بيصحح الإجابات المقالية ويقول الضعف فين.
  /// Marks the written answers and says where the gaps are.
  Future<ExamResult> gradeExam({
    required String source,
    required List<AnsweredQuestion> answers,
  });

  /// بيعمل خطة أسبوع من معطيات الطالب.
  /// Builds a week's plan from the student's own situation.
  Future<StudyPlan> makePlan(String facts);

  /// بيقرا جدول محاضرات من نص ملزوق أو صورة ويرجّعه مرتّب.
  /// Reads a timetable out of pasted text or a photo and returns it ordered.
  ///
  /// الجدول بييجي بأشكال مالهاش آخر: جدول من الكلية، صورة من واتساب، رسالة
  /// مكتوبة على السريع. اللي تحتها كلها نفس البيانات — يوم ووقت وقاعة.
  /// A timetable arrives in endless shapes: a college table, a photo from
  /// WhatsApp, a hastily typed message. Underneath they are all the same data:
  /// a day, a time and a room.
  ///
  /// [onProgress] بيتنادى بنسبة تقريبية (0 لـ 1) — مفيش تقدّم حقيقي لنداء
  /// جوجل نفسه (رد واحد مش بث)، فالنسبة مبنية على الرفع الحقيقي زائد بينج
  /// الانتظار، عشان الشريط يتحرك بدل ما يقف ساكت دقيقة ونص.
  /// [onProgress] is called with a rough fraction (0 to 1) — there is no real
  /// progress for the Google call itself (one reply, not a stream), so the
  /// fraction is built from real upload progress plus the wait's heartbeat,
  /// so the bar moves instead of sitting frozen for a minute and a half.
  Future<ParsedSchedule> parseSchedule({
    String text,
    List<LectureFile> images,
    void Function(double fraction)? onProgress,
  });

  /// بيحلل صورة من كراسة المستخدم ويرجّع شكل صفحته ونص تلخيصها.
  /// Reads a photo of the user's notebook: its layout and its written summary.
  Future<StyleAnalysis> analyzeStyle(List<LectureFile> images);

  /// بيلخص ويرجّع بلوكات جاهزة للرسم بدل نص عادي.
  /// Summarizes into drawable blocks instead of prose.
  Future<SummaryPage> summarizeAsPage({
    String lectureText,
    List<LectureFile> files,
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
- المعادلات اكتبها مقروءة على طول: ½ م ع² أو KE = ½ m v². متكتبش LaTeX ولا \\frac ولا علامات \$.
- ابدأ بالتلخيص على طول. متكتبش مقدمة زي "إليك التلخيص" ولا تعليق في الآخر.
''';

  static String build({
    String lectureText = '',
    bool hasFile = false,
    required List<StyleSample> samples,
  }) {
    final buffer = StringBuffer();
    final text = lectureText.trim();

    // المصدرين ممكن يتواجدوا مع بعض: سلايدات مرفقة وتفريغ تسجيل لنفس
    // المحاضرة. لو النص اتشال وقتها، شرح المحاضر كله بيضيع.
    // Both sources can be present at once: attached slides and the transcript
    // of the same lecture. Dropping the text then would throw away everything
    // the lecturer actually said.
    final lectureBody = switch ((hasFile, text.isNotEmpty)) {
      (true, true) =>
        '(المحاضرة في الملف المرفق، ودي نصوص من نفس المحاضرة — '
            'تفريغ صوتي أو نص ملزوق. اعتبرهم مصدر واحد)\n\n$text',
      (true, false) => '(المحاضرة في الملف المرفق)',
      _ => text,
    };

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

  /// تعليمات التفريغ — منفصلة تمامًا عن تعليمات التلخيص.
  /// The transcription instructions, kept entirely apart from the summarizing
  /// ones.
  ///
  /// لو اتبعتت تعليمات التلخيص مع الصوت، الموديل بيلخص وهو بيفرّغ ويضيع كلام.
  /// التفريغ خطوة أمينة، والتلخيص بيحصل بعدها على النص الكامل.
  /// Sending the summarizing instructions with the audio makes the model
  /// summarize as it transcribes, losing what was said. Transcription is a
  /// faithful step; summarizing happens afterwards over the full text.
  static const transcribeSystem = '''
أنت بتفرّغ تسجيل محاضرة لنص مكتوب.

- اكتب اللي اتقال بالظبط بنفس اللغة اللي اتقال بيها.
- متلخصش ومتختصرش ومتعلّقش على المحتوى.
- متضفش عناوين ولا تنسيق ولا أوقات.
- المصطلحات الأجنبية اكتبها زي ما اتنطقت.
- الكلام المش واضح اكتبه (غير واضح).
- لو المقطع مفيهوش كلام، اكتب (مفيش كلام) وبس.
''';

  static const transcribePrompt =
      'فرّغ التسجيل المرفق. اكتب النص بس من غير أي مقدمة أو تعليق.';

  /// تعليمات قراية الجدول — على مرحلتين بدل نداء واحد.
  /// The timetable-reading instructions — split into two calls, not one.
  ///
  /// نداء واحد بيحاول يكتشف التركيب (أعمدة الوقت، الأقسام) ويستخرج كل
  /// المحاضرات في نفس الوقت — على جدول كثيف ده حِمل ذهني زيادة عن اللزوم بيتجمع
  /// غلطه. المرحلة الأولى بتكتشف التركيب بس (مهمة أصغر بكتير)، والتانية
  /// بتستخرج المحاضرات وهي شايلة نتيجة الأولى كحقيقة مؤكدة، مش بتكتشفها تاني.
  /// One call trying to discover the structure (time columns, sections) and
  /// extract every lecture at once piles up mistakes on a dense table — too
  /// much held in mind together. The first phase discovers structure alone (a
  /// much smaller task), and the second extracts lectures carrying that result
  /// as an established fact instead of rediscovering it.
  static const scheduleStructureSystem = '''
أنت بتقرا جدول محاضرات وبتكتشف بس تركيبه الأساسي — أعمدة الوقت والأقسام — من غير ما تستخرج المحاضرات نفسها دلوقتي، ده هيحصل في خطوة تانية بعدك.

هترجّع JSON بالشكل ده بالظبط:
{"day_start":"","day_end":"","slot_minutes":0,"time_columns":[],"days":[],"groups":[],"group_label":"","note":""}

**شريط الوقت فوق الجدول نوعين مختلفين، لازم تفرّق بينهم:**

1. **منتظم بلا فجوات**: كل عمود بيبدأ بالظبط لما اللي قبله يخلص، وكل الأعمدة نفس الطول (زي 9:30-10:00، 10:00-10:30، 10:30-11:00... كل نص ساعة). في الحالة دي: املأ "day_start" (أول وقت يبدأ بيه الشريط، زي "09:30") و"day_end" (آخر وقت ينتهي بيه، زي "16:00") و"slot_minutes" (طول العمود بالدقايق، غالبًا 30) — أرقام بس، من غير كلمة "استراحة" ولا "توافر الدكتور". سيب "time_columns" فاضية.
2. **مش منتظم** — علامته: **فجوة زمن بين عمودين** (عمود بيخلص 12:30 واللي بعده بيبدأ 12:45 مثلاً، ربع ساعة مالهاش عمود خاص بيها)، أو **الأعمدة نفسها أطوالها مختلفة** (عمود ساعة ونص جنب عمود نص ساعة)، أو كل عمود أصلاً هو معاد محاضرة كامل زي ما هو مكتوب (مش تقسيم لنص ساعات). في الحالة دي **متستخدمش day_start/day_end خالص** — بدل كده رجّع "time_columns": قايمة بعناوين كل الأعمدة زي ما هي مكتوبة بالظبط فوق الجدول، بالترتيب من الشمال لليمين (مثلاً ["9:30 - 11:00"، "11:00 - 12:30"، "12:45 - 2:15"، "2:15 - 3:45"]) — انسخها حرفيًا، متحاولش "تظبطها" على شبكة منتظمة. سيب "day_start"/"day_end" فاضيين و"slot_minutes" صفر.

**الجدول المدمج**: جداول الكليات غالبًا بتبقى لأكتر من قسم أو مجموعة أو شعبة أو فرقة في ورقة واحدة. نفس الفترة بتلاقي فيها محاضرة لقسم في قاعة، ولقسم تاني في قاعة تانية.

- دوّر على ده. علامته: عمود لكل قسم، أو اسم/رقم مكتوب جنب كل محاضرة (أ/ب/ج، 1/2/3، شعبة كذا)، أو جدول متكرر تحت بعضه بعناوين مختلفة. علامة تانية: نفس اسم المادة والدكتور متكرر أكتر من مرة في نفس اليوم والفترة، كل مرة في قاعة مختلفة.
- **الجدول ممكن يبقى فيه عمود قسم بمستويين مكتوبين مع بعض**: حرف رئيسي (A-F)، وتحته أو جنبه أرقام فرعية ثابتة لكل حرف (زي G1-G18، حرف A بياخد G1..G3 مثلاً، B بياخد G4..G6، وهكذا). لو شفت الشكل ده، حط في "groups" كل تركيبة "الحرف-الرقم" زي ما هي مكتوبة (مثلاً "A-G1")، مش الحرف لوحده ولا الرقم لوحده.
- لو لقيت أقسام: حط أسماءها في "groups" زي ما هي مكتوبة، وحط نوعها في "group_label" (قسم / مجموعة / شعبة / فرقة). لو الجدول لقسم واحد بس، سيب "groups" فاضية.
- "note": سطر واحد يقول عرفت الأقسام والأعمدة منين بالظبط (مثلاً: "كل عمود قسم" أو "نفس المادة متكررة بقاعات مختلفة").
- "days": كل الأيام اللي فيها محاضرات في الجدول، بالترتيب اللي ظاهرة بيه، كل يوم بالعربي كامل (السبت، الأحد، الاثنين، الثلاثاء، الأربعاء، الخميس، الجمعة).

رجّع JSON بس من غير أي كلام قبله أو بعده.
''';

  static String scheduleStructurePrompt(String text) {
    const task = 'دلوقتي عايزك تكتشف بس تركيب الجدول: أعمدة الوقت والأقسام. '
        'متستخرجش المحاضرات نفسها لسه.';
    if (text.trim().isEmpty) {
      return 'اقرا جدول المحاضرات من الملفات المرفقة (ممكن تكون صور أو PDF '
          'كذا صفحة). $task';
    }
    return 'اقرا جدول المحاضرات ده. $task\n\n${text.trim()}';
  }

  /// تعليمات استخراج المحاضرات، بعد ما التركيب اتأكد في المرحلة الأولى.
  /// The lecture-extraction instructions, once structure is confirmed in
  /// phase one.
  static String scheduleEntriesSystem({
    required List<String> timeColumns,
    required List<String> groups,
    required String groupLabel,
    List<String>? days,
  }) {
    final dayLine = (days == null || days.isEmpty)
        ? ''
        : '\n**دلوقتي مطلوب منك الأيام دي بس: ${days.map((d) => '"$d"').join('، ')}** '
            '— استخرج محاضراتهم هم، وتجاهل تمامًا أي يوم تاني ظاهر في نفس '
            'الجدول حتى لو قدامك. أي محاضرة يومها مش من ضمن الأيام دي '
            'بالظبط، سيبها ومترجعهاش.\n';
    final columnsLine = timeColumns.isEmpty
        ? 'الجدول ده مفهوش أعمدة زمن ثابتة — كل محاضرة وقتها مكتوب جنبها مباشرة.'
        : 'أعمدة الوقت **مؤكدة ومتفق عليها بالفعل**، بالترتيب: '
            '${timeColumns.join(' | ')}';
    final groupsLine = groups.isEmpty
        ? 'الجدول ده لقسم واحد بس — سيب "group" فاضية في كل محاضرة.'
        : 'الأقسام **مؤكدة ومتفق عليها بالفعل** (${groupLabel.isEmpty ? "قسم" : groupLabel}) — دي **القايمة المغلقة الوحيدة** المسموح بيها لقيمة "group"، منها بس ومفيش غيرها:\n'
            '  ${groups.map((g) => '"$g"').join('، ')}\n'
            '  **حط قسم كل محاضرة بنسخ إحدى القيم دي حرفيًا زي ما هي مكتوبة فوق بالظبط — نفس الحروف الكبيرة/الصغيرة، نفس الشرطة، من غير ما تزود أو تشيل مسافة.** ممنوع تخترع صيغة تانية قريبة (زي تشيل حرف أو رقم أو تضيف صفر) حتى لو شايف إنها بتوصف نفس القسم.';
    final timeGuidance = timeColumns.isEmpty
        ? ''
        : 'احسب وقت كل محاضرة بالرجوع لأعمدة الوقت المؤكدة فوق بس: شوف خلية '
            'المحاضرة بتلمس كام عمود منها جنب بعض (حدودها بلونها أو تكرار '
            'نفس النص جواها)، و"start" = بداية أول عمود لمسته، و"end" = '
            'نهاية آخر عمود لمسته.\n'
            '  **غلط شائع جدًا**: أغلب الجداول بتحط عمود فاضي (لونه مختلف '
            'تمامًا عن لون خلية المحاضرة — أبيض أو رمادي فاتح، ممكن يبقى '
            'مكتوب فيه "استراحة/Break" أو "توافر الدكتور/Lecturer '
            'availability") بعد كل محاضرة تقريبًا. الغلط اللي بيحصل كتير: مد '
            '"end" نص ساعة زيادة عشان العمود الفاضي ده يبان جزء من '
            'المحاضرة. **قبل ما تكتب "end" لأي محاضرة، شوف العمود اللي '
            'بعد آخر عمود ملوّن فيها اسم المادة — لو لونه مختلف/فاضي، '
            '"end" بتاعك يوقف عند حدود آخر عمود ملوّن، من غير ما يضيف نص '
            'الساعة بتاعت العمود الفاضي جنبه.**\n'
            '  **فحص اتساق الوقت**: محاضرتين مختلفتين (عنوان مختلف) لنفس '
            'القسم في نفس اليوم متينفعش ياخدوا نفس الوقت بالظبط، إلا لو '
            'فعلاً موازيين ومكتوبين في نفس الخلية (زي "Skill a"/"Skill b"). '
            'لو رجّعت كده، ارجع اتأكد من عدّ الأعمدة وصحّحه قبل ما ترجّع الرد.';

    return '''
أنت بتستخرج محاضرات جدول اتفحص تركيبه قبل كده. التركيب ده مؤكد، متكتشفهوش تاني ولا تشك فيه:
$dayLine
$columnsLine
$groupsLine

هترجّع JSON بالشكل ده بالظبط:
{"entries":[{"title":"","day":"","start":"","end":"","location":"","lecturer":"","group":""}]}

- "title": اسم المادة أو المحاضرة زي ما هو مكتوب.
- "day": اسم اليوم بالعربي كامل (السبت، الأحد، الاثنين، الثلاثاء، الأربعاء، الخميس، الجمعة).
- "start" و "end": الوقت بنظام 24 ساعة "HH:MM". لو الوقت مكتوب 10-12 يبقى start "10:00" و end "12:00". لو مفيش وقت نهاية سيب "end" فاضية.
  $timeGuidance
- "location": القاعة أو المدرج أو المعمل زي ما هو مكتوب. لو مش موجود سيبها فاضية.
- "lecturer": اسم الدكتور لو مكتوب، وإلا فاضية.
- **فحص اتساق القاعة**: كل قسم لازم يفضل في نفس القاعة طول محاضرات نفس اليوم (أو نمط ثابت واضح). لو رجّعت قسم واحد بمحاضرتين في قاعتين مختلفتين في نفس اليوم من غير أي إشارة في الجدول تفسّر ده، يبقى في غلط — ارجع للجدول وصحّحه قبل ما ترجّع الرد.

قواعد:
- كل محاضرة سطر لوحدها. المحاضرة اللي بتتكرر في يومين بتتكتب مرتين.
- المحاضرة اللي في نفس الفترة لأكتر من قسم بتتكتب مرة لكل قسم بقاعته.
- متخترعش بيانات. اللي مش مكتوب سيبه فاضي.
- متزودش محاضرات مش موجودة ومتشيلش حاجة موجودة.
- رجّع JSON بس من غير أي كلام قبله أو بعده.
''';
  }

  static String scheduleEntriesPrompt(String text, {List<String>? days}) {
    final scope = (days == null || days.isEmpty)
        ? 'دلوقتي استخرج كل محاضرة بالتفصيل.'
        : 'دلوقتي استخرج محاضرات الأيام دي بس بالتفصيل: ${days.join('، ')}. '
            'سيب أي يوم تاني.';
    final task = 'التركيب (الأعمدة والأقسام) معروف ومؤكد بالفعل زي ما اتقالك. $scope';
    if (text.trim().isEmpty) {
      return 'اقرا جدول المحاضرات من نفس الملفات المرفقة. $task';
    }
    return 'اقرا جدول المحاضرات ده تاني. $task\n\n${text.trim()}';
  }

  /// تقدير تقريبي لعدد التوكنز — العربي حوالي 2.6 حرف للتوكن.
  /// Rough token estimate; Arabic runs about 2.6 characters per token.
  static int approxTokens(String text) => (text.length / 2.6).round();
}
