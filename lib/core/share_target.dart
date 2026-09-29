import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../features/summarize/file_input.dart';

/// بيمسك ملف وصل من تطبيق تاني عن طريق مشاركة النظام (Android share sheet).
/// Holds a file that arrived from another app via the OS share sheet.
///
/// pwa-sw.js بيلقط طلب المشاركة، بيخزّن الملف مؤقتًا في Cache Storage،
/// وبيحوّل لصفحة التطبيق بـ ?shared=1. [init] بيتنادى مرة واحدة بدري في
/// main() عشان يقرا أي ملف موجود ويمسحه من الكاش، و[take] بيدّيه لأي حد
/// طالبه — مرة واحدة بس، عشان ما يتضافش مرتين لو الصفحة اتعاد بناؤها.
/// pwa-sw.js catches the share request, stashes the file briefly in Cache
/// Storage, and redirects to the app's page with ?shared=1. [init] is
/// called once early in main() to read any waiting file and clear it from
/// the cache, and [take] hands it to whoever asks — only once, so it is not
/// added twice if the page rebuilds.
class SharedFile {
  const SharedFile._();

  static PickedFile? _pending;
  static bool _checked = false;

  static Future<void> init() async {
    if (_checked) return;
    _checked = true;
    _pending = await _consume();
  }

  /// بيرجّع الملف المعلّق ويمسحه فورًا.
  /// Returns the pending file and clears it immediately.
  static PickedFile? take() {
    final file = _pending;
    _pending = null;
    return file;
  }

  static bool get hasPending => _pending != null;

  static Future<PickedFile?> _consume() async {
    if (Uri.base.queryParameters['shared'] != '1') return null;
    try {
      final cache = await web.window.caches.open('share-target-cache').toDart;
      final response = await cache.match('/shared-file'.toJS).toDart;
      if (response == null) return null;

      final buffer = await response.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      final mimeType = response.headers.get('content-type') ?? 'application/octet-stream';
      final rawName = response.headers.get('x-file-name');
      final name = rawName == null ? 'shared-file' : Uri.decodeComponent(rawName);

      await cache.delete('/shared-file'.toJS).toDart;

      return PickedFile(name: name, bytes: bytes, mimeType: mimeType);
    } catch (_) {
      // مفيش ملف، أو المتصفح مش داعم Cache Storage — مش سبب يوقّف التطبيق.
      // No file, or the browser lacks Cache Storage support — no reason to
      // hold up the app.
      return null;
    }
  }
}
