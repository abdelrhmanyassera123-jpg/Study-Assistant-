import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../core/math_text.dart';
import '../../widgets/common.dart';
import '../../widgets/tex_text.dart';
import '../study_ai/study_tools_row.dart';
import 'export_page.dart';
import 'image_quiz_page.dart';
import 'style_profile.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';
import 'summary_images.dart';
import 'summary_page_view.dart';

/// الصفحة المرسومة بشكل المستخدم، مع التعديل والتصدير وأدوات المذاكرة.
/// The page drawn in the user's own layout, with editing, export and the
/// study tools.
class StyledResult extends ConsumerStatefulWidget {
  const StyledResult({
    super.key,
    required this.page,
    required this.profile,
    required this.subjectId,
    required this.onPageChanged,
    required this.onSaveNote,
    this.source = '',
  });

  final SummaryPage page;
  final StyleProfile profile;
  final String? subjectId;

  /// كل تعديل بيطلع صفحة جديدة، والأب هو اللي ماسكها.
  /// Every edit produces a new page, which the parent holds.
  final ValueChanged<SummaryPage> onPageChanged;
  final Future<void> Function() onSaveNote;

  /// نص المحاضرة الأصلي — من غيره مفيش "إيه اللي اتنسى" ولا تعديل من المصدر.
  /// The lecture's original text: without it there is no "what was missed"
  /// and edits work from the page alone.
  final String source;

  @override
  ConsumerState<StyledResult> createState() => _StyledResultState();
}

class _StyledResultState extends ConsumerState<StyledResult> {
  static const _kFormat = 'summary_page_format';

  bool _exporting = false;
  PageFormat _format = PageFormat.a4Landscape;

  /// الحدود اللي هتتصور: واحدة للصفحة المتصلة، أو واحدة لكل صفحة A4.
  /// The boundaries to capture: one for the flowing page, or one per A4 page.
  final _flowKey = GlobalKey();
  List<GlobalKey> _pageKeys = const [];

  bool _checking = false;
  List<String>? _missed;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final saved = PageFormat.values.where((f) => f.name == p.getString(_kFormat));
      if (mounted && saved.isNotEmpty) setState(() => _format = saved.first);
    });
  }

  @override
  void didUpdateWidget(StyledResult old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source) _missed = null;
  }

  void _setFormat(PageFormat format) {
    setState(() {
      _format = format;
      _pageKeys = const [];
    });
    SharedPreferences.getInstance().then((p) => p.setString(_kFormat, format.name));
  }

  List<GlobalKey> get _keys => _format == PageFormat.flowing ? [_flowKey] : _pageKeys;

  String get _fileName {
    final base = widget.page.title.trim().isEmpty ? 'summary' : widget.page.title.trim();
    // أسماء الملفات بتتكسر مع المحارف دي على بعض الأنظمة.
    // These characters break file names on some systems.
    return base.replaceAll(RegExp(r'[\/:*?"<>|]'), '-');
  }

  Future<void> _export({required bool asPdf}) async {
    final keys = _keys;
    if (keys.isEmpty) return;
    setState(() => _exporting = true);
    try {
      // Blob + <a download> بيبدأ التنزيل بصمت — من غير رسالة هنا المستخدم
      // بيضغط ومفيش أي رد فعل ظاهر، فبيفتكر إن الزرار مش شغال.
      // A Blob + <a download> starts the download silently — without a
      // message here the user presses the button, sees no visible reaction,
      // and assumes it is broken.
      String name;
      if (asPdf) {
        name = '$_fileName.pdf';
        downloadBytes(name, 'application/pdf', await capturePdf(keys));
      } else {
        // صورة لكل صفحة: لزقهم في صورة واحدة طويلة كان هيضيّع فكرة الصفحات.
        // One image per page: stitching them into one tall image would undo
        // the point of having pages.
        for (var i = 0; i < keys.length; i++) {
          final suffix = keys.length == 1 ? '' : ' (${i + 1})';
          downloadBytes('$_fileName$suffix.png', 'image/png', await capturePng(keys[i]));
        }
        name = keys.length == 1 ? '$_fileName.png' : '$_fileName (1-${keys.length}).png';
      }
      if (mounted) showSnack(context, context.l.exportDownloaded(name));
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ---------------------------------------------------- التعديل / editing

  Future<void> _editBlock(SummaryBlock block) async {
    final l = context.l;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EditSheet(block: block),
    );
    if (choice == null || !mounted) return;

    final blocks = widget.page.blocks;
    final index = blocks.indexOf(block);
    if (index < 0) return;

    if (choice == _EditSheet.delete) {
      widget.onPageChanged(widget.page.withBlocks([...blocks]..removeAt(index)));
      return;
    }

    final busy = showBusy(context, l.reworking);
    try {
      final replacement = await ref.read(activeSummarizerProvider).reworkBlock(
            page: widget.page,
            block: block,
            instruction: choice,
            profile: widget.profile,
            source: widget.source,
          );
      var updated = widget.page.withBlocks([
        ...blocks.sublist(0, index),
        ...replacement,
        ...blocks.sublist(index + 1),
      ]);
      if (replacement.any((b) => b.type == BlockType.image && b.imageUrl == null)) {
        updated = await attachImages(updated);
      }
      busy.close();
      if (mounted) widget.onPageChanged(updated);
    } on SummarizerException catch (e) {
      busy.close();
      if (mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _checkMissed() async {
    setState(() => _checking = true);
    try {
      final missed = await ref.read(activeSummarizerProvider).findMissed(
            source: widget.source,
            summary: widget.page.toPlainText(),
          );
      if (mounted) setState(() => _missed = missed);
    } on SummarizerException catch (e) {
      if (mounted) showSnack(context, e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _addMissed() {
    final missed = _missed;
    if (missed == null || missed.isEmpty) return;
    widget.onPageChanged(widget.page.withBlocks([
      ...widget.page.blocks,
      SummaryBlock(
        type: BlockType.box,
        title: context.l.missedBoxTitle,
        text: missed.map((m) => '• $m').join('\n'),
        colorIndex: 1,
      ),
    ]));
    setState(() => _missed = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final images = widget.page.blocks
        .where((b) => b.type == BlockType.image && b.imageUrl != null)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<PageFormat>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: PageFormat.a4Landscape,
              icon: const Icon(Icons.crop_landscape_rounded, size: 18),
              label: Text(l.formatLandscape),
            ),
            ButtonSegment(
              value: PageFormat.a4Portrait,
              icon: const Icon(Icons.crop_portrait_rounded, size: 18),
              label: Text(l.formatPortrait),
            ),
            ButtonSegment(
              value: PageFormat.flowing,
              icon: const Icon(Icons.view_day_outlined, size: 18),
              label: Text(l.formatFlowing),
            ),
          ],
          selected: {_format},
          onSelectionChanged: (s) => _setFormat(s.first),
        ),
        const SizedBox(height: Insets.sm),
        Text(
          l.tapBlockToEdit,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: Insets.md),
        // الحدود دي هي اللي بتتصور وقت التصدير، فبتتلف الصفحة نفسها بس.
        // This boundary is what gets captured, so it wraps the page alone.
        //
        // وتكبير الخط بتاع التطبيق متشال من هنا: الصفحة دي ملف هيتصدَّر، ولو
        // إعداد في التطبيق غيّر مقاسها تبقى المعاينة مش هي اللي اتحفظت.
        // The app's text scaling is dropped here: this page is a file about to
        // be exported, and if an app setting resized it the preview would stop
        // being what got saved.
        MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: _format == PageFormat.flowing
              ? RepaintBoundary(
                  key: _flowKey,
                  child: SummaryPageView(
                    page: widget.page,
                    profile: widget.profile,
                    onTapBlock: _editBlock,
                  ),
                )
              : PagedSummary(
                  page: widget.page,
                  profile: widget.profile,
                  format: _format,
                  onTapBlock: _editBlock,
                  // من غير setState: المفاتيح بتتقرا وقت الضغط بس.
                  // No setState: the keys are only read when a button is pressed.
                  onPages: (keys) => _pageKeys = keys,
                ),
        ),
        const SizedBox(height: Insets.lg),
        if (widget.source.trim().length >= 200) ...[
          _MissedCard(
            checking: _checking,
            missed: _missed,
            onCheck: _checkMissed,
            onAdd: _addMissed,
          ),
          const SizedBox(height: Insets.lg),
        ],
        // الأزرار في صف واحد بتتزنق على الموبايل، فبتبقى فوق بعض.
        // The buttons crowd a phone in one row, so they stack there.
        LayoutBuilder(
          builder: (context, constraints) {
            final buttons = [
              FilledButton.icon(
                onPressed: _exporting ? null : () => _export(asPdf: true),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                label: Text(l.exportPdf),
              ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : () => _export(asPdf: false),
                icon: const Icon(Icons.image_outlined, size: 19),
                label: Text(l.exportPng),
              ),
              OutlinedButton.icon(
                onPressed: _exporting ? null : widget.onSaveNote,
                icon: const Icon(Icons.save_alt_rounded, size: 19),
                label: Text(l.saveAsNote),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: readableMath(widget.page.toPlainText())),
                  );
                  if (context.mounted) showSnack(context, l.copied);
                },
                icon: const Icon(Icons.copy_rounded, size: 19),
                label: Text(l.copyText),
              ),
            ];

            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final b in buttons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Insets.sm),
                      child: b,
                    ),
                ],
              );
            }

            return Row(
              children: [
                for (final b in buttons) ...[
                  Expanded(child: b),
                  if (b != buttons.last) const SizedBox(width: Insets.md),
                ],
              ],
            );
          },
        ),
        if (images.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          OutlinedButton.icon(
            onPressed: () => openImageQuiz(
              context,
              figures: images,
              subjectId: widget.subjectId,
            ),
            icon: const Icon(Icons.quiz_outlined, size: 19),
            label: Text(l.imageQuiz(images.length)),
          ),
        ],
        const SizedBox(height: Insets.lg),
        StudyToolsRow(
          title: l.theSummary,
          source: widget.page.toPlainText(),
          subjectId: widget.subjectId,
        ),
      ],
    );
  }
}

/// اختيارات تعديل بلوك. القيمة اللي بترجع هي التعليمة نفسها للموديل.
/// The choices for editing a block. The value returned is the instruction
/// itself, sent to the model.
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.block});

  final SummaryBlock block;

  static const delete = '__delete__';

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final options = <(IconData, String, String)>[
      (Icons.unfold_more_rounded, l.reworkExpand,
          'وسّع الجزء ده: اشرح أكتر وضيف التفاصيل المهمة اللي في المحاضرة.'),
      (Icons.compress_rounded, l.reworkSimplify,
          'بسّط الجزء ده واختصره: نفس المعلومة بكلام أسهل وأقصر.'),
      (Icons.lightbulb_outline_rounded, l.reworkExample,
          'ضيف مثال واحد واضح بعد الجزء ده يوضّح الفكرة (من المحاضرة لو موجود).'),
      (Icons.image_outlined, l.reworkImage,
          'رجّع الجزء ده زي ما هو وبعده بلوك image واحد بصورة توضيحية مناسبة.'),
      (Icons.table_rows_outlined, l.reworkPoints,
          'حوّل الجزء ده لنقط قصيرة مرقّمة سهلة الحفظ.'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Insets.lg,
        0,
        Insets.lg,
        Insets.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: Radii.all(Radii.sm),
              ),
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: TexText(
                  widget.block.toPlainText().replaceAll(RegExp(r'[#*]'), ''),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
            const SizedBox(height: Insets.md),
            for (final (icon, label, instruction) in options)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.pop(context, instruction),
              ),
            const SizedBox(height: Insets.sm),
            TextField(
              controller: _custom,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l.reworkCustom,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send_rounded),
                  onPressed: () {
                    final text = _custom.text.trim();
                    if (text.isNotEmpty) Navigator.pop(context, text);
                  },
                ),
              ),
            ),
            const SizedBox(height: Insets.sm),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text(l.reworkDelete),
              onTap: () => Navigator.pop(context, _EditSheet.delete),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissedCard extends StatelessWidget {
  const _MissedCard({
    required this.checking,
    required this.missed,
    required this.onCheck,
    required this.onAdd,
  });

  final bool checking;
  final List<String>? missed;
  final VoidCallback onCheck;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final found = missed;

    if (found == null) {
      return OutlinedButton.icon(
        onPressed: checking ? null : onCheck,
        icon: checking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fact_check_outlined, size: 19),
        label: Text(checking ? l.checkingMissed : l.checkMissed),
      );
    }

    if (found.isEmpty) {
      return InfoBanner(message: l.nothingMissed, icon: Icons.check_circle_outline);
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l.missedTitle(found.length),
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: Insets.md),
          for (final point in found)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: TexText('• $point',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          const SizedBox(height: Insets.sm),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: Text(l.addMissed),
          ),
        ],
      ),
    );
  }
}
