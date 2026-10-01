import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../features/summarize/file_input.dart';
import 'file_names.dart';

/// بيمسك الملفات والنص اللي وصلوا من تطبيق تاني عن طريق مشاركة النظام.
/// Holds the files and text that arrived from another app via the OS share
/// sheet.
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

  static List<PickedFile> _files = const [];
  static String _text = '';
  static bool _checked = false;

  static Future<void> init() async {
    if (_checked) return;
    _checked = true;
    await _consume();
  }

  static bool get hasPending => _files.isNotEmpty || _text.isNotEmpty;

  /// بيرجّع اللي اتشارك ويمسحه فورًا — مرة واحدة بس.
  /// Returns what was shared and clears it immediately — once only.
  static ({List<PickedFile> files, String text})? take() {
    if (!hasPending) return null;
    final shared = (files: _files, text: _text);
    _files = const [];
    _text = '';
    return shared;
  }

  static Future<void> _consume() async {
    if (Uri.base.queryParameters['shared'] != '1') return;
    try {
      final cache = await web.window.caches.open('share-target-cache').toDart;
      final meta = await cache.match('/shared-meta'.toJS).toDart;
      if (meta == null) return;
      final info = jsonDecode((await meta.text().toDart).toDart) as Map<String, dynamic>;
      final count = (info['count'] as num?)?.toInt() ?? 0;

      final files = <PickedFile>[];
      for (var i = 0; i < count; i++) {
        final response = await cache.match('/shared-file/$i'.toJS).toDart;
        if (response == null) continue;
        final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
        final mimeType = response.headers.get('content-type') ?? 'application/octet-stream';
        final rawName = response.headers.get('x-file-name');
        files.add(PickedFile(
          name: withExtension(
            rawName == null ? 'shared-file' : Uri.decodeComponent(rawName),
            mimeType,
          ),
          bytes: bytes,
          mimeType: mimeType,
          modified: DateTime.now(),
        ));
      }

      for (final key in (await cache.keys().toDart).toDart) {
        await cache.delete(key).toDart;
      }
      _files = files;
      _text = '${info['text'] ?? ''}'.trim();
    } catch (_) {
      // مفيش حاجة، أو المتصفح مش داعم Cache Storage — مش سبب يوقّف التطبيق.
      // Nothing there, or no Cache Storage support — no reason to hold up the
      // app.
    }
  }
}
