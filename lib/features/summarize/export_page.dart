import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// بيصوّر ويدجت مرسومة كـ PNG.
/// Captures a rendered widget as PNG.
///
/// [pixelRatio] فوق 1 عشان الصورة تطلع حادة للطباعة.
/// [pixelRatio] above 1 keeps the capture sharp enough to print.
Future<Uint8List> capturePng(GlobalKey boundaryKey, {double pixelRatio = 2.5}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('الصفحة لسه مش مرسومة');
  }

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('فشل تحويل الصفحة لصورة');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// بيصوّر كل صفحة ويبني منها PDF واحد، صفحة لكل حدود.
/// Captures each boundary and builds one PDF with a page per boundary.
Future<Uint8List> capturePdf(List<GlobalKey> boundaryKeys, {double pixelRatio = 2.5}) async {
  final pages = <_RgbPage>[];
  for (final key in boundaryKeys) {
    final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('الصفحة لسه مش مرسومة');
    }
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    try {
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rgba == null) throw StateError('فشل قراءة بكسلات الصفحة');
      pages.add(_RgbPage.fromRgba(rgba.buffer.asUint8List(), image.width, image.height));
    } finally {
      image.dispose();
    }
  }
  return _pdfFromPages(pages);
}

class _RgbPage {
  _RgbPage(this.compressed, this.width, this.height);

  /// PDF مش بيفهم قناة الشفافية، فبنشيلها ونسيب RGB.
  /// PDF has no alpha channel here, so drop it and keep RGB.
  factory _RgbPage.fromRgba(Uint8List rgba, int width, int height) {
    final rgb = Uint8List(width * height * 3);
    for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
      rgb[j] = rgba[i];
      rgb[j + 1] = rgba[i + 1];
      rgb[j + 2] = rgba[i + 2];
    }
    return _RgbPage(
      Uint8List.fromList(const ZLibEncoder().encode(rgb)),
      width,
      height,
    );
  }

  final Uint8List compressed;
  final int width;
  final int height;
}

/// بيبني PDF فيه صورة لكل صفحة.
/// Builds a PDF holding one image per page.
///
/// مكتوب بالإيد بدل حزمة PDF جاهزة لسببين: الحزم المتاحة بتتعارض مع نسخة
/// archive المستخدمة، والأهم إن النص هنا **صورة** مش حروف — فمفيش مشكلة تشكيل
/// عربي في الـ PDF من أصلها.
/// Hand-written instead of pulling a PDF package: the available ones clash with
/// the archive version in use, and more importantly the text here is an *image*
/// rather than glyphs, so Arabic shaping in PDF never becomes a problem.
Uint8List _pdfFromPages(List<_RgbPage> pages) {
  final bytes = BytesBuilder();
  final offsets = <int, int>{};
  void write(String s) => bytes.add(latin1.encode(s));

  // 1 الكتالوج، 2 شجرة الصفحات، وبعدين لكل صفحة 3 كائنات: الصفحة، الصورة، المحتوى.
  // 1 catalog, 2 page tree, then three objects per page: page, image, content.
  final count = 2 + pages.length * 3;
  int pageObj(int i) => 3 + i * 3;

  write('%PDF-1.4\n');

  offsets[1] = bytes.length;
  write('1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

  offsets[2] = bytes.length;
  final kids = [for (var i = 0; i < pages.length; i++) '${pageObj(i)} 0 R'].join(' ');
  write('2 0 obj\n<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>\nendobj\n');

  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    // A4 بالعرض لو الصورة عريضة، وبالطول لو لأ؛ والبُعد التاني بنفس نسبة الصورة.
    // Landscape A4 for a wide image, portrait otherwise; the other side keeps
    // the image's aspect ratio.
    final w = p.width >= p.height ? 842.0 : 595.0;
    final h = (w * p.height / p.width).toStringAsFixed(2);
    final page = pageObj(i), image = page + 1, content = page + 2;

    offsets[page] = bytes.length;
    write('$page 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $w $h] '
        '/Resources << /XObject << /Im0 $image 0 R >> >> /Contents $content 0 R >>\nendobj\n');

    offsets[image] = bytes.length;
    write('$image 0 obj\n<< /Type /XObject /Subtype /Image /Width ${p.width} '
        '/Height ${p.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 '
        '/Filter /FlateDecode /Length ${p.compressed.length} >>\nstream\n');
    bytes.add(p.compressed);
    write('\nendstream\nendobj\n');

    offsets[content] = bytes.length;
    final draw = 'q $w 0 0 $h 0 0 cm /Im0 Do Q';
    write('$content 0 obj\n<< /Length ${draw.length} >>\nstream\n$draw\nendstream\nendobj\n');
  }

  final xrefOffset = bytes.length;
  write('xref\n0 ${count + 1}\n');
  write('0000000000 65535 f \n');
  for (var n = 1; n <= count; n++) {
    write('${offsets[n]!.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size ${count + 1} /Root 1 0 R >>\n');
  write('startxref\n$xrefOffset\n%%EOF\n');

  return bytes.toBytes();
}

/// بينزّل ملف على جهاز المستخدم.
/// Saves a file to the user's machine.
void downloadBytes(String fileName, String mimeType, Uint8List data) {
  final blob = web.Blob(
    [data.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';

  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();

  // بنفضي الـ URL بعد ما المتصفح يبدأ التنزيل عشان الذاكرة ما تتراكمش.
  // Release the URL once the download has started so memory isn't retained.
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
