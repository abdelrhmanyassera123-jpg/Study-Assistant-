import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/widgets/study_text.dart';

/// بيجمع كل النص المعروض فعلاً على الشاشة.
/// Collects every piece of text actually painted on screen.
String rendered(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.allWidgets) {
    if (widget is Text) {
      final span = widget.textSpan;
      buffer.write(span != null ? span.toPlainText() : (widget.data ?? ''));
    } else if (widget is RichText) {
      buffer.write(widget.text.toPlainText());
    }
  }
  return buffer.toString();
}

Future<void> show(WidgetTester tester, String text) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: StudyText(text))),
  ));
}

/// بيدوّر على أول span بالنص ده ويرجّع نمطه.
/// Finds the first span with this text and returns its style.
TextStyle? styleOf(WidgetTester tester, String needle) {
  TextStyle? found;
  for (final widget in tester.allWidgets) {
    if (widget is! RichText) continue;
    widget.text.visitChildren((span) {
      if (span is TextSpan && span.text == needle) {
        found = span.style;
        return false;
      }
      return true;
    });
    if (found != null) break;
  }
  return found;
}

void main() {
  group('markdown markers', () {
    // الموديل بيكتب ** و ### من نفسه. عرضها خام معناه إن الطالب بيقرا العلامات.
    // The model writes ** and ### of its own accord. Showing them raw means the
    // student reads the markers.
    testWidgets('bold markers do not reach the screen', (tester) async {
      await show(tester, 'القانون **مهم جدًا** في الامتحان');

      final text = rendered(tester);
      expect(text, contains('مهم جدًا'));
      expect(text, isNot(contains('**')));
    });

    testWidgets('bold text is actually bold', (tester) async {
      await show(tester, 'دي **القاعدة**');

      expect(styleOf(tester, 'القاعدة')?.fontWeight, FontWeight.w700);
    });

    testWidgets('heading hashes do not reach the screen', (tester) async {
      await show(tester, '### ملخص المحاضرة\nالكلام هنا');

      final text = rendered(tester);
      expect(text, contains('ملخص المحاضرة'));
      expect(text, isNot(contains('#')));
    });

    testWidgets('bullets become a bullet, not an asterisk', (tester) async {
      await show(tester, '*   أول نقطة\n*   تاني نقطة');

      final text = rendered(tester);
      expect(text, contains('•'));
      expect(text, contains('أول نقطة'));
      expect(text, isNot(contains('*')));
    });

    testWidgets('dashes become bullets too', (tester) async {
      await show(tester, '- نقطة بشرطة');

      expect(rendered(tester), contains('•'));
    });

    testWidgets('numbers keep their numbering', (tester) async {
      await show(tester, '1. الخطوة الأولى\n2. الخطوة التانية');

      final text = rendered(tester);
      expect(text, contains('1.'));
      expect(text, contains('2.'));
      expect(text, contains('الخطوة الأولى'));
    });
  });

  group('equations', () {
    testWidgets('LaTeX never reaches the screen', (tester) async {
      await show(tester, r'**القانون:** $KE = \frac{1}{2} m v^2$');

      final text = rendered(tester);
      expect(text, contains('KE = ½ m v²'));
      expect(text, isNot(contains(r'\frac')));
      expect(text, isNot(contains(r'$')));
    });

    testWidgets('an equation inside a bullet is converted too', (tester) async {
      await show(tester, r'*   القدرة: $P = \frac{W}{t}$');

      expect(rendered(tester), contains('P = W/t'));
    });
  });

  group('plain text', () {
    testWidgets('comes through word for word', (tester) async {
      const text = 'الجسم الساكن يفضل ساكن لحد ما قوة تأثر عليه.';
      await show(tester, text);

      expect(rendered(tester), contains(text));
    });

    testWidgets('empty text renders nothing at all', (tester) async {
      await show(tester, '   \n\n  ');

      expect(rendered(tester), isEmpty);
    });
  });
}
