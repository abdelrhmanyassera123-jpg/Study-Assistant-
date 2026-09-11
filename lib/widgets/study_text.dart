import 'package:flutter/material.dart';

import '../core/design.dart';
import '../core/math_text.dart';
import 'math_spans.dart';

/// بيعرض نص الموديل زي ما هو مقصود منه.
/// Renders the model's text the way it was meant to be read.
///
/// الموديل بيكتب ماركداون ومعادلات LaTeX من نفسه — عناوين بـ `###`، وتعليم
/// بـ `**`، ومعادلات بين `$`. عرضها كنص خام معناه إن الطالب بيشوف العلامات بدل
/// الكلام. الويدجت دي بتحوّل المعادلات ليونيكود وبتقرا الماركداون البسيط.
/// The model writes Markdown and LaTeX of its own accord — headings with
/// `###`, emphasis with `**`, equations between `$`. Showing that raw means the
/// student reads the markers instead of the words. This widget converts the
/// equations to Unicode and reads the light Markdown.
class StudyText extends StatelessWidget {
  const StudyText(
    this.text, {
    super.key,
    this.style,
    this.selectable = true,
  });

  final String text;
  final TextStyle? style;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.bodyMedium!;
    final lines = readableMath(text).split('\n');

    final blocks = <Widget>[];
    var blankRun = 0;

    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        blankRun++;
        continue;
      }
      // سطر فاضي واحد بين الفقرات كفاية — الموديل بيحط اتنين وتلاتة.
      // One blank line between paragraphs is enough; the model writes two or
      // three.
      if (blocks.isNotEmpty && blankRun > 0) {
        blocks.add(const SizedBox(height: Insets.md));
      }
      blankRun = 0;
      blocks.add(_block(context, line, base));
    }

    if (blocks.isEmpty) return const SizedBox.shrink();

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: blocks,
    );

    // التحديد بيلف العمود كله عشان النسخ ياخد الفقرات مع بعض.
    // Selection wraps the whole column so copying takes the paragraphs together.
    return selectable ? SelectionArea(child: column) : column;
  }

  Widget _block(BuildContext context, String line, TextStyle base) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // عنوان: # لحد ######
    // A heading: # through ######
    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final style = level <= 2
          ? text.titleMedium
          : level == 3
              ? text.titleSmall
              : base.copyWith(fontWeight: FontWeight.w700);
      return Padding(
        padding: EdgeInsets.only(top: Insets.md, bottom: Insets.sm),
        child: Text.rich(_spans(heading.group(2)!, style ?? base, scheme)),
      );
    }

    // نقطة: - أو * أو •
    // A bullet: -, * or •
    final bullet = RegExp(r'^\s*[-*•]\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      return _listRow(context, '•', bullet.group(1)!, base, scheme);
    }

    // ترقيم: 1. أو 1)
    // A number: 1. or 1)
    final numbered = RegExp(r'^\s*(\d{1,2})[.)]\s+(.*)$').firstMatch(line);
    if (numbered != null) {
      return _listRow(
        context,
        '${numbered.group(1)}.',
        numbered.group(2)!,
        base,
        scheme,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xs),
      child: Text.rich(_spans(line, base, scheme)),
    );
  }

  Widget _listRow(
    BuildContext context,
    String marker,
    String body,
    TextStyle base,
    ColorScheme scheme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              marker,
              style: base.copyWith(color: scheme.primary),
            ),
          ),
          Expanded(child: Text.rich(_spans(body, base, scheme))),
        ],
      ),
    );
  }

  /// بيقرا التعليم داخل السطر: **عريض** و`كود`.
  /// Reads the inline emphasis: **bold** and `code`.
  ///
  /// المائل بـ `_` مش مدعوم بقصد: الشرطة السفلية بتيجي في أسماء المتغيرات
  /// (`v_f`) أكتر ما بتيجي كتنسيق.
  /// Italics with `_` are deliberately unsupported: an underscore turns up in
  /// variable names (`v_f`) far more often than as formatting.
  TextSpan _spans(String line, TextStyle base, ColorScheme scheme) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\*(.+?)\*');
    var index = 0;

    for (final match in pattern.allMatches(line)) {
      if (match.start > index) {
        spans.addAll(mathSpans(line.substring(index, match.start), base));
      }
      if (match.group(1) != null) {
        spans.addAll(mathSpans(
          match.group(1)!,
          base.copyWith(fontWeight: FontWeight.w700),
        ));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(
          text: match.group(2),
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ));
      } else {
        spans.addAll(mathSpans(
          match.group(3)!,
          base.copyWith(fontStyle: FontStyle.italic),
        ));
      }
      index = match.end;
    }

    if (index < line.length) {
      spans.addAll(mathSpans(line.substring(index), base));
    }
    return TextSpan(style: base, children: spans);
  }
}
