import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'digest.dart';
import 'table_image.dart';
import 'timetable.dart';

/// الإشعارات كلها متجدولة على الموبايل نفسه، أسبوعيًا: إشعار اليوم بجدوله،
/// وتنبيه قبل كل محاضرة. مش محتاجة نت ولا التطبيق يكون مفتوح.
/// Every notification is scheduled on the phone itself, weekly: the day's
/// notification with its table, and a reminder before each lecture. They
/// need neither a connection nor the app open.
class Notifier {
  Notifier._();

  static final plugin = FlutterLocalNotificationsPlugin();

  /// الضغط على إشعار بيبعت الصفحة دي للشاشة الرئيسية.
  /// Tapping a notification hands this page to the main screen.
  static final ValueNotifier<String?> openPage = ValueNotifier(null);

  /// الجدول متكتب بتوقيت القاهرة — نفس افتراض الموقع والسيرفر.
  /// The timetable is written in Cairo time, as the site and server assume.
  static late tz.Location _cairo;

  static const _today = AndroidNotificationDetails(
    'today',
    'محاضرات النهاردة',
    channelDescription: 'إشعار واحد طول اليوم فيه محاضراتك',
    // من غير صوت ولا ظهور فوق الشاشة: معلومة مش منبّه.
    // No sound and no pop-up: information, not an alarm.
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
    ongoing: true,
    autoCancel: false,
    onlyAlertOnce: true,
    showWhen: false,
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    _cairo = tz.getLocation('Africa/Cairo');
    tz.setLocalLocation(_cairo);

    await plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) => openPage.value = r.payload,
    );
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      openPage.value = launch!.notificationResponse?.payload;
    }
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// إذن الإشعارات (أندرويد 13+) والمواعيد الدقيقة (أندرويد 12+). من غير
  /// الدقيقة التنبيه ممكن يتأخر كام دقيقة، بس بيوصل.
  /// The notification permission (Android 13+) and exact alarms (Android
  /// 12+). Without exact ones a reminder may run a few minutes late, but it
  /// still comes.
  static Future<void> askPermissions() async {
    await _android?.requestNotificationsPermission();
    if (!(await _android?.canScheduleExactNotifications() ?? true)) {
      await _android?.requestExactAlarmsPermission();
    }
  }

  /// بيمسح المتجدول ويجدول من الأول على الجدول ده.
  /// Clears what is scheduled and schedules afresh from this timetable.
  static Future<void> schedule(Timetable table) async {
    await plugin.cancelAllPendingNotifications();
    final exact = await _android?.canScheduleExactNotifications() ?? false;
    final mode = exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle;
    final dir = await getApplicationSupportDirectory();

    for (var weekday = 1; weekday <= 7; weekday++) {
      final day = table.lectures.where((l) => l.weekday == weekday).toList();
      if (day.isEmpty) continue;

      if (table.dailyDigest) {
        final moments = digestMoments(day, morningMinutes: table.digestMinutes);
        for (var i = 0; i < moments.length; i++) {
          final m = moments[i];
          final picture = File('${dir.path}/today_${weekday}_$i.png');
          await picture.writeAsBytes(await drawTable(m.view.rows));
          await plugin.zonedSchedule(
            id: 1000 + weekday * 100 + i,
            scheduledDate: _next(weekday, m.minutes),
            notificationDetails: _todayDetails(m, picture.path),
            androidScheduleMode: mode,
            title: m.view.title,
            body: m.view.body,
            payload: 'schedule',
            matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
          );
        }
      }

      var r = 0;
      for (final l in day) {
        final before = l.remindMinutes;
        if (before == null) continue;
        final at = l.startMinutes - before;
        // تنبيه بيقع اليوم اللي قبله (محاضرة 12:05 بليل وتنبيه قبلها بربع ساعة)
        // بيتساب: نادر، ومش مستاهل يوم مختلف.
        // A reminder falling on the day before (a 12:05 AM lecture with a
        // quarter-hour lead) is skipped: rare, and not worth another day.
        if (at < 0) continue;
        await plugin.zonedSchedule(
          id: 3000 + weekday * 100 + r++,
          scheduledDate: _next(weekday, at),
          notificationDetails: _reminderDetails(table),
          androidScheduleMode: mode,
          title: l.name,
          body: [
            before == 0 ? 'بدأت دلوقتي' : 'بعد $before دقيقة',
            l.location.trim(),
          ].where((s) => s.isNotEmpty).join(' · '),
          payload: 'schedule',
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }

    await _showNow(table, dir);
  }

  /// الإشعار المتجدول بيظهر في ميعاده بس؛ لو التطبيق اتفتح في نص اليوم،
  /// الحالة الحالية بتظهر على طول.
  /// A scheduled one only shows at its time; when the app opens mid-day, the
  /// current state shows straight away.
  static Future<void> _showNow(Timetable table, Directory dir) async {
    await plugin.cancel(id: 999);
    if (!table.dailyDigest) return;
    final now = tz.TZDateTime.now(_cairo);
    final day = table.lectures.where((l) => l.weekday == now.weekday).toList();
    final minutes = now.hour * 60 + now.minute;
    DigestMoment? current;
    for (final m in digestMoments(day, morningMinutes: table.digestMinutes)) {
      if (m.minutes <= minutes) current = m;
    }
    if (current == null || current.until <= minutes) return;

    final picture = File('${dir.path}/today_now.png');
    await picture.writeAsBytes(await drawTable(digestView(day, minutes).rows));
    final view = digestView(day, minutes);
    await plugin.show(
      id: 999,
      title: view.title,
      body: view.body,
      notificationDetails: _todayDetails(DigestMoment(minutes, current.until, view), picture.path),
      payload: 'schedule',
    );
  }

  static NotificationDetails _todayDetails(DigestMoment m, String picture) => NotificationDetails(
        android: AndroidNotificationDetails(
          _today.channelId,
          _today.channelName,
          channelDescription: _today.channelDescription,
          importance: _today.importance,
          priority: _today.priority,
          playSound: false,
          enableVibration: false,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
          // بيختفي لوحده لما اللحظة اللي بعده تيجي (هي اللي بتحل محله)، أو بعد
          // آخر محاضرة.
          // Goes away by itself when the next moment arrives (which takes its
          // place), or after the last lecture.
          timeoutAfter: (m.until - m.minutes) * 60 * 1000,
          styleInformation: BigPictureStyleInformation(
            FilePathAndroidBitmap(picture),
            contentTitle: m.view.title,
            summaryText: m.view.body,
            hideExpandedLargeIcon: true,
          ),
        ),
      );

  static NotificationDetails _reminderDetails(Timetable table) => NotificationDetails(
        android: AndroidNotificationDetails(
          // صوت القناة بيتحدد مرة واحدة لما تتعمل، فالصامت قناة لوحده.
          // A channel's sound is fixed when it is created, so silent is its
          // own channel.
          table.soundOn ? 'reminders' : 'reminders_silent',
          table.soundOn ? 'تنبيه المحاضرة' : 'تنبيه المحاضرة (صامت)',
          channelDescription: 'قبل كل محاضرة',
          importance: Importance.high,
          priority: Priority.high,
          playSound: table.soundOn,
          enableVibration: table.vibrateOn,
        ),
      );

  /// أقرب يوم [weekday] الساعة [minutes] بتوقيت القاهرة، من النهاردة لقدام.
  /// The nearest [weekday] at [minutes], Cairo time, from today onward.
  static tz.TZDateTime _next(int weekday, int minutes) {
    // بالتاريخ مش بإضافة 24 ساعة: مصر فيها توقيت صيفي، والساعة الزيادة كانت
    // هتزحزح المعاد.
    // By the calendar date, not by adding 24 hours: Egypt has summer time, and
    // the extra hour would shift the time.
    final now = tz.TZDateTime.now(_cairo);
    for (var days = 0; days <= 7; days++) {
      final at = tz.TZDateTime(_cairo, now.year, now.month, now.day + days, minutes ~/ 60, minutes % 60);
      if (at.weekday == weekday && at.isAfter(now)) return at;
    }
    return tz.TZDateTime(_cairo, now.year, now.month, now.day + 7, minutes ~/ 60, minutes % 60);
  }
}
