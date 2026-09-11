import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  bool _showDone = false;
  String? _subjectFilter;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final tasksAsync = ref.watch(tasksProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTaskEditor(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: Text(l.addTask),
      ),
      body: tasksAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(tasksProvider)),
        data: (all) {
          final visible = all
              .where((t) => t.isDone == _showDone)
              .where((t) =>
                  _subjectFilter == null || t.subjectId == _subjectFilter)
              .toList();

          // قايمة المهام أضيق من باقي الصفحات: السطر الطويل أصعب في المسح
          // السريع بالعين، والمهمة المفروض تتقرا بنظرة.
          // The task list is narrower than other pages: long lines are harder
          // to scan, and a task should be readable at a glance.
          return PageBody(
            maxWidth: 760,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Filters(
                  showDone: _showDone,
                  subjects: subjects,
                  subjectFilter: _subjectFilter,
                  openCount: all.where((t) => !t.isDone).length,
                  doneCount: all.where((t) => t.isDone).length,
                  onShowDone: (v) => setState(() => _showDone = v),
                  onSubject: (v) => setState(() => _subjectFilter = v),
                ),
                if (visible.isEmpty)
                  EmptyState(
                    icon: _showDone
                        ? Icons.done_all_rounded
                        : Icons.checklist_rounded,
                    title: _showDone ? l.noTasksDone : l.noTasksYet,
                    message: _showDone ? l.doneHint : l.tasksEmptyHint,
                    action: _showDone
                        ? null
                        : FilledButton.icon(
                            onPressed: () => openTaskEditor(context, ref, null),
                            icon: const Icon(Icons.add_rounded, size: 19),
                            label: Text(l.addTask),
                          ),
                  )
                else
                  ..._buildGroups(visible),
              ],
            ),
          );
        },
      ),
    );
  }

  /// المهام المفتوحة بتتقسم لمجموعات حسب الاستحقاق؛ الخالصة قايمة واحدة.
  /// Open tasks are grouped by when they're due; done tasks are one flat list.
  List<Widget> _buildGroups(List<Task> tasks) {
    final l = context.l;
    if (_showDone) {
      return [
        const SizedBox(height: Insets.lg),
        for (final t in tasks) _tile(t),
      ];
    }

    final overdue = tasks.where((t) => t.isOverdue).toList();
    final today = tasks.where((t) => !t.isOverdue && t.isDueToday).toList();
    final upcoming = tasks
        .where((t) => !t.isOverdue && !t.isDueToday && t.dueDate != null)
        .toList();
    final undated = tasks.where((t) => t.dueDate == null).toList();

    return [
      for (final (title, group) in [
        (l.overdue, overdue),
        (l.today, today),
        (l.upcomingTasks, upcoming),
        (l.noDueDate, undated),
      ])
        if (group.isNotEmpty) ...[
          _GroupHeader(title: title, count: group.length),
          for (final t in group) _tile(t),
        ],
    ];
  }

  Widget _tile(Task task) => Padding(
        padding: const EdgeInsets.only(bottom: Insets.sm),
        child: TaskTile(task: task),
      );
}

/// عنوان مجموعة بعدّادها — العدد بيوضّح حجم الشغل من غير ما تعدّ بنفسك.
/// A group heading with its count, so the size of the pile shows without
/// counting rows.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: Insets.xxl, bottom: Insets.md),
      child: Row(
        children: [
          Text(title, style: text.titleSmall),
          const SizedBox(width: Insets.sm),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 1),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: Radii.all(Radii.sm),
            ),
            child: Text(
              '$count',
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.showDone,
    required this.subjects,
    required this.subjectFilter,
    required this.openCount,
    required this.doneCount,
    required this.onShowDone,
    required this.onSubject,
  });

  final bool showDone;
  final List<Subject> subjects;
  final String? subjectFilter;
  final int openCount;
  final int doneCount;
  final ValueChanged<bool> onShowDone;
  final ValueChanged<String?> onSubject;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Insets.sm),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(
                '${l.pending} ($openCount)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            ButtonSegment(
              value: true,
              label: Text(
                '${l.completed} ($doneCount)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          selected: {showDone},
          showSelectedIcon: false,
          onSelectionChanged: (s) => onShowDone(s.first),
        ),
        if (subjects.isNotEmpty) ...[
          const SizedBox(height: Insets.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterPill(
                  label: l.all,
                  selected: subjectFilter == null,
                  onTap: () => onSubject(null),
                ),
                for (final s in subjects) ...[
                  const SizedBox(width: Insets.sm),
                  FilterPill(
                    label: s.name,
                    dot: s.color,
                    selected: subjectFilter == s.id,
                    onTap: () =>
                        onSubject(subjectFilter == s.id ? null : s.id),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// صف المهمة — مربع اختيار، عنوان، وسطر بيانات صغير.
/// A task row: a checkbox, a title, and one small line of metadata.
class TaskTile extends ConsumerWidget {
  const TaskTile({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final subject = ref.watch(subjectMapProvider)[task.subjectId];
    final overdue = task.isOverdue && !task.isDone;
    final hasMeta = subject != null ||
        task.dueDate != null ||
        task.priority == TaskPriority.high;

    return AppCard(
      padding: Insets.sm,
      onTap: () => openTaskEditor(context, ref, task),
      // المتأخر بياخد حد أحمر خفيف بدل خلفية ملونة: التمييز يبان من غير ما
      // الصف يصرخ في وش المستخدم كل مرة يفتح الصفحة.
      // Overdue rows take a soft red border rather than a coloured fill: the
      // distinction shows without the row shouting on every visit.
      border: overdue ? scheme.error.withValues(alpha: 0.45) : null,
      child: Row(
        children: [
          Checkbox(
            value: task.isDone,
            onChanged: (v) async {
              await ref.read(repositoryProvider).setTaskDone(task, v ?? false);
              ref.invalidate(tasksProvider);
              ref.invalidate(sessionsProvider);
            },
          ),
          const SizedBox(width: Insets.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          decoration:
                              task.isDone ? TextDecoration.lineThrough : null,
                          color: task.isDone ? scheme.onSurfaceVariant : null,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (hasMeta) ...[
                    const SizedBox(height: Insets.sm),
                    Wrap(
                      spacing: Insets.md,
                      runSpacing: Insets.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (subject != null)
                          SubjectChip(subject: subject, dense: true),
                        if (task.dueDate != null)
                          _MetaText(
                            icon: Icons.event_rounded,
                            text: Fmt.date(context, task.dueDate!),
                            color: overdue
                                ? scheme.error
                                : scheme.onSurfaceVariant,
                          ),
                        if (task.priority == TaskPriority.high)
                          _MetaText(
                            icon: Icons.flag_rounded,
                            text: context.l.priorityHigh,
                            color: palette.warm,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: Insets.sm),
          IconButton(
            tooltip: context.l.delete,
            iconSize: 19,
            onPressed: () async {
              if (!await confirmDelete(context)) return;
              await ref.read(repositoryProvider).deleteTask(task.id);
              ref.invalidate(tasksProvider);
            },
            icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// فورم إضافة/تعديل مهمة — بينفتح من صفحة المهام ومن اللوحة الرئيسية.
/// The add/edit task form, opened from the tasks page and the dashboard.
Future<void> openTaskEditor(BuildContext context, WidgetRef ref, Task? existing) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TaskEditor(existing: existing),
  );
  if (saved == true) {
    ref.invalidate(tasksProvider);
  }
}

class _TaskEditor extends ConsumerStatefulWidget {
  const _TaskEditor({this.existing});

  final Task? existing;

  @override
  ConsumerState<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends ConsumerState<_TaskEditor> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _details = TextEditingController(text: widget.existing?.details ?? '');
  late String? _subjectId = widget.existing?.subjectId;
  late DateTime? _due = widget.existing?.dueDate;
  late TaskPriority _priority = widget.existing?.priority ?? TaskPriority.medium;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    setState(() => _busy = true);

    final repo = ref.read(repositoryProvider);
    final existing = widget.existing;
    final details = _details.text.trim();

    final task = Task(
      id: existing?.id ?? '',
      title: title,
      details: details.isEmpty ? null : details,
      subjectId: _subjectId,
      dueDate: _due,
      priority: _priority,
      isDone: existing?.isDone ?? false,
      completedAt: existing?.completedAt,
      createdAt: existing?.createdAt ?? DateTime.now(),
    );

    try {
      if (existing == null) {
        await repo.addTask(task);
      } else {
        await repo.updateTask(task);
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

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? l.addTask : l.editTask,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              autofocus: true,
              decoration: InputDecoration(labelText: l.taskTitle),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _details,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                labelText: '${l.taskNotes} (${l.optional})',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            SubjectDropdown(
              subjects: subjects,
              value: _subjectId,
              onChanged: (v) => setState(() => _subjectId = v),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_rounded),
              label: Text(_due == null ? l.dueDate : Fmt.date(context, _due!)),
            ),
            if (_due != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => setState(() => _due = null),
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: Text(l.noDueDate),
                ),
              ),
            const SizedBox(height: 14),
            Text(l.priority, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<TaskPriority>(
              segments: [
                ButtonSegment(value: TaskPriority.low, label: Text(l.priorityLow)),
                ButtonSegment(value: TaskPriority.medium, label: Text(l.priorityMedium)),
                ButtonSegment(value: TaskPriority.high, label: Text(l.priorityHigh)),
              ],
              selected: {_priority},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
            const SizedBox(height: 26),
            FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
          ],
        ),
      ),
    );
  }
}
