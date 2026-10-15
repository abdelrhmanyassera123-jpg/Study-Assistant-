/// محاضرات اليوم وإشعارها — نفس قواعد السيرفر
/// (supabase/functions/_shared/today_digest.ts)، بس محسوبة على الموبايل
/// ومتجدولة مقدمًا، فبتشتغل حتى من غير نت.
/// The day's lectures and their notification: the same rules as the server
/// (supabase/functions/_shared/today_digest.ts), worked out on the phone and
/// scheduled ahead, so they work with no connection too.
library;

/// المحاضرة اللي مالهاش ميعاد نهاية بتتحسب ساعة ونص.
/// A lecture with no end time counts as an hour and a half.
const defaultLengthMinutes = 90;

class Lecture {
  const Lecture({
    required this.id,
    required this.title,
    required this.location,
    required this.weekday,
    required this.startMinutes,
    this.endMinutes,
    this.sessionType = '',
    this.remindMinutes,
  });

  final String id;
  final String title;
  final String location;

  /// 1 = الاتنين ... 7 = الحد — نفس DateTime.weekday ونفس الجدول.
  /// 1 = Monday ... 7 = Sunday, as DateTime.weekday and the table.
  final int weekday;
  final int startMinutes;
  final int? endMinutes;
  final String sessionType;

  /// قبل المحاضرة بكام دقيقة ييجي التنبيه — null يعني من غير تنبيه.
  /// How many minutes before the lecture its reminder comes; null for none.
  final int? remindMinutes;

  int get end => endMinutes ?? startMinutes + defaultLengthMinutes;

  String get name => [title.trim(), sessionType.trim()].where((s) => s.isNotEmpty).join(' — ');

  factory Lecture.fromJson(Map<String, dynamic> m) => Lecture(
        id: '${m['id']}',
        title: '${m['title'] ?? ''}',
        location: '${m['location'] ?? ''}',
        weekday: (m['weekday'] as num).toInt(),
        startMinutes: (m['start_minutes'] as num).toInt(),
        endMinutes: (m['end_minutes'] as num?)?.toInt(),
        sessionType: '${m['session_type'] ?? ''}',
        remindMinutes: (m['remind_minutes'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'location': location,
        'weekday': weekday,
        'start_minutes': startMinutes,
        'end_minutes': endMinutes,
        'session_type': sessionType,
        'remind_minutes': remindMinutes,
      };
}

enum RowState { done, now, next, later }

class DigestRow {
  const DigestRow(this.start, this.end, this.title, this.room, this.state);
  final String start;
  final String end;
  final String title;
  final String room;
  final RowState state;
}

/// شكل الإشعار في لحظة معيّنة.
/// The notification as it stands at one moment.
class DigestView {
  const DigestView(this.title, this.body, this.rows);
  final String title;
  final String body;
  final List<DigestRow> rows;
}

/// لحظة الإشعار بيتغيّر فيها، ولحد إمتى يفضل ظاهر.
/// A moment the notification changes, and how long it stays up.
class DigestMoment {
  const DigestMoment(this.minutes, this.until, this.view);

  /// الدقيقة من نص الليل.
  /// The minute after midnight.
  final int minutes;

  /// لحد الدقيقة دي يفضل ظاهر — اللحظة اللي بعده بتحل محله، وبعد آخر محاضرة
  /// بيختفي.
  /// Stays up until this minute: the next moment takes over, and after the
  /// last lecture it goes away.
  final int until;
  final DigestView view;
}

/// كل اللحظات اللي إشعار اليوم بيتغيّر فيها: أول اليوم، وبداية ونهاية كل
/// محاضرة.
/// Every moment the day's notification changes: the start of the day, and
/// each lecture's start and end.
List<DigestMoment> digestMoments(List<Lecture> day, {required int morningMinutes}) {
  if (day.isEmpty) return const [];
  final list = [...day]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  final lastEnd = list.map((l) => l.end).reduce((a, b) => a > b ? a : b);
  final morning = morningMinutes < list.first.startMinutes ? morningMinutes : list.first.startMinutes;

  final points = <int>{morning};
  for (final l in list) {
    if (l.startMinutes >= morning) points.add(l.startMinutes);
    if (l.end < lastEnd && l.end >= morning) points.add(l.end);
  }
  final sorted = points.where((p) => p < lastEnd).toList()..sort();
  return [
    for (var i = 0; i < sorted.length; i++)
      DigestMoment(
        sorted[i],
        i + 1 < sorted.length ? sorted[i + 1] : lastEnd,
        digestView(list, sorted[i]),
      ),
  ];
}

/// وهو مقفول بيبان سطرين: اللي شغالة أو الجاية، لحد إمتى، وفين. لما يتفتح،
/// اليوم كله جدول (rows).
/// Collapsed it shows two lines: what is under way or next, until when, and
/// where. Expanded, the whole day as a table (rows).
DigestView digestView(List<Lecture> day, int now) {
  final list = [...day]..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  Lecture? current;
  for (final l in list) {
    if (l.startMinutes <= now && l.end > now) current = l;
  }
  final upcoming = list.where((l) => l.startMinutes > now).toList();
  final next = upcoming.isEmpty ? null : upcoming.first;
  final left = list.where((l) => l.end > now).length;
  String parts(List<String> p) => p.where((s) => s.isNotEmpty).join(' · ');

  String title;
  String body;
  if (current != null) {
    title = '▶ ${current.name}';
    body = parts([
      'دلوقتي لحد ${clock(current.end)}',
      current.location.trim(),
      next != null ? 'بعدها ${clock(next.startMinutes)}' : 'آخر محاضرة',
    ]);
  } else if (next != null) {
    final morning = upcoming.length == list.length;
    title = morning ? 'محاضرات النهاردة: ${list.length}' : 'الجاية: ${next.name}';
    body = morning
        ? parts(['أولها ${clock(next.startMinutes)}', next.name, next.location.trim()])
        : parts(['الساعة ${clock(next.startMinutes)}', next.location.trim(), 'فاضل $left']);
  } else {
    title = 'خلصت محاضرات النهاردة';
    body = '';
  }

  final highlight = current ?? next;
  final rows = [
    for (final l in list)
      DigestRow(
        clock(l.startMinutes),
        clock(l.end),
        l.name,
        l.location.trim(),
        l.end <= now
            ? RowState.done
            : identical(l, current)
                ? RowState.now
                : identical(l, highlight)
                    ? RowState.next
                    : RowState.later,
      ),
  ];
  return DigestView(title, body, rows);
}

/// ساعة بنظام 12 بالعربي: 9:30 ص، 1:05 م.
/// A 12-hour Arabic clock: 9:30 ص, 1:05 م.
String clock(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'ص' : 'م'}';
}
