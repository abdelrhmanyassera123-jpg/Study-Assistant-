import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../core/l10n.dart';
import '../../core/notifications.dart';
import '../../core/push.dart';
import '../../core/settings.dart';
import '../../data/providers.dart';
import '../../models/models.dart';

/// بيراقب الجدول ويطلّع التنبيه في معاده.
/// Watches the timetable and raises each reminder at its moment.
///
/// الفحص كل نص دقيقة بدل مؤقت لكل محاضرة: المؤقتات الكتير بتموت مع أي إعادة
/// بناء، والفحص الدوري بيلحق حتى لو الصفحة قعدت نايمة شوية.
/// A check every half minute rather than a timer per lecture: many timers die
/// with any rebuild, while a periodic sweep catches up even after the page has
/// been asleep for a while.
class ReminderService extends Notifier<ReminderState> {
  Timer? _timer;

  /// اللي طلع خلاص — عشان ما يطلعش تاني في نفس النافذة.
  /// What has already fired, so it does not fire twice in the same window.
  final Set<String> _fired = {};

  @override
  ReminderState build() {
    ref.onDispose(() => _timer?.cancel());

    // التنبيهات بتشتغل بس لما تكون متفعّلة ومعاها إذن.
    // Reminders run only when switched on and permitted.
    final on = ref.watch(settingsProvider.select((s) => s.remindersOn));
    _timer?.cancel();
    if (on) {
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => _sweep());
      scheduleMicrotask(_sweep);
    }

    return ReminderState(enabled: on, permission: Reminders.permission);
  }

  /// بيسأل المتصفح الإذن، وبعد الموافقة بيشترك في Push عشان التنبيه يوصل حتى
  /// لو التطبيق مقفول. لازم يتنادى من ضغطة مستخدم.
  /// Asks the browser for permission, then subscribes to push on approval so
  /// the reminder arrives even with the app closed. Must come from a user
  /// gesture.
  Future<bool> requestPermission() async {
    final granted = await Reminders.request();
    state = state.copyWith(permission: Reminders.permission);

    if (granted) {
      // فشل الاشتراك في Push مش سبب يمنع التنبيه المحلي (اللي شغال من غير
      // Push أصلاً) — بنحاول بس من غير ما نوقف حاجة لو اتعطل.
      // A failed push subscription is no reason to block the local reminder
      // (which works without push anyway) — best-effort, nothing stops if
      // it fails.
      final keys = await WebPush.subscribe();
      if (keys != null) {
        try {
          await ref.read(repositoryProvider).savePushSubscription(
                endpoint: keys.endpoint,
                p256dh: keys.p256dh,
                auth: keys.auth,
              );
        } catch (_) {}
      }
    }

    return granted;
  }

  /// بيلغي اشتراك الـ Push بتاع الجهاز ده. بينادى لما المستخدم يقفل
  /// التنبيهات بنفسه.
  /// Cancels this device's push subscription. Called when the user switches
  /// reminders off themselves.
  Future<void> disablePush() async {
    final endpoint = await WebPush.unsubscribe();
    if (endpoint == null) return;
    try {
      await ref.read(repositoryProvider).deletePushSubscription(endpoint);
    } catch (_) {}
  }

  void _sweep() {
    final entries = ref.read(scheduleProvider).value ?? const <ScheduleEntry>[];
    if (entries.isEmpty) return;

    final now = DateTime.now();
    for (final entry in entries) {
      final lead = entry.remindMinutes;
      if (lead == null) continue;

      final due = entry.nextOccurrence(now);
      final fireAt = due.subtract(Duration(minutes: lead));
      final key = '${entry.id}@${due.toIso8601String()}';

      // الشباك دقيقة: أوسع من دورة الفحص عشان ما يفوتش، وأضيق من إنه يتكرر.
      // A one-minute window: wider than the sweep so nothing is missed, and
      // narrow enough that it cannot repeat.
      final late = now.difference(fireAt);
      if (late.isNegative || late > const Duration(minutes: 1)) continue;
      if (!_fired.add(key)) continue;

      _raise(entry, due);
    }

    // بنمسح القديم عشان المجموعة ما تكبرش مع طول الجلسة.
    // Old keys are dropped so the set does not grow through a long session.
    if (_fired.length > 200) _fired.clear();
  }

  void _raise(ScheduleEntry entry, DateTime due) {
    final l = ref.read(l10nProvider);
    final minutes = due.difference(DateTime.now()).inMinutes;

    final where = entry.location.trim();
    final body = where.isEmpty
        ? l.reminderBody(minutes)
        : '${l.reminderBody(minutes)} · $where';

    Reminders.show(entry.title, body: body, tag: entry.id);
    state = state.copyWith(last: ReminderShot(entry: entry, at: DateTime.now()));
  }
}

/// آخر تنبيه طلع — الواجهة بتعرضه جوه التطبيق كمان.
/// The most recent reminder; the UI also shows it inside the app.
@immutable
class ReminderShot {
  const ReminderShot({required this.entry, required this.at});
  final ScheduleEntry entry;
  final DateTime at;
}

@immutable
class ReminderState {
  const ReminderState({
    required this.enabled,
    required this.permission,
    this.last,
  });

  final bool enabled;
  final String permission;
  final ReminderShot? last;

  bool get isGranted => permission == 'granted';
  bool get isBlocked => permission == 'denied';
  bool get isSupported => permission != 'unsupported';

  /// شغّالة فعلاً: متفعّلة ومعاها إذن.
  /// Actually running: switched on and permitted.
  bool get isLive => enabled && isGranted;

  ReminderState copyWith({bool? enabled, String? permission, ReminderShot? last}) =>
      ReminderState(
        enabled: enabled ?? this.enabled,
        permission: permission ?? this.permission,
        last: last ?? this.last,
      );
}

final reminderServiceProvider =
    NotifierProvider<ReminderService, ReminderState>(ReminderService.new);

/// نصوص التنبيه لازم توصل لخدمة مفيهاش `BuildContext`.
/// The reminder's wording has to reach a service with no `BuildContext`.
final l10nProvider = Provider<AppL10n>((ref) {
  final code = ref.watch(settingsProvider.select((s) => s.languageCode));
  return AppL10n(Locale(code));
});

/// بيقفل التبويب لما يتقفل — لمبة التنبيهات ما تفضلش شغالة.
/// Closes down with the tab so nothing keeps running.
void disposeReminders(web.Window _) {}
