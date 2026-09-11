import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// بيرفع بايتات ويقول وصل فين وهو ماشي.
/// Uploads bytes and reports how far it has got while it goes.
///
/// مكتوب على XMLHttpRequest مش على حزمة http: نسخة الويب من الحزمة مش بتعرض
/// تقدّم الرفع أصلاً. وعلى نت بطيء الرفع هو أطول انتظار في التطبيق كله —
/// شريط ساكت هناك بيبان كأن الحاجة علّقت.
/// Built on XMLHttpRequest rather than the http package: its web implementation
/// exposes no upload progress at all. On a slow line the upload is the longest
/// wait in the whole app — a silent bar there looks like something has hung.
Future<({int status, String body})> uploadBytes({
  required Uri url,
  required Map<String, String> headers,
  required Uint8List bytes,
  void Function(int sent, int total)? onProgress,
}) {
  final done = Completer<({int status, String body})>();
  final request = web.XMLHttpRequest();

  request.open('POST', url.toString());
  for (final entry in headers.entries) {
    request.setRequestHeader(entry.key, entry.value);
  }

  request.upload.addEventListener(
    'progress',
    ((web.Event event) {
      final e = event as web.ProgressEvent;
      // الطول مش دايمًا معروف — ساعتها بنسيب الشريط بلا نسبة بدل ما نخترع رقم.
      // The length is not always known; then the bar goes without a figure
      // rather than inventing one.
      if (!e.lengthComputable) return;
      onProgress?.call(e.loaded.toInt(), e.total.toInt());
    }).toJS,
  );

  void finish(int status, String body) {
    if (!done.isCompleted) done.complete((status: status, body: body));
  }

  request.addEventListener(
    'load',
    ((web.Event _) => finish(request.status, request.responseText)).toJS,
  );
  request.addEventListener(
    'error',
    ((web.Event _) => finish(0, 'network error')).toJS,
  );
  request.addEventListener(
    'abort',
    ((web.Event _) => finish(0, 'aborted')).toJS,
  );

  request.send(bytes.toJS);
  return done.future;
}
