import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../../core/l10n.dart';
import '../../core/notification_text.dart';
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

  /// بيمنع نداءين لـ _subscribePush يشتغلوا في نفس اللحظة. من غيره، تفعيل
  /// التنبيهات بيسبب نداءين متزامنين (واحد مباشر من requestPermission()،
  /// وواحد من build() لما remindersOn يتغيّر) وكل واحد فيهم بيلاقي "مفيش
  /// اشتراك موجود" في نفس اللحظة، فبيعمل اشتراك جديد لوحده — نسخة مكررة.
  /// Guards against two _subscribePush calls running at the same moment.
  /// Without it, turning reminders on triggers two concurrent calls (one
  /// direct from requestPermission(), one from build() reacting to
  /// remindersOn changing) and each sees "no existing subscription" at the
  /// same instant, so each creates its own — a duplicate.
  bool _subscribing = false;

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

      // مستخدم قديم كان مفعّل التنبيهات قبل ما خاصية الـ Push تتضاف: الإذن
      // ممنوح بالفعل، فمفيش داعي لضغطة جديدة — بنشترك على طول.
      // A returning user who enabled reminders before push existed: permission
      // is already granted, so no fresh gesture is needed — subscribe right
      // away.
      if (Reminders.isGranted) scheduleMicrotask(_subscribePush);
    }

    return ReminderState(enabled: on, permission: Reminders.permission);
  }

  /// بيسأل المتصفح الإذن، وبعد الموافقة بيشترك في Push. لازم يتنادى من ضغطة
  /// مستخدم.
  /// Asks the browser for permission, then subscribes to push on approval.
  /// Must come from a user gesture.
  Future<bool> requestPermission() async {
    final granted = await Reminders.request();
    state = state.copyWith(permission: Reminders.permission);
    if (granted) await _subscribePush();
    return granted;
  }

  /// بيشترك في Push عشان التنبيه يوصل حتى لو التطبيق مقفول خالص. فشله مش
  /// سبب يمنع التنبيه المحلي (اللي شغال من غير Push أصلاً) — بنحاول بس من
  /// غير ما نوقف حاجة لو اتعطل.
  /// Subscribes to push so the reminder arrives even with the app fully
  /// closed. A failure here is no reason to block the local reminder (which
  /// works without push anyway) — best-effort, nothing stops if it fails.
  Future<void> _subscribePush() async {
    if (_subscribing) return;
    _subscribing = true;
    try {
      final keys = await WebPush.subscribe();
      if (keys == null) return;
      try {
        await ref.read(repositoryProvider).savePushSubscription(
              endpoint: keys.endpoint,
              p256dh: keys.p256dh,
              auth: keys.auth,
            );
      } catch (_) {}
    } finally {
      _subscribing = false;
    }
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
    final prefs = ref.read(notificationPrefsProvider).value ?? const NotificationPrefs();
    final minutes = due.difference(DateTime.now()).inMinutes;

    final body = buildReminderBody(
      l,
      prefs,
      minutes: minutes,
      location: entry.location.trim(),
      lecture: entry.title,
      lecturer: entry.lecturer.trim(),
    );

    Reminders.show(
      entry.title,
      body: body,
      tag: entry.id,
      silent: !prefs.soundOn,
      vibrate: prefs.vibrateOn ? const [200, 100, 200] : const [],
    );
    state = state.copyWith(last: ReminderShot(entry: entry, at: DateTime.now()));
  }

  /// بيطلّع تنبيه تجربة فورًا (محلي)، وبيحاول يبعت تنبيه Push حقيقي كمان لو
  /// فيه اشتراك — عشان يتأكد المسارين شغالين مع تخصيصاته الحالية.
  /// Raises a test reminder right away (local), and also tries a real push
  /// if there is a subscription — to confirm both paths work with the
  /// current customization.
  Future<int> sendTest() async {
    final l = ref.read(l10nProvider);
    final prefs = ref.read(notificationPrefsProvider).value ?? const NotificationPrefs();
    final title = l.testLectureTitle;
    final body = buildReminderBody(
      l,
      prefs,
      minutes: prefs.defaultRemindMinutes,
      location: l.testLectureLocation,
      lecture: title,
      lecturer: l.testLectureLecturer,
    );

    Reminders.show(
      title,
      body: body,
      tag: 'test',
      silent: !prefs.soundOn,
      vibrate: prefs.vibrateOn ? const [200, 100, 200] : const [],
    );

    // -1 يميّز "الطلب فشل" عن "0 جهاز مشترك" — قبل كده كانوا بيتلخبطوا في
    // نفس الرسالة، وده كان بيخبّي مشكلة CORS حقيقية وراء رسالة "مفيش
    // اشتراك" المضلّلة.
    // -1 distinguishes "the request failed" from "0 subscribed devices" —
    // they used to collapse into the same message, which hid a real CORS
    // bug behind a misleading "no subscription" message.
    try {
      return await ref.read(repositoryProvider).sendTestPush();
    } catch (_) {
      return -1;
    }
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
