import 'package:flutter/material.dart';

import '../../core/math_text.dart';
import '../../widgets/math_spans.dart';
import 'style_profile.dart';

/// بيرسم التلخيص كصفحة بألوان المستخدم وتخطيطه.
/// Draws the summary as a page in the user's own colours and layout.
///
/// الرسم بويدجتس Flutter مش بتوليد صورة: النص العربي بيطلع مقروء ومختار
/// بخط حقيقي، والصفحة نفسها بتتصور PNG بعد كده.
/// Rendered with Flutter widgets rather than image generation: the Arabic comes
/// out readable and selectable in a real font, and the page is captured to PNG
/// afterwards.
class SummaryPageView extends StatelessWidget {
  const SummaryPageView({
    super.key,
    required this.page,
    required this.profile,
    this.forExport = false,
  });

  final SummaryPage page;
  final StyleProfile profile;

  /// النسخة المصدّرة بتتقاس بعرض ثابت؛ المعاينة بتاخد عرض الشاشة.
  /// The exported copy uses a fixed width; the preview takes the screen's.
  final bool forExport;

  /// الصفحة ورقة، مش جزء من ثيم التطبيق: بتفضل بيضا بحبر غامق حتى في الوضع
  /// الليلي. غير كده الثيم الغامق كان بيدي أسود على أسود، وبيخلي المعاينة
  /// مختلفة عن الملف المصدَّر.
  /// The page is paper, not part of the app's theme: it stays white with dark
  /// ink even in dark mode. Otherwise dark mode rendered black on black, and
  /// the preview stopped matching the exported file.
  static const _paper = Color(0xFFFFFDF7);
  static const _ink = Color(0xFF1A1A1A);

  double get _gap => switch (profile.density) {
        'compact' => 10,
        'airy' => 22,
        _ => 16,
      };

  @override
  Widget build(BuildContext context) {
    const onPaper = _ink;
    final headingColor = profile.colorAt(0, const Color(0xFF1F3A93));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: forExport ? 900 : null,
        color: _paper,
        padding: EdgeInsets.all(forExport ? 40 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (page.title.trim().isNotEmpty) ...[
              MathText(
                readableMath(page.title),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: headingColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Container(height: 3, color: headingColor.withValues(alpha: 0.6)),
              SizedBox(height: _gap),
            ],
            for (final block in page.blocks) ...[
              _Block(block: block, profile: profile, onPaper: onPaper),
              SizedBox(height: _gap),
            ],
          ],
        ),
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.block, required this.profile, required this.onPaper});

  final SummaryBlock block;
  final StyleProfile profile;
  final Color onPaper;

  @override
  Widget build(BuildContext context) {
    final color = profile.colorAt(block.colorIndex, const Color(0xFF1F3A93));
    final body = TextStyle(fontSize: 15, height: 1.9, color: onPaper);

    return switch (block.type) {
      BlockType.heading => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 5, height: 22, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: MathText(
                readableMath(block.text),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      BlockType.box => Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border.all(
              color: color.withValues(alpha: 0.7),
              width: profile.usesBoxes ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (block.title.trim().isNotEmpty)
                Container(
                  color: color.withValues(alpha: 0.14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Text(
                    block.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontSize: 15,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: MathText(readableMath(block.text), style: body),
              ),
            ],
          ),
        ),
      BlockType.bullets => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in block.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: MathText(readableMath(item), style: body)),
                  ],
                ),
              ),
          ],
        ),
      BlockType.numbered => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < block.items.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child:
                            MathText(readableMath(block.items[i]), style: body)),
                  ],
                ),
              ),
          ],
        ),
      BlockType.highlight => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(10),
            border: BorderDirectional(
              start: BorderSide(color: color, width: 4),
            ),
          ),
          child: MathText(
            readableMath(block.text),
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      BlockType.note => MathText(
          readableMath(block.text),
          style: body.copyWith(
            fontSize: 14,
            color: onPaper.withValues(alpha: 0.75),
            fontStyle: FontStyle.italic,
          ),
        ),
      BlockType.divider => Divider(
          color: onPaper.withValues(alpha: 0.2),
          thickness: 1,
        ),
    };
  }
}
