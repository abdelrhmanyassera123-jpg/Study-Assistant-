// التخزين على الجهاز بيعتمد على Cache Storage في المتصفح؛ الاختبارات بتشتغل
// على الـ VM ومفيهاش متصفح، فبتاخد نسخة فاضية.
// On-device storage relies on the browser's Cache Storage; tests run on the
// VM with no browser, so they get an empty stand-in.
export 'offline_store_stub.dart' if (dart.library.js_interop) 'offline_store_web.dart';
