import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'digest.dart';

/// جدول المستخدم وإعدادات تنبيهه، محفوظين على الموبايل.
/// The user's timetable and reminder settings, kept on the phone.
class Timetable {
  const Timetable({
    required this.lectures,
    this.dailyDigest = true,
    this.digestMinutes = 420,
    this.soundOn = true,
    this.vibrateOn = true,
  });

  final List<Lecture> lectures;
  final bool dailyDigest;
  final int digestMinutes;
  final bool soundOn;
  final bool vibrateOn;

  static const _key = 'timetable_v1';

  Map<String, dynamic> toJson() => {
        'lectures': [for (final l in lectures) l.toJson()],
        'daily_digest': dailyDigest,
        'digest_minutes': digestMinutes,
        'sound_on': soundOn,
        'vibrate_on': vibrateOn,
      };

  factory Timetable.fromJson(Map<String, dynamic> m) => Timetable(
        lectures: [
          for (final r in (m['lectures'] as List? ?? const []))
            if (r is Map) Lecture.fromJson(r.cast<String, dynamic>()),
        ],
        dailyDigest: (m['daily_digest'] as bool?) ?? true,
        digestMinutes: (m['digest_minutes'] as num?)?.toInt() ?? 420,
        soundOn: (m['sound_on'] as bool?) ?? true,
        vibrateOn: (m['vibrate_on'] as bool?) ?? true,
      );

  /// آخر نسخة محفوظة، أو null لو لسه ما اتجابش.
  /// The last saved copy, or null if none was fetched yet.
  static Future<Timetable?> saved() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    try {
      return Timetable.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(toJson()));

  /// بيجيب الجدول من Supabase بتوكن الموقع اللي جوه التطبيق — نفس صلاحيات
  /// المستخدم (RLS)، فمفيش داتا حد تاني.
  /// Fetches the timetable from Supabase with the site's token from inside the
  /// app: the user's own rights (RLS), so no one else's data.
  ///
  /// مش بنجدد التوكن من هنا: التجديد بيلغي التوكن القديم، والموقع اللي جوه
  /// التطبيق هيتطرد. الموقع نفسه بيجدده، وإحنا بنقرا الجديد.
  /// The token is never refreshed from here: refreshing revokes the old one
  /// and would sign the site inside the app out. The site renews it itself,
  /// and we read the new one.
  static Future<Timetable> fetch(String accessToken) async {
    final headers = {'apikey': supabaseAnonKey, 'Authorization': 'Bearer $accessToken'};
    final responses = await Future.wait([
      http.get(
        Uri.parse(
          '$supabaseUrl/rest/v1/schedule_entries'
          '?select=id,title,location,session_type,weekday,start_minutes,end_minutes,remind_minutes',
        ),
        headers: headers,
      ),
      http.get(Uri.parse('$supabaseUrl/rest/v1/notification_prefs?select=*'), headers: headers),
    ]).timeout(const Duration(seconds: 20));

    final entries = responses[0];
    if (entries.statusCode != 200) {
      throw http.ClientException('schedule ${entries.statusCode}');
    }
    final prefsRows = responses[1].statusCode == 200 ? jsonDecode(responses[1].body) as List : const [];
    final prefs = prefsRows.isEmpty ? const <String, dynamic>{} : (prefsRows.first as Map).cast<String, dynamic>();

    return Timetable(
      lectures: [
        for (final r in jsonDecode(entries.body) as List) Lecture.fromJson((r as Map).cast<String, dynamic>()),
      ],
      dailyDigest: (prefs['daily_digest'] as bool?) ?? true,
      digestMinutes: (prefs['digest_minutes'] as num?)?.toInt() ?? 420,
      soundOn: (prefs['sound_on'] as bool?) ?? true,
      vibrateOn: (prefs['vibrate_on'] as bool?) ?? true,
    );
  }
}
