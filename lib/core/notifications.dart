import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// تنبيهات المحاضرات في المتصفح.
/// Lecture reminders, through the browser.
///
/// التنبيه بيطلع من المتصفح نفسه، فبيبان حتى لو التبويب في الخلفية. بس لو
/// الصفحة اتقفلت خالص مفيش حاجة شغالة تطلّعه — ده محتاج Service Worker و
/// Push من سيرفر، وده مش موجود هنا.
/// The notification comes from the browser itself, so it shows even when the
/// tab is in the background. But with the page fully closed nothing is running
/// to raise it — that needs a service worker and a push server, which this app
/// does not have.
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
  /// Raises a notification. The [tag] stops the same one appearing twice if it
  /// is raised again.
  static void show(String title, {required String body, String? tag}) {
    if (!isGranted) return;
    try {
      web.Notification(
        title,
        web.NotificationOptions(
          body: body,
          tag: tag ?? '',
          // مش بيصدر صوت من نفسه: التنبيه وسط محاضرة تانية أسوأ من إنه يفوت.
          // No sound of its own: a chime in the middle of another lecture is
          // worse than a reminder that goes unheard.
          silent: false,
          requireInteraction: false,
        ),
      );
    } catch (_) {
      // متصفح رافض التنبيهات مش سبب لكسر الصفحة.
      // A browser refusing notifications is no reason to break the page.
    }
  }
}
