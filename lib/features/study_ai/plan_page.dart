import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../summarize/summarizer.dart';
import '../summarize/summarizer_provider.dart';
import 'study_ai.dart';

Future<void> openPlanPage(BuildContext context) => Navigator.of(context)
    .push<void>(MaterialPageRoute(builder: (_) => const PlanPage()));

/// خطة أسبوع مبنية على جدولك ومهامك وكروتك.
/// A week's plan built from your timetable, your tasks and your cards.
class PlanPage extends ConsumerStatefulWidget {
  const PlanPage({super.key});

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  StudyPlan? _plan;
  bool _busy = false;
  SummarizerException? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _make());
  }

  /// بيجمع وضع الطالب في نص واحد للموديل.
  /// Gathers the student's situation into one brief for the model.
  ///
  /// الحقائق بتتبعت زي ما هي — الجدول والمهام والكروت المستحقة. من غيرها الخطة
  /// بتبقى نصايح عامة ينفع تتقال لأي حد.
  /// The facts go as they are: the timetable, the open tasks, the cards due.
  /// Without them a plan is general advice that would suit anyone.
  String _facts(AppL10n l) {
    final schedule = ref.read(scheduleProvider).value ?? const <ScheduleEntry>[];
    final tasks = ref.read(tasksProvider).value ?? const <Task>[];
    final due = ref.read(dueCardsProvider);
    final subjects = ref.read(subjectMapProvider);

    String clock(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

    final buffer = StringBuffer()
      ..writeln('النهاردة: ${l.weekdayName(DateTime.now().weekday)}')
      ..writeln();

    buffer.writeln('### جدول المحاضرات:');
    if (schedule.isEmpty) {
      buffer.writeln('(مفيش جدول متسجل)');
    } else {
      for (final entry in schedule) {
        buffer.writeln(
          '- ${l.weekdayName(entry.weekday)} ${clock(entry.startMinutes)}: '
          '${entry.title}${entry.location.isEmpty ? '' : ' (${entry.location})'}',
        );
      }
    }
    buffer.writeln();

    buffer.writeln('### مهام مفتوحة:');
    final open = tasks.where((t) => !t.isDone).toList();
    if (open.isEmpty) {
      buffer.writeln('(مفيش)');
    } else {
      for (final task in open.take(20)) {
        final subject = subjects[task.subjectId]?.name;
        final dueDate = task.dueDate;
        buffer.writeln(
          '- ${task.title}'
          '${subject == null ? '' : ' [$subject]'}'
          '${dueDate == null ? '' : ' — تسليم ${dueDate.day}/${dueDate.month}'}'
          '${task.priority == TaskPriority.high ? ' (أولوية عالية)' : ''}',
        );
      }
    }
    buffer.writeln();

    buffer.writeln('### كروت مراجعة مستحقة: ${due.length}');
    final bySubject = <String, int>{};
    for (final card in due) {
      final name = subjects[card.subjectId]?.name ?? 'بدون مادة';
      bySubject[name] = (bySubject[name] ?? 0) + 1;
    }
    for (final entry in bySubject.entries) {
      buffer.writeln('- ${entry.key}: ${entry.value}');
    }
    buffer.writeln();
    buffer.writeln('اعمل خطة الأسبوع الجاي بالشكل المطلوب.');

    return buffer.toString();
  }

  Future<void> _make() async {
    setState(() {
      _busy = true;
      _error = null;
      _plan = null;
    });
    try {
      final plan =
          await ref.read(activeSummarizerProvider).makePlan(_facts(context.l));
      if (mounted) setState(() => _plan = plan);
    } on SummarizerException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// بيحوّل بند من الخطة لمهمة حقيقية.
  /// Turns one item of the plan into a real task.
  Future<void> _toTask(PlanItem item, int weekday) async {
    final now = DateTime.now();
    final days = (weekday - now.weekday) % 7;
    final when = DateTime(now.year, now.month, now.day).add(Duration(days: days));

    try {
      await ref.read(repositoryProvider).addTask(Task(
            id: '',
            title: item.what,
            details: item.why.isEmpty ? null : item.why,
            dueDate: when,
            priority: TaskPriority.medium,
            isDone: false,
            createdAt: now,
          ));
      ref.invalidate(tasksProvider);
      if (mounted) showSnack(context, context.l.addedToTasks);
    } catch (e) {
      if (mounted) showSnack(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final plan = _plan;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.weekPlan),
        actions: [
          if (!_busy)
            IconButton(
              tooltip: l.retry,
              onPressed: _make,
              icon: const Icon(Icons.refresh_rounded),
            ),
          const SizedBox(width: Insets.sm),
        ],
      ),
      body: PageBody(
        maxWidth: 760,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Insets.sm),

            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.section),
                child: ProgressBar(label: l.makingPlan),
              ),

            if (_error != null)
              InfoBanner(
                message: _error!.hint == null
                    ? _error!.message
                    : '${_error!.message}\n${_error!.hint}',
                icon: Icons.error_outline_rounded,
                tone: BannerTone.error,
                action: TextButton(onPressed: _make, child: Text(l.retry)),
              ),

            if (plan != null) ...[
              if (plan.note.isNotEmpty) ...[
                InfoBanner(message: plan.note),
                const SizedBox(height: Insets.lg),
              ],
              Text(
                l.planTotal(Fmt.minutes(context, plan.totalMinutes)),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              for (final day in plan.days) ...[
                Padding(
                  padding: const EdgeInsets.only(
                      top: Insets.xxl, bottom: Insets.md),
                  child: Row(
                    children: [
                      Text(l.weekdayName(day.weekday),
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(width: Insets.sm),
                      Text(
                        Fmt.minutes(context, day.totalMinutes),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                for (final item in day.items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Insets.sm),
                    child: _PlanRow(
                      item: item,
                      onAdd: () => _toTask(item, day.weekday),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.item, required this.onAdd});

  final PlanItem item;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return AppCard(
      padding: Insets.lg,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: Insets.md, vertical: Insets.sm),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: Radii.all(Radii.sm),
            ),
            child: Text(
              Fmt.minutes(context, item.minutes),
              style: text.labelSmall,
            ),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(item.what, style: text.bodyMedium),
                if (item.why.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.why,
                    style: text.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: l.addToTasks,
            onPressed: onAdd,
            iconSize: 19,
            icon: Icon(Icons.playlist_add_rounded, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}
