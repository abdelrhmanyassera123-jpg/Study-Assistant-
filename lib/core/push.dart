import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// اشتراك Push حقيقي عن طريق service worker — بيوصل حتى لو التطبيق مقفول
/// خالص، عكس [Reminders] المحلي اللي محتاج تاب مفتوح.
/// A real push subscription through the service worker — arrives even with
/// the app fully closed, unlike the local [Reminders] which needs an open
/// tab.
class WebPush {
  const WebPush._();

  /// نفس المفتاح العام المسجّل كسر VAPID_PUBLIC_KEY في فنكشن send-reminders؛
  /// عمومي وآمن إنه يتحط هنا (ده معنى "عام" أصلاً).
  /// The same public key stored as the VAPID_PUBLIC_KEY secret on the
  /// send-reminders function; safe to embed here — that's what "public"
  /// means.
  static const _publicKey =
      'BD_N0RYVA35mh9IjUczu-4ZtgRCrSC5hVv5dVegwbfmgp4_ub7NNBpc3L6pLCejSXtYiyypGbhd6p0qJC0WMpOQ';

  /// بيشترك (أو بيرجّع الاشتراك الموجود لو فيه) بعد التأكد إن service worker
  /// جاهز. لازم يتنادى بعد إذن التنبيهات يتوافق عليه.
  /// Subscribes (or returns the existing subscription) once the service
  /// worker is ready. Must be called after notification permission is
  /// granted.
  static Future<PushSubscriptionKeys?> subscribe() async {
    try {
      final registration = await web.window.navigator.serviceWorker.ready.toDart;
      final manager = registration.pushManager;

      final existing = await manager.getSubscription().toDart;
      final sub = existing ??
          await manager
              .subscribe(
                web.PushSubscriptionOptionsInit(
                  userVisibleOnly: true,
                  applicationServerKey: _urlBase64ToBytes(_publicKey).toJS,
                ),
              )
              .toDart;

      final p256dh = sub.getKey('p256dh');
      final auth = sub.getKey('auth');
      if (p256dh == null || auth == null) return null;

      return PushSubscriptionKeys(
        endpoint: sub.endpoint,
        p256dh: _bufferToUnpaddedBase64Url(p256dh),
        auth: _bufferToUnpaddedBase64Url(auth),
      );
    } catch (_) {
      // المتصفح مش داعم Push، أو الاشتراك اتلغى — مش سبب يكسر الصفحة.
      // The browser lacks push support, or the subscribe was refused — no
      // reason to break the page.
      return null;
    }
  }

  /// بيلغي الاشتراك الحالي (لو فيه) ويرجّع الـ endpoint بتاعه عشان يتشال من
  /// السيرفر، أو null لو مفيش اشتراك أصلاً.
  /// Cancels the current subscription (if any) and returns its endpoint so
  /// it can be removed server-side, or null if there was none.
  static Future<String?> unsubscribe() async {
    try {
      final registration = await web.window.navigator.serviceWorker.ready.toDart;
      final sub = await registration.pushManager.getSubscription().toDart;
      if (sub == null) return null;
      final endpoint = sub.endpoint;
      await sub.unsubscribe().toDart;
      return endpoint;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _urlBase64ToBytes(String value) {
    final padded = value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
    return base64Url.decode(padded.replaceAll('-', '+').replaceAll('_', '/'));
  }

  static String _bufferToUnpaddedBase64Url(JSArrayBuffer buffer) {
    final bytes = buffer.toDart.asUint8List();
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class PushSubscriptionKeys {
  const PushSubscriptionKeys({
    required this.endpoint,
    required this.p256dh,
    required this.auth,
  });

  final String endpoint;
  final String p256dh;
  final String auth;
}
