library;

import 'package:flutter/material.dart';

/// بيرسم الأسس والسفلية اللي يونيكود مالهاش شكل جاهز ليها.
/// Draws the superscripts and subscripts Unicode has no ready glyph for.
///
/// `v²` و`v₀` موجودين في يونيكود، لكن `γ^μ` و`ω_a^{bc}` مش موجودين — يونيكود
/// فيه أرقام مرفوعة وشوية حروف لاتينية وبس. المحوّل بيسيبهم بعلامتهم (`^μ`)،
/// وهنا بيتحولوا لنص صغير مرفوع فعلاً.
/// `v²` and `v₀` exist in Unicode, but `γ^μ` and `ω_a^{bc}` do not — Unicode
/// has raised digits and a handful of Latin letters, no more. The converter
/// leaves those with their marker (`^μ`), and here they become genuinely
/// raised, smaller text.
///
/// معادلات الفيزياء المتقدمة كلها أسس بحروف يونانية، فمن غير ده التلخيص بيبقى
/// مليان `^` و`_` ومش مقروء.
/// Advanced physics is all Greek-lettered indices, so without this a summary
/// fills up with `^` and `_` and stops being readable.

/// الحروف اللي بنقبلها كأس أو سفلية بعد العلامة.
/// The characters accepted as a script after the marker.
///
/// لاتيني وأرقام ويوناني بس: الشرطة السفلية في نص عربي عادي مش علامة رياضية.
/// Latin, digits and Greek only: an underscore in ordinary Arabic text is not a
/// mathematical marker.
const _scriptable = r'A-Za-z0-9Ͱ-Ͽ′';

final _pattern = RegExp(
  r'\^\(([^)]{1,12})\)'
  '|\\^([$_scriptable])'
  r'|_\(([^)]{1,12})\)'
  '|_([$_scriptable])',
);

/// بيحوّل نص لأجزاء، والأسس فيه مرفوعة والسفلية منزّلة.
/// Turns text into spans with the superscripts raised and subscripts lowered.
List<InlineSpan> mathSpans(String text, TextStyle base) {
  if (!text.contains('^') && !text.contains('_')) {
    return [TextSpan(text: text, style: base)];
  }

  final size = base.fontSize ?? 14;
  final spans = <InlineSpan>[];
  var index = 0;

  for (final match in _pattern.allMatches(text)) {
    if (match.start > index) {
      spans.add(TextSpan(text: text.substring(index, match.start), style: base));
    }

    final up = match.group(1) ?? match.group(2);
    final down = match.group(3) ?? match.group(4);
    spans.add(_script(up ?? down!, base, size, raised: up != null));
    index = match.end;
  }

  if (index < text.length) {
    spans.add(TextSpan(text: text.substring(index), style: base));
  }
  return spans;
}

InlineSpan _script(
  String content,
  TextStyle base,
  double size, {
  required bool raised,
}) {
  return WidgetSpan(
    alignment: PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: Transform.translate(
      // الرفع نسبة من حجم الخط مش رقم ثابت، عشان يفضل مظبوط مع تكبير النص.
      // The lift is a fraction of the font size rather than a fixed number, so
      // it stays right when the reader enlarges the text.
      offset: Offset(0, raised ? -size * 0.34 : size * 0.16),
      child: Text(
        content,
        textDirection: TextDirection.ltr,
        style: base.copyWith(fontSize: size * 0.72),
      ),
    ),
  );
}

/// نص جاهز فيه معادلات — بيرسم الأسس صح.
/// A ready piece of text with equations, drawing its indices properly.
class MathText extends StatelessWidget {
  const MathText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    return Text.rich(
      TextSpan(children: mathSpans(text, base)),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
  }
}
