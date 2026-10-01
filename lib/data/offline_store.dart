import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// آخر نسخة من بيانات المستخدم على الجهاز، عشان التطبيق يفتح من غير نت.
/// The latest copy of the user's data on the device, so the app opens with
/// no connection.
///
/// في Cache Storage مش localStorage: الأخير سقفه حوالي 5 ميجا، وتلخيصات ترم
/// كامل بتعدّيه.
/// In Cache Storage rather than localStorage: the latter caps at about 5 MB,
/// and a whole term's summaries goes past that.
class OfflineStore {
  const OfflineStore._();

  static const _cacheName = 'offline-data-v1';

  static String _url(String key) => '/__offline__/${Uri.encodeComponent(key)}';

  static Future<void> put(String key, Object? value) async {
    try {
      final cache = await web.window.caches.open(_cacheName).toDart;
      await cache
          .put(
            _url(key).toJS,
            web.Response(
              jsonEncode(value).toJS,
              web.ResponseInit(headers: {'Content-Type': 'application/json'}.jsify()! as web.HeadersInit),
            ),
          )
          .toDart;
    } catch (_) {}
  }

  static Future<Object?> get(String key) async {
    try {
      final cache = await web.window.caches.open(_cacheName).toDart;
      final response = await cache.match(_url(key).toJS).toDart;
      if (response == null) return null;
      final text = (await response.text().toDart).toDart;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}
