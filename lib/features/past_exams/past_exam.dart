import 'package:flutter/foundation.dart';

/// سؤال من امتحان قديم.
/// A question from an old exam.
@immutable
class PastQuestion {
  const PastQuestion({
    this.id = '',
    required this.question,
    required this.kind,
    this.choices = const [],
    this.answer = '',
    this.lecture = '',
    this.topic = '',
    this.examLabel = '',
  });

  final String id;
  final String question;

  /// choice | written
  final String kind;
  final List<String> choices;
  final String answer;

  /// عنوان المحاضرة اللي السؤال جاي منها، فاضي لو ماتعرفش.
  /// The lecture the question comes from; empty when unknown.
  final String lecture;

  /// الموضوع في كلمتين — ده اللي بيتعدّ عشان نعرف إيه اللي بيتكرر.
  /// The topic in a few words; this is what gets counted to find repeats.
  final String topic;
  final String examLabel;

  bool get isChoice => kind == 'choice';

  static PastQuestion? fromModel(Map<String, dynamic> m, String examLabel) {
    final question = '${m['question'] ?? ''}'.trim();
    if (question.isEmpty) return null;
    final choices = (m['choices'] as List? ?? const [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return PastQuestion(
      question: question,
      kind: choices.length >= 2 || m['kind'] == 'choice' ? 'choice' : 'written',
      choices: choices,
      answer: '${m['answer'] ?? ''}'.trim(),
      lecture: '${m['lecture'] ?? ''}'.trim(),
      topic: '${m['topic'] ?? ''}'.trim(),
      examLabel: examLabel,
    );
  }

  factory PastQuestion.fromRow(Map<String, dynamic> m) => PastQuestion(
        id: m['id'] as String,
        question: (m['question'] as String?) ?? '',
        kind: (m['kind'] as String?) ?? 'written',
        choices: (m['choices'] as List? ?? const []).map((e) => '$e').toList(),
        answer: (m['answer'] as String?) ?? '',
        lecture: (m['lecture'] as String?) ?? '',
        topic: (m['topic'] as String?) ?? '',
        examLabel: (m['exam_label'] as String?) ?? '',
      );

  Map<String, dynamic> toInsert(String? subjectId) => {
        'subject_id': subjectId,
        'exam_label': examLabel,
        'question': question,
        'kind': kind,
        'choices': choices,
        'answer': answer,
        'lecture': lecture,
        'topic': topic,
      };

  /// السؤال كنص — بيتبعت للموديل كمثال لشكل الامتحان.
  /// The question as text, sent to the model as an example of the exam's
  /// shape.
  String toPlainText() {
    final b = StringBuffer('- [${isChoice ? 'اختياري' : 'كتابي'}] $question');
    for (var i = 0; i < choices.length; i++) {
      b.write('\n   ${i + 1}) ${choices[i]}');
    }
    return b.toString();
  }
}

/// موضوع بيتكرر: اتسأل في كام امتحان من كام.
/// A recurring topic: asked in how many exams out of how many.
@immutable
class HotTopic {
  const HotTopic({
    required this.topic,
    required this.lecture,
    required this.exams,
    required this.questions,
  });

  final String topic;
  final String lecture;

  /// عدد الامتحانات المختلفة اللي جه فيها — مش عدد الأسئلة، عشان امتحان واحد
  /// فيه 3 أسئلة على نفس الحاجة ما يبانش إنه بيتكرر كل سنة.
  /// How many different exams it appeared in, not how many questions — so one
  /// exam with three questions on the same thing does not look like a yearly
  /// repeat.
  final int exams;
  final int questions;
}

/// الموضوعات مرتبة باللي بيتكرر في امتحانات أكتر.
/// Topics ordered by how many exams they recur in.
List<HotTopic> hotTopics(List<PastQuestion> questions) {
  String norm(String t) => t.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  final byTopic = <String, List<PastQuestion>>{};
  for (final q in questions) {
    final key = norm(q.topic.isEmpty ? q.lecture : q.topic);
    if (key.isEmpty) continue;
    byTopic.putIfAbsent(key, () => []).add(q);
  }

  final topics = [
    for (final group in byTopic.values)
      HotTopic(
        topic: group.first.topic.isEmpty ? group.first.lecture : group.first.topic,
        lecture: group.map((q) => q.lecture).firstWhere((l) => l.isNotEmpty, orElse: () => ''),
        exams: group.map((q) => q.examLabel).toSet().length,
        questions: group.length,
      ),
  ]..sort((a, b) {
      final byExams = b.exams.compareTo(a.exams);
      return byExams != 0 ? byExams : b.questions.compareTo(a.questions);
    });
  return topics;
}
