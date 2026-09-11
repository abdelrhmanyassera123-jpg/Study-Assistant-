import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../widgets/common.dart';
import 'ask_page.dart';
import 'card_maker.dart';
import 'exam_page.dart';

/// الأدوات اللي بتشتغل على محتوى محاضرة واحدة.
/// The tools that work on one lecture's material.
///
/// نفس الصف بيظهر في كل مكان فيه محتوى — التلخيص والملاحظة — عشان "اسأل" و
/// "امتحان" ما يبقوش مدفونين في شاشة واحدة.
/// The same row appears wherever material lives — a summary, a note — so
/// "ask" and "exam" are not buried in one screen.
class StudyToolsRow extends ConsumerWidget {
  const StudyToolsRow({
    super.key,
    required this.title,
    required this.source,
    this.subjectId,
  });

  final String title;
  final String source;
  final String? subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;

    // المحتوى القصير مش هيطلّع كروت ولا أسئلة، والزرار اللي بيفشل أسوأ من
    // زرار مش موجود.
    // Short material yields neither cards nor questions, and a button that
    // fails is worse than one that is not there.
    if (source.trim().length < 40) return const SizedBox.shrink();

    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: [
        OutlinedButton.icon(
          onPressed: () =>
              openCardMaker(context, ref, source: source, subjectId: subjectId),
          icon: const Icon(Icons.style_rounded, size: 18),
          label: Text(l.makeCards),
        ),
        OutlinedButton.icon(
          onPressed: () => openAskPage(context, title: title, source: source),
          icon: const Icon(Icons.forum_rounded, size: 18),
          label: Text(l.askLecture),
        ),
        OutlinedButton.icon(
          onPressed: () => openExamPage(context, title: title, source: source),
          icon: const Icon(Icons.fact_check_rounded, size: 18),
          label: Text(l.mockExam),
        ),
      ],
    );
  }
}

/// نفس الأدوات كعنوان قسم — للصفحات اللي فيها مساحة.
/// The same tools under a heading, for pages with room for one.
class StudyToolsSection extends StatelessWidget {
  const StudyToolsSection({
    super.key,
    required this.title,
    required this.source,
    this.subjectId,
  });

  final String title;
  final String source;
  final String? subjectId;

  @override
  Widget build(BuildContext context) {
    if (source.trim().length < 40) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l.studyAi),
        StudyToolsRow(title: title, source: source, subjectId: subjectId),
      ],
    );
  }
}
