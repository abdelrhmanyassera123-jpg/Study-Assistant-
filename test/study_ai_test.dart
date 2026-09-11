import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/study_ai/study_ai.dart';

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
}
