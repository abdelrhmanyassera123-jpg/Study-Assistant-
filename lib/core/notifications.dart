import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// تنبيهات المحاضرات المحلية — بتطلّع من الصفحة نفسها وهي مفتوحة.
/// Local lecture reminders — raised from the page itself while it is open.
///
/// ده مسار واحد بس. التنبيه اللي بيوصل حتى لو التطبيق مقفول خالص جاي من
/// [WebPush] بدالها (core/push.dart) عن طريق فنكشن send-reminders.
/// This is only one path. The reminder that arrives even with the app fully
/// closed comes from [WebPush] instead (core/push.dart) via the
/// send-reminders function.
class Reminders {
  const Reminders._();

  /// المتصفحات القديمة مفيهاش الـ API أصلاً، والمحاولة بترمي.
  /// Older browsers lack the API entirely and reading it throws.
  static bool get isSupported => permission != 'unsupported';

  /// 'granted' أو 'denied' أو 'default' (لسه ما اتسألش).
  /// 'granted', 'denied', or 'default' (not asked yet).
  static String get permission {
    // القراءة المباشرة في try هي الفحص نفسه: المتصفح اللي مفهوش الـ API بيرمي
    // هنا، فمفيش داعي لفحص تاني يسأل عن الدعم (وده كان بينده نفسه).
    // Reading it inside a try *is* the check: a browser without the API throws
    // right here, so no separate support test is needed (and one would call
    // back into this getter).
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'unsupported';
    }
  }

  static bool get isGranted => permission == 'granted';

  /// بيطلب الإذن. لازم يتنادى من ضغطة المستخدم — المتصفح بيرفض غير كده.
  /// Asks for permission. Must be called from a user gesture; browsers refuse
  /// otherwise.
  static Future<bool> request() async {
    if (!isSupported) return false;
    try {
      final result = await web.Notification.requestPermission().toDart;
      return result.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  /// بيطلّع تنبيه. الـ [tag] بيمنع تكرار نفس التنبيه لو اتنادى مرتين.
  /// [silent] و[vibrate] بيتحكموا في الصوت والاهتزاز — من تخصيص المستخدم.
  /// Raises a notification. The [tag] stops the same one appearing twice if it
  /// is raised again. [silent] and [vibrate] come from the user's own
  /// customization.
  static void show(
    String title, {
    required String body,
    String? tag,
    bool silent = false,
    List<int> vibrate = const [200, 100, 200],
  }) {
    if (!isGranted) return;
    try {
      web.Notification(
        title,
        web.NotificationOptions(
          body: body,
          tag: tag ?? '',
          vibrate: Int32List.fromList(vibrate).toJS,
          silent: silent,
          requireInteraction: false,
        ),
      );
    } catch (_) {
      // متصفح رافض التنبيهات مش سبب لكسر الصفحة.
      // A browser refusing notifications is no reason to break the page.
    }
  }
}
