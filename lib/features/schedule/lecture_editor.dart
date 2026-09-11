import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

/// خيارات التنبيه — دقايق قبل المحاضرة، وnull معناها مقفول.
/// The reminder choices: minutes before the lecture, with null meaning off.
const reminderChoices = <int?>[null, 5, 10, 15, 30, 60];

Future<void> openLectureEditor(
  BuildContext context,
  WidgetRef ref,
  ScheduleEntry? existing,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _LectureEditor(existing: existing),
  );
  if (saved == true) ref.invalidate(scheduleProvider);
}

class _LectureEditor extends ConsumerStatefulWidget {
  const _LectureEditor({this.existing});

  final ScheduleEntry? existing;

  @override
  ConsumerState<_LectureEditor> createState() => _LectureEditorState();
}

class _LectureEditorState extends ConsumerState<_LectureEditor> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _hall = TextEditingController(text: widget.existing?.location ?? '');
  late final _lecturer =
      TextEditingController(text: widget.existing?.lecturer ?? '');

  late int _weekday = widget.existing?.weekday ?? DateTime.now().weekday;
  late TimeOfDay _start = _timeOf(widget.existing?.startMinutes ?? 9 * 60);
  late TimeOfDay? _end = widget.existing?.endMinutes == null
      ? null
      : _timeOf(widget.existing!.endMinutes!);
  late String? _subjectId = widget.existing?.subjectId;
  late int? _remind = widget.existing?.remindMinutes ?? 15;
  bool _busy = false;

  static TimeOfDay _timeOf(int minutes) =>
      TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  @override
  void dispose() {
    _title.dispose();
    _hall.dispose();
    _lecturer.dispose();
    super.dispose();
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : (_end ?? _start.replacing(hour: _start.hour + 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);

    final existing = widget.existing;
    final entry = ScheduleEntry(
      id: existing?.id ?? '',
      title: title,
      weekday: _weekday,
      startMinutes: _start.hour * 60 + _start.minute,
      endMinutes: _end == null ? null : _end!.hour * 60 + _end!.minute,
      subjectId: _subjectId,
      location: _hall.text.trim(),
      lecturer: _lecturer.text.trim(),
      remindMinutes: _remind,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    final repo = ref.read(repositoryProvider);
    try {
      if (existing == null) {
        await repo.addScheduleEntry(entry);
      } else {
        await repo.updateScheduleEntry(entry);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showSnack(context, '$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final existing = widget.existing;

    return Padding(
      padding: EdgeInsets.only(
        left: Insets.xl,
        right: Insets.xl,
        top: Insets.xs,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Insets.xxl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    existing == null ? l.addLecture : l.editLecture,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (existing != null)
                  IconButton(
                    tooltip: l.delete,
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Theme.of(context).colorScheme.error),
                    onPressed: () async {
                      if (!await confirmDelete(context)) return;
                      await ref
                          .read(repositoryProvider)
                          .deleteScheduleEntry(existing.id);
                      if (context.mounted) Navigator.pop(context, true);
                    },
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _title,
              autofocus: existing == null,
              decoration: InputDecoration(labelText: l.lectureName),
            ),
            const SizedBox(height: Insets.lg),

            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: InputDecoration(labelText: l.day),
              items: [
                for (final day in const [6, 7, 1, 2, 3, 4, 5])
                  DropdownMenuItem(value: day, child: Text(l.weekdayName(day))),
              ],
              onChanged: (v) => setState(() => _weekday = v ?? _weekday),
            ),
            const SizedBox(height: Insets.lg),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(isStart: true),
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text('${l.startTime} ${_start.format(context)}'),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(isStart: false),
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: Text(_end == null
                        ? l.endTime
                        : '${l.endTime} ${_end!.format(context)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.lg),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hall,
                    decoration: InputDecoration(labelText: l.hall),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: TextField(
                    controller: _lecturer,
                    decoration: InputDecoration(labelText: l.lecturer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.lg),

            SubjectDropdown(
              subjects: subjects,
              value: _subjectId,
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: Insets.lg),

            DropdownButtonFormField<int?>(
              initialValue: reminderChoices.contains(_remind) ? _remind : null,
              decoration: InputDecoration(labelText: l.reminders),
              items: [
                for (final choice in reminderChoices)
                  DropdownMenuItem(
                    value: choice,
                    child: Text(
                      choice == null ? l.reminderOff : l.remindBefore(choice),
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _remind = v),
            ),

            const SizedBox(height: Insets.section),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(l.save),
            ),
          ],
        ),
      ),
    );
  }
}
