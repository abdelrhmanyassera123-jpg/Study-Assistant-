import 'dart:convert';

import 'package:flutter/material.dart';

/// الشكل البصري لتلخيصات المستخدم، مستخرج من صور كراسته.
/// The visual look of the user's summaries, read from photos of their notebook.
///
/// ده مكمّل لـ StyleSample مش بديل ليه: العينات بتعلّم الموديل *الكلام*،
/// والبروفايل بيعلّمه *الشكل*.
/// This complements StyleSample rather than replacing it: samples teach the
/// model the *words*, the profile teaches it the *look*.
@immutable
class StyleProfile {
  const StyleProfile({
    this.accentColors = const [],
    this.sectionOrder = const [],
    this.usesBoxes = true,
    this.usesNumbering = true,
    this.density = 'medium',
    this.notes = '',
  });

  /// ألوان المستخدم بالترتيب — الأول هو لون العناوين عادة.
  /// The user's colours in order; the first is usually the heading colour.
  final List<Color> accentColors;

  /// ترتيب الأقسام زي ما بيكتبها.
  /// The order they lay their sections out in.
  final List<String> sectionOrder;

  final bool usesBoxes;
  final bool usesNumbering;

  /// compact | medium | airy
  final String density;

  /// وصف حر للشكل — بيتبعت للموديل كتعليمات.
  /// A free-text description of the look, sent to the model as instructions.
  final String notes;

  bool get isEmpty => accentColors.isEmpty && sectionOrder.isEmpty && notes.isEmpty;

  Color colorAt(int index, Color fallback) =>
      accentColors.isEmpty ? fallback : accentColors[index % accentColors.length];

  static Color? _parseColor(Object? v) {
    if (v is! String) return null;
    final hex = v.replaceAll('#', '').trim();
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  factory StyleProfile.fromJson(Map<String, dynamic> m) => StyleProfile(
        accentColors: (m['accent_colors'] as List<dynamic>? ?? const [])
            .map(_parseColor)
            .whereType<Color>()
            .toList(),
        sectionOrder: (m['section_order'] as List<dynamic>? ?? const [])
            .map((e) => '$e')
            .where((e) => e.isNotEmpty)
            .toList(),
        usesBoxes: m['uses_boxes'] as bool? ?? true,
        usesNumbering: m['uses_numbering'] as bool? ?? true,
        density: (m['density'] as String?) ?? 'medium',
        notes: (m['notes'] as String?) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'accent_colors': [
          for (final c in accentColors)
            '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}',
        ],
        'section_order': sectionOrder,
        'uses_boxes': usesBoxes,
        'uses_numbering': usesNumbering,
        'density': density,
        'notes': notes,
      };

  /// وصف نصي بيتحط في البرومبت عشان التلخيص يطلع بنفس التخطيط.
  /// A prose description injected into the prompt so the summary comes out
  /// with the same layout.
  String asInstructions() {
    final b = StringBuffer();
    b.writeln('شكل تلخيصات الطالب (من صور كراسته):');
    if (sectionOrder.isNotEmpty) {
      b.writeln('- ترتيب الأقسام: ${sectionOrder.join(' ← ')}');
    }
    b.writeln('- بيستخدم مربعات/إطارات: ${usesBoxes ? "أيوه" : "لأ"}');
    b.writeln('- بيرقّم النقط: ${usesNumbering ? "أيوه" : "لأ"}');
    b.writeln('- كثافة الصفحة: $density');
    if (notes.trim().isNotEmpty) b.writeln('- ملاحظات: ${notes.trim()}');
    return b.toString();
  }
}

/// نوع البلوك في الصفحة المرسومة.
/// The kind of block on the rendered page.
enum BlockType { heading, box, bullets, numbered, highlight, note, divider }

/// وحدة واحدة من التلخيص المرسوم.
/// One unit of the rendered summary.
@immutable
class SummaryBlock {
  const SummaryBlock({
    required this.type,
    this.title = '',
    this.text = '',
    this.items = const [],
    this.colorIndex = 0,
  });

  final BlockType type;
  final String title;
  final String text;
  final List<String> items;

  /// مؤشر على ألوان البروفايل بدل لون ثابت — عشان الصفحة تفضل بألوان المستخدم.
  /// Indexes into the profile's colours instead of hard-coding one, so the page
  /// stays in the user's own palette.
  final int colorIndex;

  factory SummaryBlock.fromJson(Map<String, dynamic> m) {
    final type = BlockType.values.firstWhere(
      (t) => t.name == m['type'],
      orElse: () => BlockType.note,
    );
    return SummaryBlock(
      type: type,
      title: (m['title'] as String?) ?? '',
      text: (m['text'] as String?) ?? '',
      items: (m['items'] as List<dynamic>? ?? const [])
          .map((e) => '$e')
          .where((e) => e.trim().isNotEmpty)
          .toList(),
      colorIndex: (m['color_index'] as num?)?.toInt() ?? 0,
    );
  }

  /// النص الخام للبلوك — بيستخدم لما نحفظ التلخيص كملاحظة.
  /// The block as plain text, used when saving the summary as a note.
  String toPlainText() => switch (type) {
        BlockType.heading => '## $text',
        BlockType.box => '**$title**\n$text',
        BlockType.bullets => items.map((i) => '- $i').join('\n'),
        BlockType.numbered => [
            for (var i = 0; i < items.length; i++) '${i + 1}. ${items[i]}',
          ].join('\n'),
        BlockType.highlight => '**$text**',
        BlockType.note => text,
        BlockType.divider => '---',
      };
}

/// تلخيص مرسوم كامل.
/// A complete rendered summary.
@immutable
class SummaryPage {
  const SummaryPage({required this.title, required this.blocks});

  final String title;
  final List<SummaryBlock> blocks;

  factory SummaryPage.fromJson(Map<String, dynamic> m) => SummaryPage(
        title: (m['title'] as String?) ?? '',
        blocks: (m['blocks'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SummaryBlock.fromJson)
            .toList(),
      );

  String toPlainText() =>
      ['# $title', for (final b in blocks) b.toPlainText()].join('\n\n');
}

/// ناتج تحليل صورة من كراسة المستخدم: شكل الصفحة **ونص** التلخيص اللي فيها.
/// What one notebook photo yields: the page's look **and** the summary written
/// on it.
///
/// الاتنين بيتطلبوا في نداء واحد بقصد — الحصة المجانية محدودة، وكل صورة
/// بتديك المعلومتين مرة واحدة.
/// Both come from a single call on purpose: the free quota is tight, and one
/// photo can answer both questions at once.
@immutable
class StyleAnalysis {
  const StyleAnalysis({
    required this.profile,
    this.title = '',
    this.transcript = '',
  });

  final StyleProfile profile;

  /// عنوان الصفحة زي ما هو مكتوب.
  /// The page's own heading.
  final String title;

  /// نص التلخيص المكتوب بخط اليد، منقول حرفيًا.
  /// The handwritten summary, transcribed as written.
  final String transcript;

  bool get hasTranscript => transcript.trim().length > 30;

  factory StyleAnalysis.fromJson(Map<String, dynamic> m) => StyleAnalysis(
        profile: StyleProfile.fromJson(
          (m['look'] as Map<String, dynamic>?) ?? m,
        ),
        title: (m['title'] as String?) ?? '',
        transcript: (m['transcript'] as String?) ?? '',
      );
}

/// البرومبتات الخاصة بالتحليل البصري والتلخيص المنظم.
/// Prompts for the visual analysis and the structured summary.
class VisualPrompts {
  const VisualPrompts._();

  static const analysisSystem = '''
أنت بتحلل صور تلخيصات مكتوبة بخط اليد. مطلوب منك حاجتين من نفس الصورة:

**أولاً: شكل الصفحة**
- الألوان المستخدمة وأماكنها (عناوين، تحديد، تحذيرات).
- ترتيب الأقسام على الصفحة من فوق لتحت.
- استخدام المربعات والإطارات والخطوط الفاصلة.
- التنقيط والترقيم.
- كثافة الصفحة: مزحومة ولا فيها مسافات.

**ثانيًا: نص التلخيص**
انقل اللي مكتوب في الصفحة **حرفيًا** بنفس ترتيبه وتقسيمه وعناوينه.
- متلخصش ومتختصرش ومتعيدش صياغة — ده نقل مش تلخيص.
- حافظ على نبرة الطالب ولهجته زي ما كتبها بالظبط.
- علّم العناوين بـ ** ** والنقط بـ -.
- لو في كلمة مش واضحة، اكتب أقرب قراءة ليها من غير ما تعلّق.

رد بـ JSON بالشكل ده بالظبط:
{
  "look": {
    "accent_colors": ["#RRGGBB", ...],
    "section_order": ["اسم القسم زي ما بيسميه أو وصفه", ...],
    "uses_boxes": true/false,
    "uses_numbering": true/false,
    "density": "compact" | "medium" | "airy",
    "notes": "وصف مختصر لأي عادة تنسيق مميزة"
  },
  "title": "عنوان الصفحة زي ما هو مكتوب",
  "transcript": "نص التلخيص كامل منقول حرفيًا"
}
''';

  static const analysisPrompt =
      'حلّل شكل الصفحة المرفقة وانقل نصها، ورد بالـ JSON المطلوب.';

  static String blocksSystem(StyleProfile profile) => '''
أنت بتلخص محاضرات دراسية بأسلوب طالب معيّن وبشكل صفحته بالظبط.

${profile.asInstructions()}

هترد بـ JSON بالشكل ده بالظبط:
{
  "title": "عنوان الصفحة",
  "blocks": [
    {"type": "heading",   "text": "...",  "color_index": 0},
    {"type": "box",       "title": "...", "text": "...", "color_index": 1},
    {"type": "bullets",   "items": ["...", "..."]},
    {"type": "numbered",  "items": ["...", "..."]},
    {"type": "highlight", "text": "..."},
    {"type": "note",      "text": "..."},
    {"type": "divider"}
  ]
}

قواعد:
- رتّب البلوكات بنفس ترتيب أقسام الطالب.
- استخدم "box" للتعريفات والقواعد لو الطالب بيحط مربعات.
- استخدم "highlight" للي بيتنسى أو اللي بيتكرر في الامتحان.
- color_index رقم من 0 لعدد ألوان الطالب ناقص واحد.
- المحتوى كله من المحاضرة المعطاة. متخترعش معلومة ولا مثال.
- اكتب بالعربي وبنفس نبرة الطالب.
- رد بالـ JSON بس، من غير أي كلام قبله أو بعده.
''';
}

/// بيفك JSON جاي من الموديل بشكل متسامح.
/// Tolerantly decodes JSON coming back from the model.
Map<String, dynamic>? decodeModelJson(Object? raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is String) {
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map<String, dynamic>) return parsed;
    } on FormatException {
      return null;
    }
  }
  return null;
}
