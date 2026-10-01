/// اللي التطبيق اتفتح عشانه من تنبيه: تسجيل محاضرة، أو نتيجة تلخيص.
/// What a notification opened the app for: recording a lecture, or a
/// summary's result.
///
/// بيتقري من الرابط مرة واحدة، و[takeRecord]/[takeJob] بيدّوه لأول حد يطلبه
/// بس، عشان ما يتنفذش تاني لو الشاشة اتعاد بناؤها.
/// Read from the URL once; [takeRecord]/[takeJob] hand it to the first asker
/// only, so it does not run again when the screen rebuilds.
class LaunchIntent {
  const LaunchIntent._();

  static String? _record = _param('record');
  static String? _job = _param('job');

  static String? _param(String name) {
    final value = Uri.base.queryParameters[name]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  static bool get hasPending => _record != null || _job != null;

  /// من جوه التطبيق: زرار "سجّلها" في شاشة النهاردة.
  /// From inside the app: the "record it" button on the Today card.
  static void armRecord(String entryId) => _record = entryId;

  static String? takeRecord() {
    final id = _record;
    _record = null;
    return id;
  }

  static String? takeJob() {
    final id = _job;
    _job = null;
    return id;
  }
}
