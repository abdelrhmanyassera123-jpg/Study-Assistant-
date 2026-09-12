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

  bool get needsChoice => groups.length > 1;

  /// بيفصل "A-G1" لقسم رئيسي "A" ومجموعة فرعية "G1"، أو يرجّع القيمة زي ما
  /// هي كقسم لوحده لو مفيهاش "-" (مفيش تقسيم مستويين).
  /// Splits "A-G1" into main section "A" and subgroup "G1", or returns the
  /// value as a standalone section when there is no "-" (no two-level split).
  static (String, String?) _splitGroup(String raw) {
    final i = raw.indexOf('-');
    if (i <= 0) return (raw, null);
    return (raw.substring(0, i), raw.substring(i + 1));
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
    return entries.where((e) {
      if (e.group.isEmpty) return true;
      final (esection, esubgroup) = _splitGroup(e.group);
      if (esection != section) return false;
      return subgroup == null || esubgroup == null || esubgroup == subgroup;
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

  /// تعليمات قراية الجدول.
  /// The timetable-reading instructions.
  static const scheduleSystem = '''
أنت بتقرا جدول محاضرات وبتفهم تركيبه قبل ما ترجّعه بيانات منظمة.

هترجّع JSON بالشكل ده بالظبط:
{"groups":[],"group_label":"","note":"","entries":[{"title":"","day":"","start":"","end":"","location":"","lecturer":"","group":""}]}

- "title": اسم المادة أو المحاضرة زي ما هو مكتوب.
- "day": اسم اليوم بالعربي كامل (السبت، الأحد، الاثنين، الثلاثاء، الأربعاء، الخميس، الجمعة).
- "start" و "end": الوقت بنظام 24 ساعة "HH:MM". لو الوقت مكتوب 10-12 يبقى start "10:00" و end "12:00". لو مفيش وقت نهاية سيب "end" فاضية.
  **جداول فيها أعمدة كل نص ساعة (9:30، 10:00، 10:30...) دي مسطرة زمن مش مدة المحاضرة.** خلية المحاضرة بتمتد فوق كذا عمود من الأعمدة دي — اتبع حدود الخلية (لونها أو تكرار اسم المادة) عشان تعرف تمتد لحد فين، ومترجّعش نص ساعة بس لأن ده أول عمود لمستها بس.
- "location": القاعة أو المدرج أو المعمل زي ما هو مكتوب. لو مش موجود سيبها فاضية.
- "lecturer": اسم الدكتور لو مكتوب، وإلا فاضية.

**الأهم — الجدول المدمج:**
جداول الكليات غالبًا بتبقى لأكتر من قسم أو مجموعة أو شعبة أو فرقة في ورقة واحدة.
نفس الفترة بتلاقي فيها محاضرة لقسم في قاعة، ولقسم تاني في قاعة تانية.

- دوّر على ده الأول. علامته: عمود لكل قسم، أو اسم/رقم مكتوب جنب كل محاضرة (أ/ب/ج، 1/2/3، شعبة كذا)، أو جدول متكرر تحت بعضه بعناوين مختلفة.
- **وعلامة تانية مهمة**: نفس اسم المادة والدكتور متكرر أكتر من مرة في نفس اليوم والفترة، كل مرة في قاعة مختلفة — ده جدول مدمج حتى لو مفيش عمود واضح لكل قسم. كل تكرار قسم لوحده، وسمّيه بالحرف أو الرقم المكتوب جنبه في الجدول (زي A/B/C، أو رقم الشعبة).
- **الجدول ممكن يبقى فيه تقسيم على مستويين مكتوب في الجدول نفسه**: عمود لحرف قسم رئيسي (A-F)، وتحته أو جنبه أرقام فرعية مكتوبة صراحة لكل صف (زي G1-G18) — كل حرف بياخد مجموعة أرقام ثابتة بتاعته (مثلاً A=G1..G3، B=G4..G6). **لو الجدول متقسم بالشكل ده، رجّع الحرف والرقم مع بعض دايمًا** بالصيغة "الحرف-الرقم" زي ما هما مكتوبين (مثلاً "A-G1"، "B-G5") لكل صف تحت الحرف ده — **حتى لو المعاد أو القاعة متساوية بين كل الأرقام الفرعية تحت نفس الحرف**، ومترجّعش الرقم لوحده ولا الحرف لوحده. ده عشان التطبيق يسأل المستخدم على قسمه الرئيسي الأول وبعدين رقمه الفرعي جواه، مش يحطله كل الأرقام (ممكن توصل 18) في قايمة واحدة مسطحة يدوّر فيها. أما لو الجدول فيه مستوى واحد بس (حرف لوحده، أو رقم لوحده من غير حرف فوقه في الجدول)، رجّع القيمة زي ما هي من غير تركيب.
- **فحص اتساق**: كل قسم لازم يفضل في **نفس القاعة** طول محاضرات نفس اليوم (أو نمط ثابت واضح). لو رجّعت قسم واحد بمحاضرتين في قاعتين مختلفتين في نفس اليوم من غير أي إشارة في الجدول تفسّر ده، يبقى في غلط في الفهم — ارجع للجدول وصحّح التقسيم قبل ما ترجّع الرد.
- لو لقيت أقسام: حط أسماءها في "groups" زي ما هي مكتوبة، وحط نوعها في "group_label" (قسم / مجموعة / شعبة / فرقة).
- وحط قسم كل محاضرة في "group". المحاضرة اللي لكل الأقسام (زي محاضرة عامة) سيب "group" فاضية.
- لو الجدول لقسم واحد بس، سيب "groups" فاضية و"group" فاضية في كل محاضرة.
- "note": سطر واحد يقول عرفت الأقسام منين بالظبط (مثلاً: "كل عمود قسم" أو "نفس المادة متكررة بقاعات مختلفة").

قواعد:
- كل محاضرة سطر لوحدها. المحاضرة اللي بتتكرر في يومين بتتكتب مرتين.
- المحاضرة اللي في نفس الفترة لأكتر من قسم بتتكتب مرة لكل قسم بقاعته.
- متخترعش بيانات. اللي مش مكتوب سيبه فاضي.
- متزودش محاضرات مش موجودة ومتشيلش حاجة موجودة.
- رجّع JSON بس من غير أي كلام قبله أو بعده.
''';

  static String schedulePrompt(String text) {
    const task = 'افحص تركيب الجدول الأول: هو لقسم واحد ولا فيه كذا قسم '
        'مدمجين؟ وبعدين رجّعه بالشكل المطلوب.';
    if (text.trim().isEmpty) {
      return 'اقرا جدول المحاضرات من الملفات المرفقة (ممكن تكون صور أو PDF '
          'كذا صفحة). $task';
    }
    return 'اقرا جدول المحاضرات ده. $task\n\n${text.trim()}';
  }

  /// تقدير تقريبي لعدد التوكنز — العربي حوالي 2.6 حرف للتوكن.
  /// Rough token estimate; Arabic runs about 2.6 characters per token.
  static int approxTokens(String text) => (text.length / 2.6).round();
}
