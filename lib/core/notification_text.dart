import 'l10n.dart';
import '../models/models.dart';

/// نص التنبيه — الصيغة الافتراضية، أو قالب المستخدم المخصص لو حطّه.
/// The reminder's wording — the default phrasing, or the user's own
/// template when they have set one.
///
/// نفس المنطق ده متكرر في فنكشن send-reminders (Deno)، عشان التنبيه المحلي
/// والتنبيه اللي جاي من السيرفر يطلعوا بنفس الشكل بالظبط.
/// This same logic is duplicated in the send-reminders function (Deno), so
/// the local reminder and the one arriving from the server read identically.
String buildReminderBody(
  AppL10n l,
  NotificationPrefs prefs, {
  required int minutes,
  required String location,
  required String lecture,
  required String lecturer,
}) {
  final custom = prefs.customBody?.trim();
  if (custom == null || custom.isEmpty) {
    return location.isEmpty
        ? l.reminderBody(minutes)
        : '${l.reminderBody(minutes)} · $location';
  }
  return custom
      .replaceAll('{minutes}', '$minutes')
      .replaceAll('{location}', location)
      .replaceAll('{lecture}', lecture)
      .replaceAll('{lecturer}', lecturer);
}
