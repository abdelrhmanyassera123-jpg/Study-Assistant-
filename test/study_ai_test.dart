import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/study_ai/study_ai.dart';
import 'package:study_assistant/features/summarize/style_profile.dart';
import 'package:study_assistant/features/summarize/summarizer.dart';

void main() {
  group('generated cards', () {
    test('a card needs both sides', () {
      expect(
        GeneratedCard.fromJson({'front': 'إيه هو الجهد؟', 'back': 'فرق الكمون'}),
        isNotNull,
      );
      expect(GeneratedCard.fromJson({'front': 'إيه هو الجهد؟'}), isNull);
      expect(GeneratedCard.fromJson({'back': 'فرق الكمون'}), isNull);
      expect(GeneratedCard.fromJson({'front': '  ', 'back': 'x'}), isNull);
    });

    // الموديل بيبدّل بين front/back و q/a من نداء للتاني، والكارت اللي بيتشال
    // بسبب اسم مفتاح هو كارت ضاع من غير سبب.
    // The model alternates between front/back and q/a from one call to the
    // next, and a card dropped over a key's name is a card lost for nothing.
    test('either key naming is accepted', () {
      final card = GeneratedCard.fromJson({'q': 'السؤال', 'a': 'الإجابة'});

      expect(card, isNotNull);
      expect(card!.front, 'السؤال');
      expect(card.back, 'الإجابة');
    });
  });

  group('exam questions', () {
    test('a choice question keeps its options and its answer', () {
      final q = ExamQuestion.fromJson({
        'question': 'وحدة قياس الجهد؟',
        'choices': ['أمبير', 'فولت', 'أوم', 'وات'],
        'answer': 1,
      });

      expect(q, isNotNull);
      expect(q!.isChoice, isTrue);
      expect(q.choices, hasLength(4));
      expect(q.answerIndex, 1);
    });

    // إجابة بره المدى معناها إن الموديل غلط في الترقيم؛ السؤال بيتحول لمقالي
    // بدل ما يتعرض باختيار صح وهمي.
    // An answer out of range means the model mis-numbered; the question becomes
    // a written one rather than showing a fake right choice.
    test('an out-of-range answer drops the choices', () {
      final q = ExamQuestion.fromJson({
        'question': 'س',
        'choices': ['أ', 'ب'],
        'answer': 5,
      });

      expect(q!.isChoice, isFalse);
      expect(q.choices, isEmpty);
    });

    test('a written question carries the model answer', () {
      final q = ExamQuestion.fromJson({
        'question': 'اشرح قانون أوم',
        'model_answer': 'الجهد = التيار × المقاومة',
      });

      expect(q, isNotNull);
      expect(q!.isChoice, isFalse);
      expect(q.modelAnswer, 'الجهد = التيار × المقاومة');
    });

    test('a question without text is refused', () {
      expect(ExamQuestion.fromJson({'choices': ['أ', 'ب'], 'answer': 0}), isNull);
    });
  });

  group('marking', () {
    test('a score outside 0..1 is pulled back into range', () {
      expect(WrittenMark.fromJson({'index': 0, 'score': 1.6})!.score, 1);
      expect(WrittenMark.fromJson({'index': 0, 'score': -2})!.score, 0);
    });

    test('a mark without a question number is refused', () {
      expect(WrittenMark.fromJson({'score': 0.5}), isNull);
    });

    test('a missing score counts as zero, not as full marks', () {
      expect(WrittenMark.fromJson({'index': 1})!.score, 0);
    });
  });

  group('plan items', () {
    test('an item needs something to do', () {
      expect(PlanItem.fromJson({'minutes': 30}), isNull);
      expect(PlanItem.fromJson({'what': 'راجع الفصل الأول'}), isNotNull);
    });

    // جلسة 6 ساعات مش خطة، ودقيقتين مش جلسة. المدى بيمنع الاتنين.
    // A six-hour sitting is not a plan and two minutes is not a session; the
    // range rules out both.
    test('minutes are held inside a workable range', () {
      expect(PlanItem.fromJson({'what': 'x', 'minutes': 600})!.minutes, 240);
      expect(PlanItem.fromJson({'what': 'x', 'minutes': 1})!.minutes, 5);
      expect(PlanItem.fromJson({'what': 'x'})!.minutes, 30);
    });
  });

  group('plan totals', () {
    test('a day sums its own items', () {
      const day = PlanDay(weekday: 6, items: [
        PlanItem(what: 'أ', minutes: 30),
        PlanItem(what: 'ب', minutes: 45),
      ]);

      expect(day.totalMinutes, 75);
    });

    test('a plan sums its days', () {
      const plan = StudyPlan(days: [
        PlanDay(weekday: 6, items: [PlanItem(what: 'أ', minutes: 30)]),
        PlanDay(weekday: 7, items: [PlanItem(what: 'ب', minutes: 20)]),
      ]);

      expect(plan.totalMinutes, 50);
      expect(plan.isEmpty, isFalse);
    });

    test('a plan of empty days is empty', () {
      const plan = StudyPlan(days: [PlanDay(weekday: 6, items: [])]);
      expect(plan.isEmpty, isTrue);
    });
  });

  group('prompts', () {
    // القاعدة دي هي اللي بتفرق بين مساعد مذاكرة وبين موديل بيتكلم من عنده.
    // This rule is what separates a study assistant from a model talking from
    // its own memory.
    test('every prompt says the material is the only source', () {
      for (final system in [
        StudyAiPrompts.cardsSystem,
        StudyAiPrompts.askSystem,
        StudyAiPrompts.examSystem,
      ]) {
        expect(system, contains('المصدر الوحيد'));
        expect(system, contains('تخترع'));
      }
    });

    test('the question and the material both reach the ask prompt', () {
      final prompt = StudyAiPrompts.askPrompt(
        source: 'الجهد = التيار × المقاومة',
        question: 'يعني إيه مقاومة؟',
      );

      expect(prompt, contains('الجهد = التيار × المقاومة'));
      expect(prompt, contains('يعني إيه مقاومة؟'));
    });

    test('earlier turns are carried into a follow-up question', () {
      final prompt = StudyAiPrompts.askPrompt(
        source: 'محتوى',
        question: 'وليه؟',
        history: const [AskTurn(question: 'إيه ده؟', answer: 'ده قانون أوم')],
      );

      expect(prompt, contains('إيه ده؟'));
      expect(prompt, contains('ده قانون أوم'));
    });

    test('an unanswered question is still sent for marking', () {
      final prompt = StudyAiPrompts.gradePrompt(
        source: 'محتوى',
        answers: [
          (index: 0, question: 'س', expected: 'ج', answer: '   '),
        ],
      );

      expect(prompt, contains('سابها فاضية'));
    });
  });

  group('explain and review pages', () {
    const profile = StyleProfile();

    // الشرح بيضيف أمثلة من برّه، فلازم تتعلّم — وإلا الطالب يكتبها في
    // الامتحان على إنها من المنهج.
    // The explanation adds outside examples, so they must be marked, or the
    // student writes them in the exam as syllabus.
    test('outside examples in an explanation are marked', () {
      for (final level in ExplainLevel.values) {
        final system = VisualPrompts.blocksSystem(
          profile,
          kind: StudyOutput.explain,
          level: level,
        );
        expect(system, contains('💡 للتوضيح'));
        expect(system, contains('من المحاضرة بس'));
        expect(system, isNot(contains('متخترعش معلومة ولا مثال')));
      }
    });

    test('each level asks for a different depth', () {
      final texts = {
        for (final level in ExplainLevel.values) StudyAiPrompts.explainRules(level),
      };
      expect(texts, hasLength(ExplainLevel.values.length));
    });

    // التلاتة بيترسموا ورق: نفس شكل الـ JSON ونفس البلوكات.
    // All three are drawn as paper: the same JSON shape and the same blocks.
    test('every kind is answered in the same page blocks', () {
      for (final kind in StudyOutput.values) {
        final system = VisualPrompts.blocksSystem(profile, kind: kind);
        expect(system, contains('"blocks"'));
        expect(system, contains('"diagram"'));
      }
    });

    test('the review keeps to the material and ends on likely questions', () {
      final system = VisualPrompts.blocksSystem(profile, kind: StudyOutput.review);
      expect(system, contains('أسئلة متوقعة'));
      expect(system, contains('متخترعش معلومة ولا مثال'));
    });

    test('the summary prompt is unchanged by the new kinds', () {
      final system = VisualPrompts.blocksSystem(profile);
      expect(system, startsWith('أنت بتلخص'));
      expect(system, isNot(contains('💡 للتوضيح')));
    });

    test('the lecture prompt asks for the chosen kind', () {
      String ask(StudyOutput kind) =>
          StudyPrompt.build(lectureText: 'قانون أوم', samples: const [], kind: kind);
      expect(ask(StudyOutput.summary), contains('لخّص'));
      expect(ask(StudyOutput.explain), contains('اشرح'));
      expect(ask(StudyOutput.review), contains('ورقة مراجعة'));
      expect(ask(StudyOutput.explain), contains('قانون أوم'));
    });
  });

  group('solving a question', () {
    // الدكتور بيصحح على طريقته: لو فيه محاضرة، الحل لازم يمشي عليها.
    // The lecturer marks by their own method: with a lecture, the solution
    // must follow it.
    test('with a lecture, the solution follows its method and says where', () {
      final system = StudyAiPrompts.solveSystem(withLecture: true, arabic: true);
      expect(system, contains('طريقتها'));
      expect(system, contains('📖 من المحاضرة:'));
      expect(system, contains('⚠️ مش من المحاضرة'));
    });

    test('without one, it solves the usual way and flags assumptions', () {
      final system = StudyAiPrompts.solveSystem(withLecture: false, arabic: true);
      expect(system, isNot(contains('📖 من المحاضرة:')));
      expect(system, contains('افترضته'));
    });

    test('every solution starts by making the question clear', () {
      final system = StudyAiPrompts.solveSystem(withLecture: false, arabic: true);
      expect(system.indexOf('## فهم السؤال'), lessThan(system.indexOf('## الحل خطوة بخطوة')));
      expect(system, contains('## الإجابة'));
    });

    test('the prompt says which attachments are the question and which the lecture', () {
      final prompt = StudyAiPrompts.solvePrompt(question: '', questionImages: 2, lectureFiles: 1);
      expect(prompt, contains('(السؤال في الصور المرفقة)'));
      expect(prompt, contains('أول 2 ملف مرفق صور السؤال'));
      expect(prompt, contains('والـ 1 اللي بعدهم المحاضرة'));
    });

    // صورة اتلصقت في خانة المتابعة من غير كلام: السؤال هو الصورة.
    // A picture pasted into the follow-up box with no words: the picture is
    // the question.
    test('a follow-up can be just a pasted picture', () {
      final prompt = StudyAiPrompts.solvePrompt(
        question: 'احسب التيار',
        history: const [AskTurn(question: 'احسب التيار', answer: 'I = 2 A')],
        followUpImages: 1,
      );
      expect(prompt, contains('(السؤال في الصورة المرفقة)'));
      expect(prompt, contains('مرفق معاه 1 صورة'));
    });

    test('a follow-up carries the earlier solution and the new question', () {
      final prompt = StudyAiPrompts.solvePrompt(
        question: 'احسب التيار',
        lectureText: 'V = I × R',
        history: const [AskTurn(question: 'احسب التيار', answer: 'I = V / R = 2 A')],
        followUp: 'ليه قسمنا؟',
      );
      expect(prompt, contains('### الحل اللي اتشرح:'));
      expect(prompt, contains('I = V / R = 2 A'));
      expect(prompt, contains('ليه قسمنا؟'));
      expect(prompt, contains('V = I × R'));
    });
  });
}
