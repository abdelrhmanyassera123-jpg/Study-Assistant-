// المحمّل من غير service worker بتاع فلاتر: بيتاعه كان بيتسجّل على نفس
// النطاق في كل فتحة ويشيل pwa-sw.js، فالتطبيق ما كانش بيتحفظ للاستخدام من
// غير نت. التخزين كله في pwa-sw.js.
// The loader without Flutter's service worker: Flutter's registered on the
// same scope on every load and displaced pwa-sw.js, so the app was never
// kept for offline use. All caching lives in pwa-sw.js.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
