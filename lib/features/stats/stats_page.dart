import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../data/providers.dart';
import '../../data/stats.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';

class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final stats = ref.watch(statsProvider);
    final sessionsAsync = ref.watch(sessionsProvider);
    final reviews = ref.watch(weeklyReviewsProvider).value ?? 0;

    if (sessionsAsync.isLoading && sessionsAsync.value == null) {
      return const LoadingView();
    }
    if (sessionsAsync.hasError && sessionsAsync.value == null) {
      return ErrorView(
        error: sessionsAsync.error!,
        onRetry: () => ref.invalidate(sessionsProvider),
      );
    }
    if (stats.isEmpty) {
      return EmptyState(icon: Icons.insights_outlined, message: l.notEnoughData);
    }

    return PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Insets.sm),
          StatGrid(
            children: [
              StatTile(
                label: l.thisWeek,
                value: Fmt.minutes(context, stats.weekMinutes),
                icon: Icons.calendar_view_week_rounded,
              ),
              StatTile(
                label: l.currentStreak,
                value: '${stats.streakDays}',
                icon: Icons.local_fire_department_rounded,
                color: AppPalette.of(context).warm,
              ),
              StatTile(
                label: l.dailyAverage,
                value: Fmt.minutes(context, stats.dailyAverageMinutes.round()),
                icon: Icons.show_chart_rounded,
                color: AppPalette.of(context).success,
              ),
              StatTile(
                label: l.sessionsCount,
                value: '${stats.sessionCount}',
                icon: Icons.timelapse_rounded,
              ),
              StatTile(
                label: l.cardsReviewed,
                value: '$reviews',
                icon: Icons.style_rounded,
                color: scheme.tertiary,
              ),
              StatTile(
                label: l.tasksCompleted,
                value: '${stats.tasksCompletedThisWeek}',
                icon: Icons.task_alt_rounded,
                color: scheme.secondary,
              ),
            ],
          ),
          SectionHeader(l.last7Days),
          AppCard(
            padding: Insets.lg,
            child: SizedBox(height: 210, child: _WeekChart(stats: stats)),
          ),
          SectionHeader(l.bySubject),
          _SubjectBreakdown(stats: stats),
        ],
      ),
    );
  }
}

/// أعمدة دقايق المذاكرة لآخر 7 أيام.
/// Focus minutes per day for the last week.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.stats});

  final StudyStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = stats.last7Days;
    final maxMinutes = days.map((d) => d.minutes).fold<int>(0, (a, b) => a > b ? a : b);
    // سقف مريح فوق أعلى عمود عشان الأرقام ما تلزقش في السقف.
    // Headroom above the tallest bar so labels don't touch the top.
    final maxY = (maxMinutes <= 0 ? 60 : (maxMinutes * 1.25)).toDouble();

    return BarChart(
      BarChartData(
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Text(
                value.round() == 0 ? '' : '${value.round()}',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    Fmt.weekday(context, days[i].day),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              Fmt.minutes(context, rod.toY.round()),
              TextStyle(color: scheme.onInverseSurface, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: days[i].minutes.toDouble(),
                  width: 20,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  color: i == days.length - 1
                      ? scheme.primary
                      : scheme.primary.withValues(alpha: 0.45),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// توزيع وقت المذاكرة على المواد.
/// How focus time splits across subjects.
class _SubjectBreakdown extends ConsumerWidget {
  const _SubjectBreakdown({required this.stats});

  final StudyStats stats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final subjects = ref.watch(subjectMapProvider);
    final scheme = Theme.of(context).colorScheme;

    final entries = stats.minutesBySubject.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty) {
      return AppCard(
        padding: Insets.xxl,
        child: Center(
          child: Text(
            l.notEnoughData,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return AppCard(
      child: Column(
        children: [
          for (final e in entries) ...[
            _SubjectRow(
              subject: subjects[e.key],
              minutes: e.value,
              fraction: total == 0 ? 0 : e.value / total,
            ),
            if (e != entries.last) const SizedBox(height: Insets.lg),
          ],
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.subject,
    required this.minutes,
    required this.fraction,
  });

  final Subject? subject;
  final int minutes;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = subject?.color ?? scheme.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                subject?.name ?? context.l.noSubject,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${Fmt.minutes(context, minutes)}  ·  ${(fraction * 100).round()}%',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        ClipRRect(
          borderRadius: Radii.all(Insets.sm),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}
