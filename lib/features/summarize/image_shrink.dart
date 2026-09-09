import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_input.dart';

/// بيصغّر صورة قبل ما تتبعت للموديل.
/// Shrinks an image before it is sent to the model.
///
/// صور الموبايل بتيجي 3-8 ميجا، وترميز base64 بيزودها الثلث، والـ Edge Function
/// بتفك الـ JSON وتعيد بناءه — يعني نسختين تلاتة من نفس البيانات في ذاكرة
/// محدودة. النتيجة كانت WORKER_RESOURCE_LIMIT.
/// Phone photos arrive at 3-8 MB, base64 adds a third, and the Edge Function
/// parses the JSON then rebuilds it — two or three copies of the same bytes in
/// a small memory budget. That produced WORKER_RESOURCE_LIMIT.
///
/// 1600 بكسل على الضلع الأطول أكتر من كفاية عشان الموديل يقرا خط اليد ويشوف
/// الألوان، وبيوصل بالصفحة لأقل من نص ميجا.
/// 1600px on the long edge is more than enough for the model to read
/// handwriting and see the colours, and brings a page under half a megabyte.
Future<PickedFile> shrinkImage(
  PickedFile file, {
  int maxEdge = 1600,
  double quality = 0.82,
}) async {
  // الملفات الصغيرة أصلاً بتعدي زي ما هي — إعادة الترميز بتخسر جودة من غير داعي.
  // Already-small files pass through untouched; re-encoding only loses quality.
  if (file.bytes.length < 400 * 1024) return file;

  final blob = web.Blob(
    [file.bytes.toJS].toJS,
    web.BlobPropertyBag(type: file.mimeType),
  );

  web.ImageBitmap? bitmap;
  try {
    bitmap = await web.window.createImageBitmap(blob).toDart;

    final longest = bitmap.width > bitmap.height ? bitmap.width : bitmap.height;
    final scale = longest > maxEdge ? maxEdge / longest : 1.0;
    final width = (bitmap.width * scale).round();
    final height = (bitmap.height * scale).round();

    final canvas = web.HTMLCanvasElement()
      ..width = width
      ..height = height;
    final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;

    // خلفية بيضا: التحويل لـ JPEG مش بيدعم الشفافية، ومن غيرها بتطلع سودا.
    // White ground: JPEG has no alpha, and without this transparency turns black.
    ctx.fillStyle = '#FFFFFF'.toJS;
    ctx.fillRect(0, 0, width.toDouble(), height.toDouble());
    ctx.drawImage(bitmap, 0, 0, width.toDouble(), height.toDouble());

    final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
    final encoded = dataUrl.split(',').last;
    final shrunk = base64Decode(encoded);

    // لو التصغير ما وفّرش حاجة، بنسيب الأصل.
    // If shrinking saved nothing, keep the original.
    if (shrunk.length >= file.bytes.length) return file;

    return PickedFile(
      name: file.name,
      bytes: Uint8List.fromList(shrunk),
      mimeType: 'image/jpeg',
    );
  } catch (_) {
    // صيغة المتصفح ما قدرش يفكها — بنبعت الأصل ونسيب فحص الحجم يتصرف.
    // A format the browser could not decode: send the original and let the
    // size check deal with it.
    return file;
  } finally {
    bitmap?.close();
  }
}
