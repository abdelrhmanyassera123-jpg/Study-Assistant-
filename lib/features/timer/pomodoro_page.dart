import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
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
    final palette = AppPalette.of(context);
    final compact = Breakpoints.isCompact(context);

    // لكل مرحلة لونها: التركيز بلون الهوية، والراحة بألوان أهدى — عشان تعرف
    // انت في إيه من نظرة واحدة على الشاشة من بعيد.
    // Each phase carries its own colour: focus in the identity green, breaks in
    // quieter tones, so a glance from across the desk tells you where you are.
    final phaseColor = switch (state.phase) {
      PomodoroPhase.focus => scheme.primary,
      PomodoroPhase.shortBreak => palette.success,
      PomodoroPhase.longBreak => palette.warm,
    };
    final phaseLabel = switch (state.phase) {
      PomodoroPhase.focus => l.focus,
      PomodoroPhase.shortBreak => l.shortBreak,
      PomodoroPhase.longBreak => l.longBreak,
    };

    final dial = SizedBox(
      width: compact ? 248 : 288,
      height: compact ? 248 : 288,
      child: CustomPaint(
        painter: _RingPainter(
          progress: state.progress,
          color: phaseColor,
          trackColor: scheme.outlineVariant,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.clock(state.remainingSeconds),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      height: 1.1,
                    ),
              ),
              const SizedBox(height: Insets.sm),
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
    );

    return PageBody(
      maxWidth: 640,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Insets.lg),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg, vertical: Insets.sm),
              decoration: BoxDecoration(
                color: phaseColor.withValues(alpha: 0.13),
                borderRadius: Radii.all(Radii.xl),
              ),
              child: Text(
                phaseLabel,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: phaseColor),
              ),
            ),
          ),
          const SizedBox(height: Insets.section),
          Center(child: dial),
          const SizedBox(height: Insets.section),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.outlined(
                tooltip: l.reset,
                onPressed: controller.reset,
                icon: const Icon(Icons.refresh_rounded, size: 21),
              ),
              const SizedBox(width: Insets.xl),
              SizedBox(
                width: 168,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: phaseColor,
                    foregroundColor: scheme.surface,
                    minimumSize: const Size(0, 58),
                  ),
                  onPressed: () =>
                      state.isRunning ? controller.pause() : controller.start(),
                  icon: Icon(
                    state.isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 22,
                  ),
                  label: Text(
                    state.isRunning
                        ? l.pause
                        : (state.elapsedSeconds > 0 ? l.resume : l.start),
                  ),
                ),
              ),
              const SizedBox(width: Insets.xl),
              IconButton.outlined(
                tooltip: l.skip,
                onPressed: controller.skip,
                icon: const Icon(Icons.skip_next_rounded, size: 21),
              ),
            ],
          ),

          if (state.isFocus) ...[
            const SizedBox(height: Insets.section),
            SubjectDropdown(
              subjects: subjects,
              value: state.subjectId,
              onChanged: controller.setSubject,
            ),
          ],

          SectionHeader(
            l.today,
            action: TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const TimerSettingsSheet(),
              ),
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: Text(l.settings),
            ),
          ),
          const _TodaySummary(),
          const SizedBox(height: Insets.lg),
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
}

class _TodaySummary extends ConsumerWidget {
  const _TodaySummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final stats = ref.watch(statsProvider);
    return StatGrid(
      children: [
        StatTile(
          label: l.todayFocus,
          value: Fmt.minutes(context, stats.todayMinutes),
          icon: Icons.timelapse_rounded,
        ),
        StatTile(
          label: l.currentStreak,
          value: '${stats.streakDays}',
          icon: Icons.local_fire_department_rounded,
          color: AppPalette.of(context).warm,
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
      padding: const EdgeInsets.fromLTRB(Insets.xl, 0, Insets.xl, Insets.section),
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
