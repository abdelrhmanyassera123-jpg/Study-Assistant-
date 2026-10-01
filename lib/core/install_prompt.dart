import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('canInstallApp')
external JSBoolean? _canInstall();

@JS('installApp')
external JSPromise<JSString> _install();

/// تثبيت التطبيق على الشاشة الرئيسية.
/// Installing the app on the home screen.
///
/// كروم وإيدج بيدّوا إذن تثبيت (بيتمسك في index.html)، فبيبقى فيه زرار.
/// سفاري على الآيفون مالوش إذن ولا زرار — التثبيت من قايمة المشاركة بس،
/// فبيتعرض الطريقة بدل الزرار.
/// Chrome and Edge grant an install permission (caught in index.html), so
/// there is a button. Safari on iPhone has neither — installing is only
/// from its share menu — so the steps are shown instead.
class InstallPrompt {
  const InstallPrompt._();

  /// مفتوح كتطبيق متثبّت بالفعل؟
  /// Already running as an installed app?
  static bool get isInstalled {
    try {
      if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
      // سفاري القديم بيقولها من هنا بس.
      // Older Safari only says so here.
      final standalone = (web.window.navigator as JSObject).getProperty('standalone'.toJS);
      return standalone.isA<JSBoolean>() && (standalone as JSBoolean).toDart;
    } catch (_) {
      return false;
    }
  }

  static bool get canPrompt {
    try {
      return _canInstall()?.toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  static bool get isIos {
    final ua = web.window.navigator.userAgent.toLowerCase();
    return ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod');
  }

  /// بيفتح نافذة التثبيت بتاعة المتصفح. بيرجّع true لو المستخدم وافق.
  /// Opens the browser's install dialog; true if the user accepted.
  static Future<bool> prompt() async {
    try {
      return (await _install().toDart).toDart == 'accepted';
    } catch (_) {
      return false;
    }
  }

  /// بيتنادى كل ما الإذن يوصل أو يروح، عشان الزرار يظهر أول ما ينفع.
  /// Called whenever the permission arrives or goes, so the button appears
  /// the moment it can.
  static StreamSubscription<web.Event> onChange(void Function() callback) =>
      web.EventStreamProvider<web.Event>('install-available')
          .forTarget(web.window)
          .listen((_) => callback());
}
