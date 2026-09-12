import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../summarize/file_input.dart';
import '../summarize/image_shrink.dart';
import '../summarize/summarizer.dart';
import '../summarize/summarizer_provider.dart';

Future<void> openScheduleImport(BuildContext context, WidgetRef ref) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const ScheduleImportPage()),
  );
  if (saved == true) ref.invalidate(scheduleProvider);
}

/// بيقرا جدول المحاضرات من نص ملزوق أو صورة.
/// Reads a timetable out of pasted text or a photo.
///
/// الجدول بييجي من الكلية بأي شكل — صورة من واتساب، جدول ملزوق، رسالة مكتوبة
/// على السريع. الكتابة اليدوية لـ 12 محاضرة هي أكتر حاجة بتخلي حد ما يستخدمش
/// الميزة أصلاً.
/// A timetable arrives from college in any shape — a WhatsApp photo, a pasted
/// table, a hastily typed message. Typing twelve lectures by hand is the single
/// thing most likely to stop someone using the feature at all.
class ScheduleImportPage extends ConsumerStatefulWidget {
  const ScheduleImportPage({super.key});

  @override
  ConsumerState<ScheduleImportPage> createState() => _ScheduleImportPageState();
}

class _ScheduleImportPageState extends ConsumerState<ScheduleImportPage> {
  final _text = TextEditingController();
  final List<LectureFile> _images = [];

  ParsedSchedule? _read;

  /// القسم اللي المستخدم قاله. null معناها لسه ما اختارش.
  /// The section the user named; null means they have not chosen yet.
  String? _group;

  final Set<int> _dropped = {};
  bool _busy = false;
  bool _saving = false;
  double _progress = 0;
  SummarizerException? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final files = await pickLocalFiles(
        extensions: ['png', 'jpg', 'jpeg', 'webp', 'pdf'],
      );
      if (files.isEmpty || !mounted) return;

      final picked = <LectureFile>[];
      for (final file in files) {
        // الـ PDF بيتبعت زي ما هو — `shrinkImage` بترجّعه من غير تغيير لأنه
        // مش قادر يفكه كـ bitmap، لكن بنجنّب المحاولة أصلاً.
        // A PDF is sent as-is — `shrinkImage` would hand it back unchanged
        // since it cannot decode it as a bitmap, but skip the attempt outright.
        final small =
            file.mimeType == 'application/pdf' ? file : await shrinkImage(file);
        picked.add(LectureFile(
          name: small.name,
          mimeType: small.mimeType,
          bytes: small.bytes,
        ));
      }
      if (!mounted) return;
      setState(() {
        _images.addAll(picked);
        _error = null;
      });
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  Future<void> _read_() async {
    setState(() {
      _busy = true;
      _error = null;
      _read = null;
      _group = null;
      _progress = 0;
      _dropped.clear();
    });

    try {
      final schedule = await ref.read(activeSummarizerProvider).parseSchedule(
            text: _text.text,
            images: _images,
            onProgress: (fraction) {
              if (mounted) setState(() => _progress = fraction);
            },
          );
      if (mounted) {
        setState(() {
          _read = schedule;
          // القسم الواحد مفيش فيه سؤال — الاختيار بيتحط لوحده.
          // With one section there is nothing to ask; the choice sets itself.
          _group = schedule.groups.length == 1 ? schedule.groups.first : null;
        });
      }
    } on SummarizerException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// المحاضرات المعروضة دلوقتي: بتاعة قسمك + اللي للكل.
  /// The lectures showing now: your section's plus the ones for everyone.
  List<ParsedLecture> get _visible => _read?.forGroup(_group) ?? const [];

  Future<void> _save({required bool replace}) async {
    final visible = _visible;
    if (visible.isEmpty) return;

    final kept = [
      for (var i = 0; i < visible.length; i++)
        if (!_dropped.contains(i)) visible[i],
    ];
    if (kept.isEmpty) return;

    setState(() => _saving = true);
    final repo = ref.read(repositoryProvider);
    try {
      if (replace) await repo.clearSchedule();
      await repo.addScheduleEntries([
        for (final lecture in kept)
          ScheduleEntry(
            id: '',
            title: lecture.title,
            weekday: lecture.weekday,
            startMinutes: lecture.startMinutes,
            endMinutes: lecture.endMinutes,
            location: lecture.location,
            lecturer: lecture.lecturer,
            // التنبيه بيتفتح افتراضيًا على ربع ساعة: الجدول المستورد كله
            // محاضرات جاية، واللي مش عايز تنبيه بيقفله من الصف نفسه.
            // Reminders default to a quarter of an hour: an imported timetable
            // is all upcoming lectures, and anyone who does not want one turns
            // it off from the row itself.
            remindMinutes: 15,
            createdAt: DateTime.now(),
          ),
      ]);
      if (mounted) {
        showSnack(context, context.l.scheduleSaved);
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final read = _read;

    return Scaffold(
      appBar: AppBar(title: Text(l.importSchedule)),
      body: PageBody(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),

            StepCard(
              step: 1,
              done: _text.text.trim().isNotEmpty || _images.isNotEmpty,
              title: l.importSchedule,
              subtitle: l.importScheduleHint,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _text,
                    maxLines: 8,
                    minLines: 4,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l.pasteSchedule,
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: Insets.lg),
                  Row(
                    children: [
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Insets.md),
                        child: Text(
                          l.orUploadPhoto,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(child: Divider(color: scheme.outlineVariant)),
                    ],
                  ),
                  const SizedBox(height: Insets.lg),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickImages,
                    icon: const Icon(Icons.upload_file_outlined, size: 19),
                    label: Text(l.orUploadPhoto),
                  ),
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: Insets.md),
                    for (final image in _images)
                      Padding(
                        padding: const EdgeInsets.only(bottom: Insets.sm),
                        child: Row(
                          children: [
                            Icon(
                              image.mimeType == 'application/pdf'
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.image_rounded,
                              size: 18,
                              color: scheme.primary,
                            ),
                            const SizedBox(width: Insets.md),
                            Expanded(
                              child: Text(
                                image.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            IconButton(
                              iconSize: 18,
                              onPressed: () =>
                                  setState(() => _images.remove(image)),
                              icon: Icon(Icons.close_rounded,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: Insets.lg),
                  FilledButton.icon(
                    onPressed: _busy ||
                            (_text.text.trim().isEmpty && _images.isEmpty)
                        ? null
                        : _read_,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                    label: Text(_busy ? l.readingSchedule : l.readSchedule),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: Insets.md),
                    ProgressBar(label: l.readingSchedule, value: _progress),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: Insets.lg),
                    InfoBanner(
                      message: _error!.hint == null
                          ? _error!.message
                          : '${_error!.message}\n${_error!.hint}',
                      icon: Icons.error_outline_rounded,
                      tone: BannerTone.error,
                    ),
                  ],
                ],
              ),
            ),

            // الجدول المدمج بيتسأل عنه قبل المراجعة: مفيش فايدة من مراجعة
            // محاضرات تلات أقسام وانت في واحد.
            // A merged timetable is asked about before the review: there is no
            // point checking three sections' lectures when you are in one.
            if (read != null && read.needsChoice) ...[
              const SizedBox(height: Insets.lg),
              StepCard(
                step: 2,
                done: _group != null,
                title: l.whichGroup(read.groupLabel),
                subtitle: read.note.isEmpty ? l.whichGroupHint : read.note,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.sm,
                      children: [
                        for (final group in read.groups)
                          FilterPill(
                            label: group,
                            selected: _group == group,
                            onTap: () => setState(() {
                              _group = group;
                              _dropped.clear();
                            }),
                          ),
                        FilterPill(
                          label: l.allGroups,
                          selected: _group == null,
                          onTap: () => setState(() {
                            _group = null;
                            _dropped.clear();
                          }),
                        ),
                      ],
                    ),
                    if (_group != null) ...[
                      const SizedBox(height: Insets.md),
                      Text(
                        l.groupPicked(_visible.length, read.entries.length),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],

            if (read != null) ...[
              const SizedBox(height: Insets.lg),
              StepCard(
                step: read.needsChoice ? 3 : 2,
                done: true,
                title: l.reviewBeforeSaving,
                subtitle: l.lecturesRead(_visible.length - _dropped.length),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _visible.length; i++)
                      _ReadRow(
                        lecture: _visible[i],
                        dropped: _dropped.contains(i),
                        onToggle: () => setState(() {
                          if (!_dropped.remove(i)) _dropped.add(i);
                        }),
                      ),
                    const SizedBox(height: Insets.lg),
                    FilledButton.icon(
                      onPressed: _saving ? null : () => _save(replace: false),
                      icon: const Icon(Icons.playlist_add_rounded, size: 19),
                      label: Text(l.addToSchedule),
                    ),
                    const SizedBox(height: Insets.sm),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : () => _save(replace: true),
                      icon: const Icon(Icons.restart_alt_rounded, size: 19),
                      label: Text(l.replaceSchedule),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReadRow extends StatelessWidget {
  const _ReadRow({
    required this.lecture,
    required this.dropped,
    required this.onToggle,
  });

  final ParsedLecture lecture;
  final bool dropped;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    String clock(int minutes) =>
        TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60).format(context);

    final when = [
      l.weekdayName(lecture.weekday),
      lecture.endMinutes == null
          ? clock(lecture.startMinutes)
          : '${clock(lecture.startMinutes)} - ${clock(lecture.endMinutes!)}',
      if (lecture.location.isNotEmpty) lecture.location,
      if (lecture.group.isNotEmpty) lecture.group,
    ].join(' · ');

    return Opacity(
      opacity: dropped ? 0.45 : 1,
      child: Row(
        children: [
          Checkbox(value: !dropped, onChanged: (_) => onToggle()),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    lecture.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      decoration: dropped ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    when,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
