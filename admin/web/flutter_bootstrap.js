// المحمّل من غير service worker بتاع فلاتر: اللوحة لازم تجيب آخر نسخة دايمًا،
// ومش محتاجة تشتغل من غير نت.
// The loader without Flutter's service worker: the dashboard must always load
// its latest version, and has no need to work offline.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load();
