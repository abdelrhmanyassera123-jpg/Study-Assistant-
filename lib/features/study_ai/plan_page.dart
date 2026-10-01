import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _kHours = 'plan_daily_hours';

  StudyPlan? _plan;
  int _dailyHours = 4;
  bool _busy = false;
  SummarizerException? _error;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _dailyHours = p.getInt(_kHours) ?? 4);
      _make();
    });
  }

  void _setHours(int hours) {
    setState(() => _dailyHours = hours);
    SharedPreferences.getInstance().then((p) => p.setInt(_kHours, hours));
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
    final notes = ref.read(notesProvider).value ?? const <Note>[];
    final cards = ref.read(cardsProvider).value ?? const <Flashcard>[];
    final due = ref.read(dueCardsProvider);
    final subjects = ref.read(subjectMapProvider);
    final now = DateTime.now();

    String clock(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    String subjectOf(String? id) => subjects[id]?.name ?? 'بدون مادة';
    String kind(String t) => switch (t) {
          'section' => 'سكشن',
          'lab' => 'لاب',
          'lecture' => 'محاضرة',
          _ => '',
        };

    final buffer = StringBuffer()
      ..writeln('النهاردة: ${l.weekdayName(now.weekday)} '
          '${now.day}/${now.month} — الساعة ${clock(now.hour * 60 + now.minute)}')
      ..writeln('الهدف اليومي للمذاكرة: حوالي $_dailyHours ساعات '
          '(غير المحاضرات نفسها).')
      ..writeln();

    // الأيام السبعة الجاية بالترتيب، وكل يوم فيه محاضراته والأوقات الفاضية —
    // من غيرها الموديل بيحط مذاكرة فوق محاضرة أو بيسيب اليوم فاضي.
    // The next seven days in order, each with its lectures and its free
    // windows — without them the model stacks study on top of a lecture or
    // leaves the day empty.
    buffer.writeln('### الأيام السبعة الجاية:');
    for (var i = 0; i < 7; i++) {
      final day = now.add(Duration(days: i));
      final entries = schedule.where((e) => e.weekday == day.weekday).toList()
        ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
      buffer.writeln('${l.weekdayName(day.weekday)} ${day.day}/${day.month}:');
      if (entries.isEmpty) {
        buffer.writeln('  - مفيش محاضرات (يوم فاضي)');
      }
      var free = i == 0 ? now.hour * 60 + now.minute : 8 * 60;
      final windows = <String>[];
      for (final e in entries) {
        final end = e.endMinutes ?? e.startMinutes + 90;
        buffer.writeln('  - ${clock(e.startMinutes)}–${clock(end)} '
            '${kind(e.sessionType)} ${e.title} [${subjectOf(e.subjectId)}]'
            '${e.lecturer.isEmpty ? '' : ' — ${e.lecturer}'}');
        if (e.startMinutes - free >= 45) {
          windows.add('${clock(free)}–${clock(e.startMinutes)}');
        }
        if (end > free) free = end + 30;
      }
      if (24 * 60 - free >= 45) windows.add('${clock(free)}–24:00');
      buffer.writeln('  أوقات فاضية: ${windows.isEmpty ? 'مفيش' : windows.join('، ')}');
    }
    buffer.writeln();

    // اللي اتشرح فعلاً: التلخيصات المحفوظة في آخر أسبوعين بتاريخها، عشان
    // المراجعة تبقى باسم المحاضرة مش "راجع المادة".
    // What was actually taught: summaries saved in the last two weeks with
    // their dates, so a review names the lecture rather than "review the
    // subject".
    buffer.writeln('### محاضرات اتلخصت مؤخرًا (محتاجة مراجعة متباعدة):');
    final recent = notes
        .where((n) => now.difference(n.createdAt).inDays <= 14)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (recent.isEmpty) {
      buffer.writeln('(مفيش)');
    } else {
      for (final n in recent.take(25)) {
        final ago = now.difference(n.createdAt).inDays;
        buffer.writeln('- ${n.title} [${subjectOf(n.subjectId)}] — '
            '${ago == 0 ? 'النهاردة' : 'من $ago يوم'}');
      }
    }
    buffer.writeln();

    buffer.writeln('### مهام مفتوحة:');
    final open = tasks.where((t) => !t.isDone).toList();
    if (open.isEmpty) {
      buffer.writeln('(مفيش)');
    } else {
      for (final task in open.take(25)) {
        final dueDate = task.dueDate;
        buffer.writeln(
          '- ${task.title} [${subjectOf(task.subjectId)}]'
          '${dueDate == null ? '' : ' — تسليم ${dueDate.day}/${dueDate.month}'}'
          '${task.priority == TaskPriority.high ? ' (أولوية عالية)' : ''}',
        );
      }
    }
    buffer.writeln();

    buffer.writeln('### الكروت: ${due.length} مستحقة دلوقتي من ${cards.length}');
    final bySubject = <String, int>{};
    for (final card in due) {
      final name = subjectOf(card.subjectId);
      bySubject[name] = (bySubject[name] ?? 0) + 1;
    }
    for (final entry in bySubject.entries) {
      buffer.writeln('- ${entry.key}: ${entry.value} مستحقة');
    }
    final weak = <String, int>{};
    for (final card in cards.where((c) => c.lapses >= 2)) {
      final name = subjectOf(card.subjectId);
      weak[name] = (weak[name] ?? 0) + 1;
    }
    for (final entry in weak.entries) {
      buffer.writeln('- ${entry.key}: ${entry.value} كارت بيتنسى كتير (نقطة ضعف)');
    }
    buffer.writeln();
    buffer.writeln('اعمل خطة السبع أيام دول بالتفصيل وبالشكل المطلوب.');

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
            Text(l.dailyStudyGoal, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final h in const [2, 3, 4, 5, 6, 8])
                  FilterPill(
                    label: l.hoursShort(h),
                    selected: _dailyHours == h,
                    onTap: _busy ? () {} : () => _setHours(h),
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),

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
                if (day.focus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Insets.md),
                    child: Text(
                      day.focus,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.primary),
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
              color: item.kind == 'break'
                  ? scheme.tertiaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: Radii.all(Radii.sm),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.time.isNotEmpty)
                  Text(
                    item.time,
                    textDirection: TextDirection.ltr,
                    style: text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                Text(Fmt.minutes(context, item.minutes), style: text.labelSmall),
              ],
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
          if (item.kind != 'break')
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
