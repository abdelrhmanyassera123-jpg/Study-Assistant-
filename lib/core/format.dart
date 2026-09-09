import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'l10n.dart';

/// تنسيق الوقت والتواريخ بالعربي والإنجليزي.
/// Time and date formatting for both languages.
class Fmt {
  const Fmt._();

  /// 95 دقيقة -> "1س 35د" / "1h 35m". أقل من ساعة -> "35د" / "35m".
  static String minutes(BuildContext context, int totalMinutes) {
    final l = context.l;
    if (totalMinutes < 60) return '$totalMinutes${l.minShort}';
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? '$h${l.hourShort}' : '$h${l.hourShort} $m${l.minShort}';
  }

  /// عداد المؤقت: 25:00
  static String clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// "النهاردة" / "بكرة" / "إمبارح" وإلا التاريخ.
  /// Relative day name where it helps, otherwise a short date.
  static String date(BuildContext context, DateTime d) {
    final l = context.l;
    final diff = _day(d).difference(_day(DateTime.now())).inDays;
    if (diff == 0) return l.today;
    if (diff == 1) return l.tomorrow;
    if (diff == -1) return l.yesterday;
    return DateFormat.MMMd(l.locale.languageCode).format(d);
  }

  /// اسم اليوم المختصر — للرسم البياني.
  /// Short weekday name for the chart axis.
  static String weekday(BuildContext context, DateTime d) =>
      DateFormat.E(context.l.locale.languageCode).format(d);

  /// "بعد 3 أيام" / "in 3 days" لجدولة الكروت.
  static String inDays(BuildContext context, DateTime d) {
    final l = context.l;
    final diff = _day(d).difference(_day(DateTime.now())).inDays;
    if (diff <= 0) return l.dueNow;
    if (diff == 1) return l.tomorrow;
    return l.isAr ? 'بعد $diff يوم' : 'in $diff days';
  }
}
