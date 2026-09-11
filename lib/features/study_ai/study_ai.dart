import 'package:flutter/material.dart';

/// كارت مراجعة طلع من المحتوى قبل ما يتحفظ.
/// A review card generated from the material, before it is saved.
@immutable
class GeneratedCard {
  const GeneratedCard({required this.front, required this.back});

  final String front;
  final String back;

  static GeneratedCard? fromJson(Map<String, dynamic> m) {
    final front = '${m['front'] ?? m['q'] ?? ''}'.trim();
    final back = '${m['back'] ?? m['a'] ?? ''}'.trim();
    if (front.isEmpty || back.isEmpty) return null;
    return GeneratedCard(front: front, back: back);
  }
}

/// سؤال في الامتحان التجريبي.
/// One question in the mock exam.
///
/// الاختيار من متعدد والمقالي في نوع واحد: الفرق بينهم إن الأول ليه اختيارات
/// وإجابة صح معروفة، والتاني بيتصحح بالموديل.
/// Multiple choice and written answers share one type: the difference is that
/// the first has options and a known right answer, while the second is marked
/// by the model.
@immutable
class ExamQuestion {
  const ExamQuestion({
    required this.question,
    this.choices = const [],
    this.answerIndex,
    this.modelAnswer = '',
  });

  final String question;

  /// فاضية معناها سؤال مقالي.
  /// Empty means a written question.
  final List<String> choices;

  final int? answerIndex;

  /// الإجابة النموذجية — للمقالي، وبتتعرض بعد التصحيح.
  /// The model answer, for written questions, shown after marking.
  final String modelAnswer;

  bool get isChoice => choices.length > 1 && answerIndex != null;

  static ExamQuestion? fromJson(Map<String, dynamic> m) {
    final question = '${m['question'] ?? m['q'] ?? ''}'.trim();
    if (question.isEmpty) return null;

    final rawChoices = m['choices'];
    final choices = <String>[
      if (rawChoices is List)
        for (final c in rawChoices)
          if ('$c'.trim().isNotEmpty) '$c'.trim(),
    ];

    final rawAnswer = m['answer'];
    final answerIndex = rawAnswer is num ? rawAnswer.toInt() : null;
    final valid = answerIndex != null &&
        answerIndex >= 0 &&
        answerIndex < choices.length;

    return ExamQuestion(
      question: question,
      choices: valid ? choices : const [],
      answerIndex: valid ? answerIndex : null,
      modelAnswer: '${m['model_answer'] ?? m['answer_text'] ?? ''}'.trim(),
    );
  }
}

/// سؤال مقالي وإجابة الطالب عليه، جاهزين للتصحيح.
/// A written question with the student's answer, ready to be marked.
@immutable
class AnsweredQuestion {
  const AnsweredQuestion({
    required this.index,
    required this.question,
    required this.expected,
    required this.answer,
  });

  final int index;
  final String question;
  final String expected;
  final String answer;
}

/// تصحيح إجابة مقالية.
/// The marking of a written answer.
@immutable
class WrittenMark {
  const WrittenMark({
    required this.index,
    required this.score,
    required this.comment,
  });

  /// رقم السؤال زي ما اتبعت.
  /// The question's number as it was sent.
  final int index;

  /// من 0 لـ 1.
  /// From 0 to 1.
  final double score;

  final String comment;

  static WrittenMark? fromJson(Map<String, dynamic> m) {
    final index = m['index'];
    if (index is! num) return null;
    final score = m['score'];
    return WrittenMark(
      index: index.toInt(),
      score: score is num ? score.toDouble().clamp(0, 1) : 0,
      comment: '${m['comment'] ?? ''}'.trim(),
    );
  }
}

/// نتيجة الامتحان بعد التصحيح.
/// The exam's outcome after marking.
@immutable
class ExamResult {
  const ExamResult({
    required this.marks,
    required this.weakSpots,
    required this.advice,
  });

  final List<WrittenMark> marks;

  /// المواضيع اللي الإجابات بتقول إنها مش مذاكرة كويس.
  /// The topics the answers suggest are not yet solid.
  final List<String> weakSpots;

  final String advice;
}

/// بند واحد في خطة المذاكرة.
/// One item in the study plan.
@immutable
class PlanItem {
  const PlanItem({
    required this.what,
    required this.minutes,
    this.why = '',
  });

  final String what;
  final int minutes;
  final String why;

  static PlanItem? fromJson(Map<String, dynamic> m) {
    final what = '${m['what'] ?? m['task'] ?? ''}'.trim();
    if (what.isEmpty) return null;
    final minutes = m['minutes'];
    return PlanItem(
      what: what,
      minutes: minutes is num ? minutes.toInt().clamp(5, 240) : 30,
      why: '${m['why'] ?? ''}'.trim(),
    );
  }
}

/// يوم في الخطة.
/// A day in the plan.
@immutable
class PlanDay {
  const PlanDay({required this.weekday, required this.items});

  final int weekday;
  final List<PlanItem> items;

  int get totalMinutes => items.fold(0, (sum, i) => sum + i.minutes);
}

/// خطة أسبوع.
/// A week's plan.
@immutable
class StudyPlan {
  const StudyPlan({required this.days, this.note = ''});

  final List<PlanDay> days;

  /// سطر من الموديل بيشرح المنطق — مفيد لما الخطة تبان غريبة.
  /// A line from the model explaining its reasoning; useful when the plan looks
  /// odd.
  final String note;

  bool get isEmpty => days.every((d) => d.items.isEmpty);
  int get totalMinutes => days.fold(0, (sum, d) => sum + d.totalMinutes);
}

/// دور واحد في المحادثة عن المحاضرة.
/// One turn in the conversation about a lecture.
@immutable
class AskTurn {
  const AskTurn({required this.question, required this.answer});
  final String question;
  final String answer;
}

/// برومبتات المذاكرة — كلها بتشترك في قاعدة واحدة: المحتوى المعطى هو المصدر
/// الوحيد.
/// The study prompts. All share one rule: the given material is the only
/// source.
///
/// ده مش تشدد زيادة. الطالب بيذاكر من الكلام ده للامتحان، وأي معلومة الموديل
/// بيضيفها من عنده — حتى لو صح في المطلق — بتبقى غلط في ورقة الإجابة.
/// This is not excess caution. The student revises this material for an exam,
/// and anything the model adds from its own knowledge — even if true in
/// general — is wrong on the answer sheet.
class StudyAiPrompts {
  const StudyAiPrompts._();

  static const _grounding = '''
- المحتوى المعطى هو المصدر الوحيد. متضيفش أي معلومة من برّه.
- لو الإجابة مش في المحتوى، قول كده صراحة بدل ما تخترع.
- اكتب بنفس لغة المحتوى.
- المعادلات اكتبها مقروءة على طول: ½ م ع² أو KE = ½ m v². متكتبش LaTeX ولا \\frac ولا علامات \$.
''';

  // ------------------------------------------------------- كروت / cards
  static const cardsSystem = '''
أنت بتعمل كروت مراجعة من محتوى دراسي.

$_grounding

هترجّع JSON بالشكل ده بالظبط:
{"cards":[{"front":"","back":""}]}

- "front": سؤال قصير ومحدد. مش عنوان ومش "اشرح كل حاجة عن...".
- "back": الإجابة في سطر أو اتنين. دقيقة ومختصرة.
- كارت لكل فكرة. الفكرة اللي محتاجة صفحة إجابة اتقسم لكروت.
- التعريفات والقوانين والفروق والخطوات هي أنفع حاجة تتعمل كروت.
- متعملش كارت لمعلومة تنظيمية (مواعيد، أسماء ملفات، كلام المحاضر الجانبي).
''';

  static String cardsPrompt(String source, int count) => '''
اعمل حوالي $count كارت مراجعة من المحتوى ده:

$source
''';

  // ------------------------------------------------------- اسأل / ask
  static const askSystem = '''
أنت بتجاوب على أسئلة طالب في محتوى محاضرة موجود قدامك.

$_grounding
- جاوب على قد السؤال. لو السؤال عن تعريف، ادي التعريف مش المحاضرة كلها.
- لو الطالب فهم غلط، صحّح له بالمحتوى نفسه.
- من غير مقدمات زي "بناءً على المحتوى" — ادخل في الإجابة على طول.
''';

  static String askPrompt({
    required String source,
    required String question,
    List<AskTurn> history = const [],
  }) {
    final buffer = StringBuffer()
      ..writeln('### محتوى المحاضرة:')
      ..writeln()
      ..writeln(source.trim())
      ..writeln();

    if (history.isNotEmpty) {
      buffer.writeln('### اللي اتسأل قبل كده:');
      for (final turn in history) {
        buffer.writeln('س: ${turn.question}');
        buffer.writeln('ج: ${turn.answer}');
      }
      buffer.writeln();
    }

    buffer
      ..writeln('### السؤال:')
      ..writeln(question.trim());
    return buffer.toString();
  }

  // ---------------------------------------------------- امتحان / exam
  static const examSystem = '''
أنت بتعمل امتحان تجريبي من محتوى محاضرة.

$_grounding

هترجّع JSON بالشكل ده بالظبط:
{"questions":[{"question":"","choices":["","","",""],"answer":0,"model_answer":""}]}

- سؤال الاختيار من متعدد: 4 اختيارات، و"answer" رقم الاختيار الصح (يبدأ من 0).
- السؤال المقالي: سيب "choices" فاضية واكتب الإجابة النموذجية في "model_answer".
- الاختيارات الغلط لازم تكون معقولة — مش واضح إنها غلط من أول نظرة.
- الأسئلة تغطي المحتوى كله مش أول جزء بس.
- متسألش عن حاجة مش في المحتوى.
''';

  static String examPrompt({
    required String source,
    required int choiceCount,
    required int writtenCount,
  }) =>
      '''
اعمل امتحان من $choiceCount سؤال اختيار من متعدد و $writtenCount سؤال مقالي على المحتوى ده:

$source
''';

  static const gradeSystem = '''
أنت بتصحح إجابات طالب على أسئلة مقالية.

$_grounding

هترجّع JSON بالشكل ده بالظبط:
{"marks":[{"index":0,"score":0.0,"comment":""}],"weak":[""],"advice":""}

- "score": من 0 لـ 1. الإجابة الصح الناقصة تاخد نص الدرجة مش صفر.
- "comment": سطر واحد يقول الناقص إيه بالظبط. مش "إجابة جيدة".
- "weak": المواضيع اللي الإجابات بتقول إنها محتاجة مراجعة، من المحتوى نفسه.
- "advice": سطر واحد عملي: يذاكر إيه تاني.
''';

  static String gradePrompt({
    required String source,
    required List<({int index, String question, String expected, String answer})>
        answers,
  }) {
    final buffer = StringBuffer()
      ..writeln('### محتوى المحاضرة:')
      ..writeln()
      ..writeln(source.trim())
      ..writeln()
      ..writeln('### الأسئلة وإجابات الطالب:');

    for (final a in answers) {
      buffer
        ..writeln()
        ..writeln('[${a.index}] السؤال: ${a.question}');
      if (a.expected.trim().isNotEmpty) {
        buffer.writeln('الإجابة النموذجية: ${a.expected.trim()}');
      }
      buffer.writeln('إجابة الطالب: ${a.answer.trim().isEmpty ? '(سابها فاضية)' : a.answer.trim()}');
    }

    buffer.writeln();
    buffer.writeln('صحّح كل إجابة ورجّع الشكل المطلوب.');
    return buffer.toString();
  }

  // -------------------------------------------------------- خطة / plan
  static const planSystem = '''
أنت بتعمل خطة مذاكرة أسبوعية لطالب.

هترجّع JSON بالشكل ده بالظبط:
{"days":[{"day":"","items":[{"what":"","minutes":0,"why":""}]}],"note":""}

- "day": اسم اليوم بالعربي كامل (السبت، الأحد، الاثنين، الثلاثاء، الأربعاء، الخميس، الجمعة).
- "what": حاجة واحدة محددة يعملها. مش "ذاكر فيزياء" — "راجع كروت الفصل التاني".
- "minutes": من 20 لـ 90. الجلسة الأطول من كده مش بتتعمل.
- "why": سبب قصير (امتحان قريب، كروت مستحقة، محاضرة بكرة).

قواعد:
- ابنِ الخطة على المعطيات اللي هتشوفها: الجدول، المهام المفتوحة، الكروت المستحقة.
- سيب اليوم اللي فيه محاضرات كتير أخف.
- المذاكرة قبل المحاضرة للمواد اللي ليها محاضرة قريبة، والمراجعة بعدها.
- متحطش أكتر من 3 ساعات في اليوم.
- اليوم الفاضي سيبه فاضي بدل ما تحشيه.
- "note": سطر واحد يشرح المنطق العام.
''';
}
