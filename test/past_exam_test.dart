import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/past_exams/past_exam.dart';

PastQuestion _q(String topic, String exam, {String lecture = ''}) =>
    PastQuestion(question: 'س', kind: 'written', topic: topic, examLabel: exam, lecture: lecture);

void main() {
  test('a topic counts each exam once, however many questions it had', () {
    final topics = hotTopics([
      _q('الغدة النكفية', '2023'),
      _q('الغدة النكفية', '2023'),
      _q('الغدة النكفية', '2023'),
      _q('اللسان', '2023'),
      _q('اللسان', '2024'),
    ]);
    expect(topics.first.topic, 'اللسان');
    expect(topics.first.exams, 2);
    expect(topics.last.exams, 1);
    expect(topics.last.questions, 3);
  });

  test('topics match despite spacing and case', () {
    final topics = hotTopics([_q('Salivary  glands', 'a'), _q('salivary glands', 'b')]);
    expect(topics, hasLength(1));
    expect(topics.single.exams, 2);
  });

  test('a question with choices is multiple choice even if the model said written', () {
    final q = PastQuestion.fromModel(
      {'question': 'اختار', 'kind': 'written', 'choices': ['أ', 'ب', '']},
      'final',
    )!;
    expect(q.isChoice, isTrue);
    expect(q.choices, ['أ', 'ب']);
  });

  test('an empty question is dropped', () {
    expect(PastQuestion.fromModel({'question': '  '}, 'x'), isNull);
  });
}
