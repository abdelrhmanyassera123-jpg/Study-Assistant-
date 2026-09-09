import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../data/stats.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import 'pomodoro_controller.dart';

class PomodoroPage extends ConsumerWidget {
  const PomodoroPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final state = ref.watch(pomodoroProvider);
    final controller = ref.read(pomodoroProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final subjects = ref.watch(subjectsProvider).value ?? const <Subject>[];
    final scheme = Theme.of(context).colorScheme;

    final phaseColor = switch (state.phase) {
      PomodoroPhase.focus => scheme.primary,
      PomodoroPhase.shortBreak => const Color(0xFF10B981),
      PomodoroPhase.longBreak => const Color(0xFF0EA5E9),
    };
    final phaseLabel = switch (state.phase) {
      PomodoroPhase.focus => l.focus,
      PomodoroPhase.shortBreak => l.shortBreak,
      PomodoroPhase.longBreak => l.longBreak,
    };

    return PageBody(
      maxWidth: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: phaseColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                phaseLabel,
                style: TextStyle(color: phaseColor, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: SizedBox(
              width: 260,
              height: 260,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: state.progress,
                  color: phaseColor,
                  trackColor: scheme.outlineVariant.withValues(alpha: 0.4),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Fmt.clock(state.remainingSeconds),
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${l.round} ${state.completedRounds + 1}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: l.reset,
                iconSize: 22,
                onPressed: () => controller.reset(),
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 18),
              SizedBox(
                width: 150,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: phaseColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  onPressed: () => state.isRunning ? controller.pause() : controller.start(),
                  icon: Icon(state.isRunning
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(
                    state.isRunning
                        ? l.pause
                        : (state.elapsedSeconds > 0 ? l.resume : l.start),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              IconButton.outlined(
                tooltip: l.skip,
                iconSize: 22,
                onPressed: () => controller.skip(),
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          const SizedBox(height: 32),
          if (state.isFocus)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: SubjectDropdown(
                  subjects: subjects,
                  value: state.subjectId,
                  onChanged: controller.setSubject,
                ),
              ),
            ),
          SectionHeader(
            l.today,
            action: TextButton.icon(
              onPressed: () => _openTimerSettings(context, ref),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: Text(l.settings),
            ),
          ),
          const _TodaySummary(),
          const SizedBox(height: 8),
          Text(
            l.isAr
                ? 'كل ${settings.focusMinutes} دقيقة تركيز بتتسجل تلقائي في إحصائياتك.'
                : 'Every ${settings.focusMinutes}-minute focus block is logged to your stats.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  void _openTimerSettings(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const TimerSettingsSheet(),
    );
  }
}

class _TodaySummary extends ConsumerWidget {
  const _TodaySummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final stats = ref.watch(statsProvider);
    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: l.todayFocus,
            value: Fmt.minutes(context, stats.todayMinutes),
            icon: Icons.timer_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: l.currentStreak,
            value: '${stats.streakDays}',
            icon: Icons.local_fire_department_rounded,
            color: const Color(0xFFF59E0B),
          ),
        ),
      ],
    );
  }
}

/// إعدادات مدد المؤقت — بتتحفظ محليًا وبتنطبق على المرحلة الجاية.
/// Timer lengths; stored locally and applied to the next phase.
class TimerSettingsSheet extends ConsumerWidget {
  const TimerSettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.timer,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _MinuteSlider(
              label: l.focusLength,
              value: s.focusMinutes,
              min: 5,
              max: 90,
              step: 5,
              onChanged: (v) => notifier.setTimerConfig(focus: v),
            ),
            _MinuteSlider(
              label: l.shortBreakLength,
              value: s.shortBreakMinutes,
              min: 1,
              max: 30,
              step: 1,
              onChanged: (v) => notifier.setTimerConfig(shortBreak: v),
            ),
            _MinuteSlider(
              label: l.longBreakLength,
              value: s.longBreakMinutes,
              min: 5,
              max: 60,
              step: 5,
              onChanged: (v) => notifier.setTimerConfig(longBreak: v),
            ),
            _MinuteSlider(
              label: l.roundsBeforeLong,
              value: s.roundsBeforeLongBreak,
              min: 2,
              max: 8,
              step: 1,
              suffix: '',
              onChanged: (v) => notifier.setTimerConfig(rounds: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.autoStartNext),
              value: s.autoStartNext,
              onChanged: (v) => notifier.setTimerConfig(autoStart: v),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinuteSlider extends StatelessWidget {
  const _MinuteSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.suffix,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final String? suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
              Text(
                '$value${suffix ?? ''}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Slider(
            value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: ((max - min) / step).round(),
            onChanged: (v) => onChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

/// حلقة التقدم حوالين العداد.
/// The progress ring around the countdown.
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress.clamp(0.0, 1.0),
        false,
        arc,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.trackColor != trackColor;
}
