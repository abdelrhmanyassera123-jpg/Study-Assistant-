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

  /// بيقرا لون ويرفض اللي مش صالح كلون تمييز على ورقة.
  /// Parses a colour, rejecting anything unusable as an accent on paper.
  ///
  /// الموديل بيرجّع لون الورق (أبيض/كريمي) ولون الحبر (أسود) ضمن الألوان،
  /// وهما مش ألوان تمييز — لو اتاخدوا زي ما هما بيطلع عنوان أبيض على ورقة
  /// بيضا أو أسود على أسود. واللي فاتح زيادة بنغمّقه بدل ما نرميه.
  /// The model lists the paper colour (white/cream) and the ink colour (black)
  /// among the accents. Taken literally they produce a white heading on white
  /// paper, or black on black. Anything merely too pale is darkened instead of
  /// being thrown away.
  /// أسماء الألوان الشائعة — الموديل بيرجّع "red" بدل "#RRGGBB" أحيانًا،
  /// والرفض وقتها بيفضّي القايمة كلها.
  /// Common colour names: the model sometimes answers "red" instead of
  /// "#RRGGBB", and rejecting those empties the whole list.
  static const _namedColors = <String, int>{
    'red': 0xD32F2F, 'أحمر': 0xD32F2F,
    'blue': 0x1565C0, 'أزرق': 0x1565C0,
    'green': 0x2E7D32, 'أخضر': 0x2E7D32,
    'orange': 0xEF6C00, 'برتقالي': 0xEF6C00,
    'purple': 0x6A1B9A, 'بنفسجي': 0x6A1B9A,
    'pink': 0xD81B60, 'وردي': 0xD81B60,
    'brown': 0x5D4037, 'بني': 0x5D4037,
    'teal': 0x00796B, 'تركوازي': 0x00796B,
    'yellow': 0xF9A825, 'أصفر': 0xF9A825,
    'gold': 0xF9A825, 'ذهبي': 0xF9A825,
  };

  static Color? _parseColor(Object? v) {
    if (v is! String) return null;
    final raw = v.trim().toLowerCase();

    final named = _namedColors[raw] ?? _namedColors[v.trim()];
    if (named != null) return Color(0xFF000000 | named);

    var hex = raw.replaceAll('#', '');
    // الصيغة المختصرة #abc بتتمدد لـ #aabbcc.
    // The shorthand #abc expands to #aabbcc.
    if (hex.length == 3) {
      hex = hex.split('').map((c) => '$c$c').join();
    }
    if (hex.length != 6) return null;
    final value = int.tryParse(hex, radix: 16);
    if (value == null) return null;

    final color = Color(0xFF000000 | value);
    final luminance = color.computeLuminance();

    // ورق أو حبر، مش لون تمييز.
    // Paper or ink, not an accent.
    if (luminance > 0.82 || luminance < 0.04) return null;

    // فاتح لدرجة إنه ما يبانش على ورقة بيضا — بنغمّقه لحد ما يُقرأ.
    // Too pale to read on white paper: darken until it does.
    var adjusted = color;
    while (adjusted.computeLuminance() > 0.55) {
      adjusted = Color.lerp(adjusted, const Color(0xFF1A1A1A), 0.25)!;
    }
    return adjusted;
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

/// صفحة واحدة اتقروت من كراسة المستخدم.
/// One page read out of the user's notebook.
@immutable
class AnalyzedPage {
  const AnalyzedPage({required this.title, required this.transcript});

  final String title;
  final String transcript;

  /// سطرين مش تلخيص — بنتجاهل القراءات الفاشلة.
  /// A couple of lines isn't a summary; failed reads are ignored.
  bool get isUsable => transcript.trim().length > 30;

  factory AnalyzedPage.fromJson(Map<String, dynamic> m) => AnalyzedPage(
        title: (m['title'] as String?)?.trim() ?? '',
        transcript: (m['transcript'] as String?)?.trim() ?? '',
      );
}

/// ناتج تحليل صور كراسة المستخدم: شكل صفحاته **ونص** كل تلخيص فيها.
/// What the notebook photos yield: the page layout **and** the summary written
/// on each one.
///
/// الشكل واحد لكل الصفحات لأنه أسلوب الطالب مش خاصية صفحة، أما النصوص
/// فواحد لكل صورة — كل واحد بيبقى مثال أسلوب لوحده.
/// The layout is shared because it is the student's habit rather than a
/// property of one page; the transcripts are per image, each becoming its own
/// style example.
@immutable
class StyleAnalysis {
  const StyleAnalysis({required this.profile, this.pages = const []});

  final StyleProfile profile;
  final List<AnalyzedPage> pages;

  List<AnalyzedPage> get usablePages =>
      pages.where((p) => p.isUsable).toList();

  /// تحويل آمن: الخرايط الجوّانية بتوصل أحيانًا بنوع عام (من jsonb أو من
  /// فك ترميز متداخل)، والتحويل المباشر بيرمي استثناء ويضيّع الرد كله.
  /// A defensive cast: nested maps sometimes arrive loosely typed (from jsonb
  /// or a nested decode), where a direct cast throws and loses the whole reply.
  static Map<String, dynamic>? _asMap(Object? v) =>
      v is Map ? v.map((k, value) => MapEntry('$k', value)) : null;

  factory StyleAnalysis.fromJson(Map<String, dynamic> m) {
    final look = _asMap(m['look']) ?? m;

    final pages = (m['pages'] as List<dynamic>? ?? const [])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(AnalyzedPage.fromJson)
        .toList();

    // بنقبل كمان شكل الصفحة الواحدة القديم عشان أي رد مش متبع للمخطط
    // ما يضيعش.
    // The older single-page shape is still accepted so a reply that strays
    // from the schema isn't thrown away.
    if (pages.isEmpty && (m['transcript'] as String?)?.trim().isNotEmpty == true) {
      pages.add(AnalyzedPage.fromJson(m));
    }

    return StyleAnalysis(profile: StyleProfile.fromJson(look), pages: pages);
  }
}

/// البرومبتات الخاصة بالتحليل البصري والتلخيص المنظم.
/// Prompts for the visual analysis and the structured summary.
class VisualPrompts {
  const VisualPrompts._();

  static const analysisSystem = '''
أنت بتحلل صور تلخيصات مكتوبة بخط اليد. ممكن توصلك صورة واحدة أو كذا صورة.
مطلوب منك حاجتين:

**أولاً: شكل الصفحة** — وصف واحد مشترك لكل الصور
- الألوان المستخدمة وأماكنها (عناوين، تحديد، تحذيرات).
- ترتيب الأقسام على الصفحة من فوق لتحت.
- استخدام المربعات والإطارات والخطوط الفاصلة.
- التنقيط والترقيم.
- كثافة الصفحة: مزحومة ولا فيها مسافات.

لو الصور مختلفة شوية في التنسيق، اوصف العادة الغالبة عليهم.

**ثانيًا: نص كل صفحة** — عنصر مستقل لكل صورة بنفس ترتيب ورودها
انقل اللي مكتوب في كل صفحة **حرفيًا** بنفس ترتيبه وتقسيمه وعناوينه.
- متلخصش ومتختصرش ومتعيدش صياغة — ده نقل مش تلخيص.
- حافظ على نبرة الطالب ولهجته زي ما كتبها بالظبط.
- علّم العناوين بـ ** ** والنقط بـ -.
- لو في كلمة مش واضحة، اكتب أقرب قراءة ليها من غير ما تعلّق.

رد بـ JSON بالشكل ده بالظبط:
{
  "look": {
    "accent_colors": ["#RRGGBB", ...],   // هيكس بس، مش أسماء ألوان
    "section_order": ["اسم القسم زي ما بيسميه أو وصفه", ...],
    "uses_boxes": true/false,
    "uses_numbering": true/false,
    "density": "compact" | "medium" | "airy",
    "notes": "وصف مختصر لأي عادة تنسيق مميزة"
  },
  "pages": [
    {"title": "عنوان الصفحة زي ما هو مكتوب", "transcript": "نص التلخيص كامل منقول حرفيًا"}
  ]
}

لازم يكون عدد العناصر في pages مساوي لعدد الصور المرفقة.
''';

  static String analysisPrompt(int pageCount) => pageCount == 1
      ? 'حلّل شكل الصفحة المرفقة وانقل نصها، ورد بالـ JSON المطلوب.'
      : 'حلّل شكل الـ $pageCount صفحات المرفقة (وصف واحد مشترك) وانقل نص كل '
          'صفحة لوحدها بنفس ترتيبها، ورد بالـ JSON المطلوب.';

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
