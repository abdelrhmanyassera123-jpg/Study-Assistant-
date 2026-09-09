import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/summarize/style_profile.dart';

StyleProfile profileWith(List<String> colors) =>
    StyleProfile.fromJson({'accent_colors': colors});

void main() {
  group('accent colours', () {
    test('reads hex, with or without the hash', () {
      final p = profileWith(['#C62828', '1565C0']);
      expect(p.accentColors, hasLength(2));
    });

    test('expands three-digit hex', () {
      expect(profileWith(['#c00']).accentColors.single.toARGB32(), 0xFFCC0000);
    });

    test('accepts colour names, which the model sometimes returns', () {
      // رد الموديل مش ثابت: مرة "#C62828" ومرة "red" — الرفض بيفضّي القايمة.
      // The model is inconsistent: "#C62828" one call, "red" the next.
      // Rejecting names empties the palette entirely.
      final p = profileWith(['red', 'blue', 'أصفر']);
      expect(p.accentColors, hasLength(3));
    });

    test('drops the paper and the ink, which are not accents', () {
      // الموديل بيسرد لون الورق ولون الحبر ضمن الألوان. لو اتاخدوا زي ما هما،
      // بيطلع عنوان أبيض على ورق أبيض أو أسود على أسود.
      // The model lists paper and ink among the colours. Taken literally they
      // give a white heading on white paper, or black on black.
      final p = profileWith(['#FFFFFF', '#FFFDF7', '#000000', '#C62828']);
      expect(p.accentColors, hasLength(1));
      expect(p.accentColors.single.computeLuminance(), lessThan(0.5));
    });

    test('darkens colours too pale to read on paper', () {
      final pale = profileWith(['#FFE082']).accentColors.single;
      expect(pale.computeLuminance(), lessThanOrEqualTo(0.55));
    });

    test('ignores values that are not colours at all', () {
      expect(profileWith(['', 'not a colour', '#12', '#GGGGGG']).accentColors, isEmpty);
    });

    test('falls back when the palette ends up empty', () {
      const fallback = Color(0xFF123456);
      expect(profileWith(['#FFFFFF']).colorAt(0, fallback), fallback);
    });

    test('cycles through the palette rather than running off the end', () {
      final p = profileWith(['#C62828', '#1565C0']);
      expect(p.colorAt(2, Colors.black), p.colorAt(0, Colors.black));
      expect(p.colorAt(5, Colors.black), p.colorAt(1, Colors.black));
    });
  });

  group('analysis parsing', () {
    test('reads one entry per page, in order', () {
      final a = StyleAnalysis.fromJson({
        'look': {'density': 'airy'},
        'pages': [
          {'title': 'قانون أوم', 'transcript': 'ا' * 60},
          {'title': 'قانون كيرشوف', 'transcript': 'ب' * 60},
        ],
      });

      expect(a.pages, hasLength(2));
      expect(a.pages.first.title, 'قانون أوم');
      expect(a.pages.last.title, 'قانون كيرشوف');
      expect(a.profile.density, 'airy');
    });

    test('skips pages whose transcript is too short to be a summary', () {
      final a = StyleAnalysis.fromJson({
        'pages': [
          {'title': 'كامل', 'transcript': 'ا' * 60},
          {'title': 'قراءة فاشلة', 'transcript': 'ااا'},
        ],
      });

      expect(a.pages, hasLength(2));
      expect(a.usablePages, hasLength(1));
      expect(a.usablePages.single.title, 'كامل');
    });

    test('still reads the older single-page shape', () {
      // الموديل بيخرج عن المخطط أحيانًا؛ الرد وقتها ما يضيعش.
      // The model strays from the schema sometimes; that reply isn't lost.
      final a = StyleAnalysis.fromJson({
        'accent_colors': ['#C62828'],
        'title': 'صفحة واحدة',
        'transcript': 'ا' * 60,
      });

      expect(a.usablePages, hasLength(1));
      expect(a.usablePages.single.title, 'صفحة واحدة');
      expect(a.profile.accentColors, hasLength(1));
    });

    test('survives a reply with no pages at all', () {
      final a = StyleAnalysis.fromJson({'look': {}});
      expect(a.usablePages, isEmpty);
    });
  });
}
