import 'package:flutter/material.dart';

import '../../widgets/tex_text.dart';
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
    this.onTapBlock,
  });

  final SummaryPage page;
  final StyleProfile profile;

  /// ضغطة على بلوك بتفتح تعديله. null = الصفحة للعرض بس.
  /// A tap on a block opens its edit; null means the page is display-only.
  final ValueChanged<SummaryBlock>? onTapBlock;

  /// النسخة المصدّرة بتتقاس بعرض ثابت؛ المعاينة بتاخد عرض الشاشة.
  /// The exported copy uses a fixed width; the preview takes the screen's.
  final bool forExport;

  /// الصفحة ورقة، مش جزء من ثيم التطبيق: بتفضل بيضا بحبر غامق حتى في الوضع
  /// الليلي. غير كده الثيم الغامق كان بيدي أسود على أسود، وبيخلي المعاينة
  /// مختلفة عن الملف المصدَّر.
  /// The page is paper, not part of the app's theme: it stays white with dark
  /// ink even in dark mode. Otherwise dark mode rendered black on black, and
  /// the preview stopped matching the exported file.
  static const paper = Color(0xFFFFFDF7);
  static const ink = Color(0xFF1A1A1A);

  double get _gap => blockGap(profile);

  @override
  Widget build(BuildContext context) {
    final headingColor = profile.colorAt(0, const Color(0xFF1F3A93));

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: forExport ? 900 : null,
        color: paper,
        padding: EdgeInsets.all(forExport ? 40 : 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (page.title.trim().isNotEmpty) ...[
              TexText(
                page.title,
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
              _tappable(block, SummaryBlockView(block: block, profile: profile), onTapBlock),
              SizedBox(height: _gap),
            ],
          ],
        ),
      ),
    );
  }
}

Widget _tappable(
  SummaryBlock block,
  Widget child,
  ValueChanged<SummaryBlock>? onTap,
) =>
    onTap == null
        ? child
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(block),
              child: child,
            ),
          );

double blockGap(StyleProfile profile) => switch (profile.density) {
      'compact' => 10,
      'airy' => 22,
      _ => 16,
    };

class SummaryBlockView extends StatelessWidget {
  const SummaryBlockView({super.key, required this.block, required this.profile});

  final SummaryBlock block;
  final StyleProfile profile;
  Color get onPaper => SummaryPageView.ink;

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
              child: TexText(
                block.text,
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
                child: TexText(block.text, style: body),
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
                        child: TexText(item, style: body)),
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
                        '${i + block.numberFrom}',
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
                            TexText(block.items[i], style: body)),
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
          child: TexText(
            block.text,
            style: body.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      BlockType.note => TexText(
          block.text,
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
      BlockType.image => _Figure(block: block, color: color),
      BlockType.diagram => _Diagram(block: block, color: color),
    };
  }
}

/// صورة توضيحية بارتفاع ثابت: التقسيم على الصفحات بيتحسب قبل ما الصورة
/// تحمّل، فلو ارتفاعها اتغيّر بعد التحميل الصفحة كانت هتفيض.
/// A figure at a fixed height: pagination is measured before the picture
/// loads, so a height that changed on load would overflow the page.
class _Figure extends StatelessWidget {
  const _Figure({required this.block, required this.color});

  final SummaryBlock block;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final url = block.imageUrl;
    final data = block.imageData;
    if (url == null && data == null) return const SizedBox.shrink();
    Widget broken(BuildContext _, Object _, StackTrace? _) => Icon(
          Icons.image_not_supported_outlined,
          color: color.withValues(alpha: 0.4),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          // صفحة السلايد أعرض وفيها كلام، فبتاخد مساحة أكبر شوية.
          // A slide page is wider and carries text, so it gets a little more room.
          height: data != null ? 240 : 210,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: color.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.all(6),
          child: data != null
              ? Image.memory(data, fit: BoxFit.contain, errorBuilder: broken)
              : Image.network(url!, fit: BoxFit.contain, errorBuilder: broken),
        ),
        if (block.text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          TexText(
            block.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: SummaryPageView.ink.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}

/// شكل الورقة المصدَّرة.
/// The shape of the exported paper.
enum PageFormat {
  /// صفحة واحدة طويلة زي ما كانت.
  /// One long page, as before.
  flowing,
  a4Portrait,

  /// عمودين جنب بعض — أقرب لشكل الملزمة المفتوحة.
  /// Two columns side by side — closer to an open revision sheet.
  a4Landscape;

  /// A4 عند 96 نقطة/بوصة.
  /// A4 at 96 dpi.
  Size get size => this == a4Landscape ? const Size(1123, 794) : const Size(794, 1123);
  int get columns => this == a4Landscape ? 2 : 1;
}

/// التلخيص مقسّم على صفحات A4 بمقاس ثابت.
/// The summary split across fixed-size A4 pages.
///
/// التقسيم بيتحسب من المقاسات الحقيقية: البلوكات بتترسم مرة مخفية بعرض العمود،
/// وبعدين بتتوزع. التقدير بعدد الحروف كان هيغلط مع الصور والمعادلات.
/// Pagination is computed from real sizes: the blocks are laid out once,
/// hidden, at the column's width, then distributed. Estimating by character
/// count would go wrong around figures and formulas.
class PagedSummary extends StatefulWidget {
  const PagedSummary({
    super.key,
    required this.page,
    required this.profile,
    required this.format,
    required this.onPages,
    this.onTapBlock,
  });

  final SummaryPage page;
  final StyleProfile profile;
  final PageFormat format;
  final ValueChanged<SummaryBlock>? onTapBlock;

  /// مفتاح لكل صفحة، عشان التصدير يصوّرهم واحدة واحدة.
  /// One key per page, so export can capture them one by one.
  final ValueChanged<List<GlobalKey>> onPages;

  @override
  State<PagedSummary> createState() => _PagedSummaryState();
}

class _PagedSummaryState extends State<PagedSummary> {
  static const _pad = 36.0;
  static const _columnGap = 28.0;
  static const _footer = 22.0;

  late List<SummaryBlock> _units;

  /// البلوك الأصلي لكل جزء — القايمة المقسومة بتتعدل كلها مش جزء منها.
  /// The original block behind each piece: a split list is edited whole.
  final _origin = <SummaryBlock, SummaryBlock>{};
  List<GlobalKey> _measureKeys = [];
  final _titleKey = GlobalKey();

  /// صفحات ← أعمدة ← بلوكات. null لحد ما القياس يخلص.
  /// pages → columns → blocks. null until measuring is done.
  List<List<List<SummaryBlock>>>? _pages;
  List<GlobalKey> _pageKeys = [];

  double get _columnWidth {
    final cols = widget.format.columns;
    return (widget.format.size.width - 2 * _pad - (cols - 1) * _columnGap) / cols;
  }

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(PagedSummary old) {
    super.didUpdateWidget(old);
    // البروفايل بيتبني من جديد مع كل build للأب، فمقارنته بالهوية كانت هتعيد
    // التقسيم كل مرة.
    // The profile is rebuilt on every parent build, so comparing it by
    // identity would re-paginate every time.
    if (old.page != widget.page || old.format != widget.format) {
      _prepare();
    }
  }

  void _prepare() {
    _origin.clear();
    _units = _splitLists(widget.page.blocks, _origin);
    _measureKeys = [for (final _ in _units) GlobalKey()];
    _pages = null;
    WidgetsBinding.instance.addPostFrameCallback((_) => _paginate());
  }

  /// القايمة الطويلة بتتقسم لأجزاء صغيرة عشان تقدر تكمّل في العمود اللي بعده
  /// بدل ما تتصغّر كلها في عمود واحد.
  /// Long lists are cut into small pieces so they can continue in the next
  /// column instead of being shrunk to fit one.
  static List<SummaryBlock> _splitLists(
    List<SummaryBlock> blocks,
    Map<SummaryBlock, SummaryBlock> origin,
  ) {
    const size = 4;
    final out = <SummaryBlock>[];
    for (final b in blocks) {
      final isList = b.type == BlockType.bullets || b.type == BlockType.numbered;
      if (!isList || b.items.length <= size) {
        out.add(b);
        origin[b] = b;
        continue;
      }
      for (var i = 0; i < b.items.length; i += size) {
        final end = (i + size).clamp(0, b.items.length);
        final piece = b.copyWith(items: b.items.sublist(i, end), numberFrom: i + 1);
        out.add(piece);
        origin[piece] = b;
      }
    }
    return out;
  }

  double _heightOf(GlobalKey key) =>
      (key.currentContext?.findRenderObject() as RenderBox?)?.size.height ?? 0;

  void _paginate() {
    if (!mounted) return;
    final gap = blockGap(widget.profile);
    final full = widget.format.size.height - 2 * _pad - _footer;
    final titleHeight = widget.page.title.trim().isEmpty ? 0.0 : _heightOf(_titleKey) + gap;
    final cols = widget.format.columns;

    final pages = <List<List<SummaryBlock>>>[];
    var page = <List<SummaryBlock>>[];
    var column = <SummaryBlock>[];
    var used = 0.0;

    double capacity() => pages.isEmpty ? full - titleHeight : full;

    void closeColumn() {
      page.add(column);
      column = [];
      used = 0;
      if (page.length == cols) {
        pages.add(page);
        page = [];
      }
    }

    for (var i = 0; i < _units.length; i++) {
      final h = _heightOf(_measureKeys[i]);
      final need = column.isEmpty ? h : h + gap;
      if (column.isNotEmpty && used + need > capacity()) {
        // العنوان ما يتسابش لوحده في آخر العمود ومحتواه في اللي بعده.
        // A heading is never left alone at a column's foot.
        final orphan = column.last.type == BlockType.heading && column.length > 1
            ? column.removeLast()
            : null;
        closeColumn();
        if (orphan != null) {
          column.add(orphan);
          used = _heightOf(_measureKeys[_units.indexOf(orphan)]);
        }
      }
      used += column.isEmpty ? h : h + gap;
      column.add(_units[i]);
    }
    if (column.isNotEmpty) closeColumn();
    if (page.isNotEmpty) pages.add(page);

    setState(() {
      _pages = pages;
      _pageKeys = [for (final _ in pages) GlobalKey()];
    });
    widget.onPages(_pageKeys);
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages == null) return _measuring();

    final size = widget.format.size;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < pages.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: size.width / size.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8),
                ],
              ),
              child: FittedBox(
                child: RepaintBoundary(
                  key: _pageKeys[i],
                  child: _sheet(i, pages[i], pages.length),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sheet(int index, List<List<SummaryBlock>> columns, int total) {
    final size = widget.format.size;
    final gap = blockGap(widget.profile);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: size.width,
        height: size.height,
        color: SummaryPageView.paper,
        padding: const EdgeInsets.fromLTRB(_pad, _pad, _pad, _pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (index == 0 && widget.page.title.trim().isNotEmpty) ...[
              _title(),
              SizedBox(height: gap),
            ],
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < widget.format.columns; c++) ...[
                    if (c > 0) const SizedBox(width: _columnGap),
                    SizedBox(
                      width: _columnWidth,
                      child: c < columns.length ? _column(columns[c], gap) : null,
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              height: _footer,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Text(
                  '${index + 1} / $total',
                  style: TextStyle(
                    fontSize: 11,
                    color: SummaryPageView.ink.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// لو القياس غلط (خط اتحمّل بعده مثلاً)، العمود بيصغر بدل ما يتقص.
  /// If a measurement was off — say a font loaded afterwards — the column
  /// shrinks instead of being cut off.
  Widget _column(List<SummaryBlock> blocks, double gap) => ClipRect(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: _columnWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < blocks.length; i++) ...[
                  // جزء مكمّل لنفس القايمة بيلزق في اللي قبله.
                  // A continuation of the same list sits tight against it.
                  if (i > 0)
                    SizedBox(
                      height: blocks[i].numberFrom > 1 &&
                              blocks[i].type == blocks[i - 1].type
                          ? 0
                          : gap,
                    ),
                  _tappable(
                    _origin[blocks[i]] ?? blocks[i],
                    SummaryBlockView(block: blocks[i], profile: widget.profile),
                    widget.onTapBlock,
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _title({Key? key}) {
    final color = widget.profile.colorAt(0, const Color(0xFF1F3A93));
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TexText(
          widget.page.title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 3, color: color.withValues(alpha: 0.6)),
      ],
    );
  }

  Widget _measuring() {
    return SizedBox(
      height: 120,
      child: Stack(
        children: [
          const Center(child: CircularProgressIndicator()),
          // Offstage بيعمل layout من غير رسم — ده كل اللي محتاجينه للقياس.
          // Offstage lays out without painting, which is all measuring needs.
          Offstage(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              maxWidth: widget.format.size.width,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: widget.format.size.width - 2 * _pad,
                      child: _title(key: _titleKey),
                    ),
                    for (var i = 0; i < _units.length; i++)
                      SizedBox(
                        key: _measureKeys[i],
                        width: _columnWidth,
                        child: SummaryBlockView(block: _units[i], profile: widget.profile),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// مخطط مرسوم من الكلام نفسه: خطوات، دورة، فروع، أو مقارنة.
/// A diagram drawn from the text itself: steps, a cycle, branches, or a
/// comparison.
///
/// بديل الصورة لما مفيش رسمة حقيقية: بيترسم بنفس الخط والألوان، فبيطلع
/// حاد في الـ PDF، ومحتواه من المحاضرة مش متخيّل.
/// The stand-in for a picture when no real figure exists: drawn in the same
/// font and colours, so it comes out sharp in the PDF, and its content comes
/// from the lecture rather than being imagined.
class _Diagram extends StatelessWidget {
  const _Diagram({required this.block, required this.color});

  final SummaryBlock block;
  final Color color;

  TextStyle get _cell => const TextStyle(fontSize: 13.5, height: 1.5, color: SummaryPageView.ink);

  Widget _node(String text, {bool filled = false}) => Container(
        constraints: const BoxConstraints(minWidth: 70, maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.1),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 1.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: TexText(
          text,
          textAlign: TextAlign.center,
          style: filled
              ? _cell.copyWith(color: Colors.white, fontWeight: FontWeight.w700)
              : _cell,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final body = switch (block.kind) {
      'compare' => _compare(),
      'tree' => _tree(),
      'cycle' => _steps(cycle: true),
      _ => _steps(cycle: false),
    };
    final showTitle = block.title.trim().isNotEmpty && block.kind != 'tree';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTitle) ...[
            TexText(
              block.title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(height: 10),
          ],
          body,
        ],
      ),
    );
  }

  Widget _steps({required bool cycle}) {
    final items = block.items;
    // السهم ده بيتقلب لوحده في العربي، فبيشاور على الخطوة اللي بعدها.
    // This arrow mirrors itself in Arabic, so it points at the next step.
    final arrow = Icon(Icons.arrow_forward_rounded, size: 20, color: color);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 10,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) arrow,
              _node(items[i]),
            ],
          ],
        ),
        if (cycle && items.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.replay_rounded, size: 18, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: TexText(
                  '← ${items.first}',
                  style: _cell.copyWith(fontSize: 12.5, color: color),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _tree() {
    return Column(
      children: [
        _node(block.title.isEmpty ? block.text : block.title, filled: true),
        Container(width: 2, height: 14, color: color.withValues(alpha: 0.6)),
        Container(
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          color: color.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [for (final item in block.items) _node(item)],
        ),
      ],
    );
  }

  Widget _compare() {
    final columns = block.columns;
    final width = [
      columns.length,
      for (final r in block.rows) r.length,
    ].fold<int>(0, (a, b) => a > b ? a : b);
    if (width == 0) return const SizedBox.shrink();

    List<String> pad(List<String> r) => [...r, ...List.filled(width - r.length, '')];
    final line = BorderSide(color: color.withValues(alpha: 0.35));

    return Table(
      border: TableBorder(
        top: line,
        bottom: line,
        left: line,
        right: line,
        horizontalInside: line,
        verticalInside: line,
      ),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        if (columns.isNotEmpty)
          TableRow(
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14)),
            children: [
              for (final c in pad(columns))
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: TexText(
                    c,
                    textAlign: TextAlign.center,
                    style: _cell.copyWith(fontWeight: FontWeight.w700, color: color),
                  ),
                ),
            ],
          ),
        for (final r in block.rows)
          TableRow(
            children: [
              for (var i = 0; i < width; i++)
                Padding(
                  padding: const EdgeInsets.all(7),
                  child: TexText(
                    pad(r)[i],
                    textAlign: TextAlign.center,
                    style: i == 0 ? _cell.copyWith(fontWeight: FontWeight.w700) : _cell,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
