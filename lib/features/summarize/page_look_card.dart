import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'file_input.dart';
import 'style_profile.dart';
import 'summarizer.dart';
import 'summarizer_provider.dart';

const _imageExtensions = ['png', 'jpg', 'jpeg', 'webp'];

/// سقف عدد الصور في التحليل الواحد.
/// How many images one analysis takes.
///
/// حد الطلب عند جوجل حوالي 20 ميجا، والأسلوب بيبان من كام صفحة — الصور
/// الزيادة بتكبّر الطلب من غير ما تحسّن الوصف.
/// Google's request cap is about 20 MB, and a handful of pages is enough to
/// show the habit; more images inflate the request without sharpening it.
const _maxImages = 6;

/// بطاقة تحليل شكل صفحة المستخدم من صور كراسته.
/// The card that reads the user's page layout from notebook photos.
///
/// الصور بتتبعت للتحليل بس وما بتتخزنش في أي مكان — اللي بيتحفظ هو الوصف
/// الناتج (ألوان، ترتيب أقسام، عادات تنسيق).
/// Photos are sent for analysis only and stored nowhere; what gets saved is the
/// resulting description (colours, section order, formatting habits).
class PageLookCard extends ConsumerStatefulWidget {
  const PageLookCard({super.key, this.subjectId});

  final String? subjectId;

  @override
  ConsumerState<PageLookCard> createState() => _PageLookCardState();
}

class _PageLookCardState extends ConsumerState<PageLookCard> {
  bool _busy = false;
  SummarizerException? _error;

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final picked = await pickLocalFiles(extensions: _imageExtensions);
      if (picked.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }

      // الصور كلها في نداء واحد: أرخص على الحصة، والأهم إن الموديل بيشوفهم
      // مع بعض فيستنتج العادة المشتركة بدل ما يوصف كل صفحة لوحدها.
      // All images ride one call: cheaper on quota, and the model sees them
      // together so it infers the shared habit instead of describing each page
      // in isolation.
      final files = [
        for (final f in picked.take(_maxImages))
          LectureFile(name: f.name, mimeType: f.mimeType, bytes: f.bytes),
      ];

      final analysis =
          await ref.read(activeSummarizerProvider).analyzeStyle(files);
      final repo = ref.read(repositoryProvider);

      await repo.saveStyleProfile(
        subjectId: widget.subjectId,
        profile: analysis.profile.toJson(),
        sourceCount: files.length,
      );

      // كل صفحة بتتحفظ كمثال أسلوب لوحدها، فالمستخدم مش محتاج يكتب
      // تلخيصاته بإيده.
      // Each page is stored as its own style example, so nothing has to be
      // retyped by hand.
      final pages = analysis.usablePages;
      for (var i = 0; i < pages.length; i++) {
        await repo.addStyleSample(StyleSample(
          id: '',
          title: pages[i].title.isEmpty
              ? (i < files.length
                  ? files[i].name.replaceAll(RegExp(r'\.[^.]+$'), '')
                  : '')
              : pages[i].title,
          body: pages[i].transcript,
          subjectId: widget.subjectId,
          createdAt: DateTime.now(),
        ));
      }
      if (pages.isNotEmpty) ref.invalidate(styleSamplesProvider);

      ref.invalidate(styleProfilesProvider);

      if (mounted) {
        setState(() => _busy = false);
        showSnack(
          context,
          pages.isEmpty
              ? context.l.lookSaved
              : context.l.lookAndPagesSaved(pages.length),
        );
      }
    } on SummarizerException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = SummarizerException('$e');
        });
      }
    }
  }

  Future<void> _remove() async {
    if (!await confirmDelete(context)) return;
    await ref.read(repositoryProvider).deleteStyleProfile(widget.subjectId);
    ref.invalidate(styleProfilesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final profiles = ref.watch(styleProfilesProvider).value ?? const {};
    final raw = profiles[widget.subjectId] ?? profiles[null];
    final profile = raw == null ? null : StyleProfile.fromJson(raw);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_fix_high_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.pageLook,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (profile != null)
                  IconButton(
                    tooltip: l.removeLook,
                    iconSize: 18,
                    onPressed: _busy ? null : _remove,
                    icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l.pageLookIntro,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant, height: 1.7),
            ),

            if (profile != null && !profile.isEmpty) ...[
              const SizedBox(height: 14),
              if (profile.accentColors.isNotEmpty)
                Row(
                  children: [
                    Text('${l.colorsFound}:',
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(width: 8),
                    for (final c in profile.accentColors)
                      Container(
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.outlineVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              if (profile.sectionOrder.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  '${l.sectionsFound}: ${profile.sectionOrder.join(' ← ')}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant, height: 1.6),
                ),
              ],
            ],

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _error!.hint == null
                      ? _error!.message
                      : '${_error!.message}\n${_error!.hint}',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : _analyze,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(
                _busy
                    ? l.analyzingLook
                    : (profile == null ? l.uploadHandwriting : l.reanalyze),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${l.pickManyImages}\n${l.handwritingNote}',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

