import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../core/math_text.dart';
import 'math_spans.dart';

/// نص فيه معادلات LaTeX بين `$...$` (جوه السطر) أو `$$...$$` (لوحدها)،
/// بيترسموا معادلات حقيقية: كسور فوق بعض، جذور، أسس.
/// Text with LaTeX between `$...$` (inline) or `$$...$$` (on its own line),
/// typeset as real equations: stacked fractions, roots, powers.
///
/// ده للصفحة المرسومة بس، اللي هي في الآخر صورة. أي نص بيتنسخ أو بيتحفظ
/// ملاحظة بيعدي على [readableMath] زي الأول، لأن LaTeX في رسالة أو ملاحظة
/// بيبان رموز.
/// This is for the drawn page only, which ends up as an image. Text that is
/// copied or saved as a note still goes through [readableMath], since LaTeX in
/// a message or a note shows up as raw markup.
class TexText extends StatelessWidget {
  const TexText(this.text, {super.key, this.style, this.textAlign});

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  static final _math = RegExp(r'\$\$([\s\S]+?)\$\$|\$([^$\n]+?)\$');

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final source = repairTex(text);
    if (!source.contains(r'$')) {
      return MathText(readableMath(source), style: base, textAlign: textAlign);
    }

    final spans = <InlineSpan>[];
    var index = 0;
    for (final m in _math.allMatches(source)) {
      if (m.start > index) {
        spans.addAll(mathSpans(readableMath(source.substring(index, m.start)), base));
      }
      final display = m.group(1) != null;
      spans.add(_equation((m.group(1) ?? m.group(2)!).trim(), base, display: display));
      index = m.end;
    }
    if (index < source.length) {
      spans.addAll(mathSpans(readableMath(source.substring(index)), base));
    }

    return Text.rich(TextSpan(children: spans), textAlign: textAlign);
  }

  InlineSpan _equation(String tex, TextStyle base, {required bool display}) {
    final size = base.fontSize ?? 15;
    final math = Math.tex(
      tex,
      mathStyle: display ? MathStyle.display : MathStyle.text,
      // وزن عادي دايمًا: الخط العريض بيحوّل المتغيرات لرموز متجهات.
      // Always normal weight: bold turns variables into vector notation.
      textStyle: base.copyWith(
        fontSize: size * (display ? 1.15 : 1.05),
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
      ),
      // معادلة مكسورة بترجع للتحويل النصي بدل ما تظهر رسالة خطأ حمرا.
      // A broken equation falls back to the plain conversion instead of a red
      // error message.
      onErrorFallback: (_) => Text(
        readableMath('\$$tex\$'),
        textDirection: TextDirection.ltr,
        style: base,
      ),
    );

    // المعادلة دايمًا شمال لليمين، حتى جوه سطر عربي.
    // An equation always reads left to right, even inside an Arabic line.
    final child = Directionality(
      textDirection: TextDirection.ltr,
      child: display
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: math,
                ),
              ),
            )
          : math,
    );

    return display
        ? WidgetSpan(child: SizedBox(width: double.infinity, child: child))
        : WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: child,
          );
  }
}

/// بيرجّع الـ backslash اللي ضاع في فك JSON.
/// Restores backslashes lost while decoding JSON.
///
/// لو الموديل كتب `"\frac"` في JSON من غير ما يضاعف الـ backslash، الفك بيقرا
/// `\f` كحرف تحكم ويفضل "rac" — ونفس الكلام لـ `\t`imes و`\b`eta و`\n`eq.
/// جوه المعادلة الحروف دي مستحيل تبقى مقصودة، فبترجع زي ما كانت.
/// If the model writes `"\frac"` in JSON without doubling the backslash,
/// decoding reads `\f` as a control character and leaves "rac" — likewise
/// `\t`imes, `\b`eta and `\n`eq. Inside an equation those characters can never
/// be intended, so they are turned back.
String repairTex(String text) {
  if (!text.contains(r'$')) return text;
  return text.replaceAllMapped(RegExp(r'\$\$[\s\S]*?\$\$|\$[^$]*\$'), (m) {
    return m[0]!
        .replaceAll('\f', r'\f')
        .replaceAll('\t', r'\t')
        .replaceAll('\b', r'\b')
        .replaceAll('\r', r'\r')
        .replaceAllMapped(RegExp(r'\n(?=[a-zA-Z])'), (_) => r'\n');
  });
}
