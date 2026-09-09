import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/providers.dart';

enum PomodoroPhase { focus, shortBreak, longBreak }

class PomodoroState {
  const PomodoroState({
    required this.phase,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.isRunning,
    required this.completedRounds,
    this.subjectId,
    this.startedAt,
  });

  final PomodoroPhase phase;
  final int remainingSeconds;
  final int totalSeconds;
  final bool isRunning;

  /// عدد جلسات التركيز اللي خلصت في الدورة الحالية.
  /// Focus rounds completed in the current cycle.
  final int completedRounds;

  final String? subjectId;

  /// وقت بداية المرحلة الحالية — بيتسجل مع الجلسة.
  /// When the current phase began; stored with the logged session.
  final DateTime? startedAt;

  bool get isFocus => phase == PomodoroPhase.focus;
  double get progress =>
      totalSeconds == 0 ? 0 : (totalSeconds - remainingSeconds) / totalSeconds;
  int get elapsedSeconds => totalSeconds - remainingSeconds;

  PomodoroState copyWith({
    PomodoroPhase? phase,
    int? remainingSeconds,
    int? totalSeconds,
    bool? isRunning,
    int? completedRounds,
    String? subjectId,
    bool clearSubject = false,
    DateTime? startedAt,
    bool clearStartedAt = false,
  }) {
    return PomodoroState(
      phase: phase ?? this.phase,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      isRunning: isRunning ?? this.isRunning,
      completedRounds: completedRounds ?? this.completedRounds,
      subjectId: clearSubject ? null : (subjectId ?? this.subjectId),
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
    );
  }
}

/// مؤقت البومودورو. عايش على مستوى التطبيق عشان يفضل شغال وانت بتتنقل بين الأقسام.
/// The Pomodoro timer. It lives at app level so it keeps running while you
/// move between sections.
class PomodoroController extends Notifier<PomodoroState> {
  Timer? _ticker;

  @override
  PomodoroState build() {
    // بيفضل عايش حتى لو مفيش صفحة بتتفرج عليه — عشان المؤقت ما يقفش وانت بتتنقل.
    // Stays alive even when no page is watching, so the countdown survives navigation.
    ref.keepAlive();
    ref.onDispose(() => _ticker?.cancel());

    // لو المستخدم غيّر المدد والمؤقت واقف، نعكس التغيير على طول.
    // Reflect length changes immediately while the timer is idle.
    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if (!state.isRunning && state.elapsedSeconds == 0) {
        final secs = _phaseSeconds(state.phase, next);
        state = state.copyWith(remainingSeconds: secs, totalSeconds: secs);
      }
    });

    final focusSeconds = ref.read(settingsProvider).focusMinutes * 60;
    return PomodoroState(
      phase: PomodoroPhase.focus,
      remainingSeconds: focusSeconds,
      totalSeconds: focusSeconds,
      isRunning: false,
      completedRounds: 0,
    );
  }

  /// آخر مرحلة خلصت — الواجهة بتقرأها عشان تعرض رسالة.
  /// The phase that just finished, for the UI to announce.
  PomodoroPhase? lastCompletedPhase;

  static int _phaseSeconds(PomodoroPhase phase, AppSettings s) => switch (phase) {
        PomodoroPhase.focus => s.focusMinutes * 60,
        PomodoroPhase.shortBreak => s.shortBreakMinutes * 60,
        PomodoroPhase.longBreak => s.longBreakMinutes * 60,
      };

  void setSubject(String? id) =>
      state = id == null ? state.copyWith(clearSubject: true) : state.copyWith(subjectId: id);

  void start() {
    if (state.isRunning) return;
    state = state.copyWith(
      isRunning: true,
      startedAt: state.startedAt ?? DateTime.now(),
    );
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(isRunning: false);
  }

  /// بيوقف ويرجّع المرحلة من أولها. لو كان في تركيز فعلي، بيتسجل الأول.
  /// Stops and rewinds the phase, logging any real focus time first.
  Future<void> reset() async {
    _ticker?.cancel();
    _ticker = null;
    await _logFocusIfWorthwhile();
    final secs = _phaseSeconds(state.phase, ref.read(settingsProvider));
    state = state.copyWith(
      isRunning: false,
      remainingSeconds: secs,
      totalSeconds: secs,
      clearStartedAt: true,
    );
  }

  /// يعدّي للمرحلة الجاية من غير ما يستنى المؤقت.
  /// Jumps to the next phase without waiting for the countdown.
  Future<void> skip() async {
    _ticker?.cancel();
    _ticker = null;
    await _logFocusIfWorthwhile();
    _advance(countRound: false);
  }

  void _tick() {
    final left = state.remainingSeconds - 1;
    if (left > 0) {
      state = state.copyWith(remainingSeconds: left);
      return;
    }
    _ticker?.cancel();
    _ticker = null;
    unawaited(_complete());
  }

  Future<void> _complete() async {
    lastCompletedPhase = state.phase;
    // بيب خفيف على الموبايل والديسكتوب؛ على الويب المتصفح بيتجاهله.
    // A short chime on mobile and desktop; browsers ignore it.
    unawaited(SystemSound.play(SystemSoundType.alert));

    if (state.isFocus) {
      await _logSession(state.totalSeconds);
    }
    _advance(countRound: state.isFocus);

    if (ref.read(settingsProvider).autoStartNext) start();
  }

  /// يحدد المرحلة الجاية: تركيز -> راحة (قصيرة أو طويلة)، وراحة -> تركيز.
  /// Picks the next phase: focus -> break (short or long), break -> focus.
  void _advance({required bool countRound}) {
    final s = ref.read(settingsProvider);
    final rounds = countRound ? state.completedRounds + 1 : state.completedRounds;

    final PomodoroPhase next;
    if (state.isFocus) {
      next = (rounds > 0 && rounds % s.roundsBeforeLongBreak == 0)
          ? PomodoroPhase.longBreak
          : PomodoroPhase.shortBreak;
    } else {
      next = PomodoroPhase.focus;
    }

    final secs = _phaseSeconds(next, s);
    state = PomodoroState(
      phase: next,
      remainingSeconds: secs,
      totalSeconds: secs,
      isRunning: false,
      completedRounds: rounds,
      subjectId: state.subjectId,
    );
  }

  /// بنسجل بس لو المستخدم ذاكر دقيقة على الأقل — عشان ما نزحمش الإحصائيات.
  /// Only log a minute or more, so stray taps don't pollute the stats.
  Future<void> _logFocusIfWorthwhile() async {
    if (state.isFocus && state.elapsedSeconds >= 60) {
      await _logSession(state.elapsedSeconds);
    }
  }

  Future<void> _logSession(int seconds) async {
    try {
      await ref.read(repositoryProvider).logSession(
            startedAt: state.startedAt ?? DateTime.now(),
            durationSeconds: seconds,
            subjectId: state.subjectId,
          );
      ref.invalidate(sessionsProvider);
    } catch (_) {
      // لو النت قطع، ما نوقفش المؤقت عشان خطأ في التسجيل.
      // A failed write shouldn't break the timer the user is watching.
    }
  }

}

final pomodoroProvider =
    NotifierProvider<PomodoroController, PomodoroState>(PomodoroController.new);
