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

/// بيصوّر الويدجت ويبني منها PDF صفحة واحدة.
/// Captures the widget and wraps it in a one-page PDF.
Future<Uint8List> capturePdf(GlobalKey boundaryKey, {double pixelRatio = 2.5}) async {
  final boundary =
      boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError('الصفحة لسه مش مرسومة');
  }

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) throw StateError('فشل قراءة بكسلات الصفحة');
    return _pdfFromRgba(
      rgba.buffer.asUint8List(),
      image.width,
      image.height,
    );
  } finally {
    image.dispose();
  }
}

/// بيبني PDF صفحة واحدة فيها الصورة.
/// Builds a single-page PDF containing the image.
///
/// مكتوب بالإيد بدل حزمة PDF جاهزة لسببين: الحزم المتاحة بتتعارض مع نسخة
/// archive المستخدمة، والأهم إن النص هنا **صورة** مش حروف — فمفيش مشكلة تشكيل
/// عربي في الـ PDF من أصلها.
/// Hand-written instead of pulling a PDF package: the available ones clash with
/// the archive version in use, and more importantly the text here is an *image*
/// rather than glyphs, so Arabic shaping in PDF never becomes a problem.
Uint8List _pdfFromRgba(Uint8List rgba, int width, int height) {
  // PDF مش بيفهم قناة الشفافية، فبنشيلها ونسيب RGB.
  // PDF has no alpha channel here, so drop it and keep RGB.
  final rgb = Uint8List(width * height * 3);
  for (var i = 0, j = 0; i < rgba.length; i += 4, j += 3) {
    rgb[j] = rgba[i];
    rgb[j + 1] = rgba[i + 1];
    rgb[j + 2] = rgba[i + 2];
  }

  final compressed = Uint8List.fromList(const ZLibEncoder().encode(rgb));

  // عرض A4 عند 72 نقطة/بوصة، والارتفاع بنفس نسبة الصورة.
  // A4 width at 72dpi, with the height following the image's aspect ratio.
  const pageWidth = 595.0;
  final pageHeight = pageWidth * height / width;
  final h = pageHeight.toStringAsFixed(2);

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidth $h] '
        '/Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>',
    // الكائن ده جسمه ثنائي، فبنركّبه بره القايمة.
    // This object carries binary data, so it is assembled outside the list.
    '',
    '',
  ];

  final bytes = BytesBuilder();
  final offsets = <int>[];

  void write(String s) => bytes.add(latin1.encode(s));

  write('%PDF-1.4\n');

  for (var i = 0; i < objects.length; i++) {
    offsets.add(bytes.length);
    write('${i + 1} 0 obj\n');

    if (i == 3) {
      write('<< /Type /XObject /Subtype /Image /Width $width /Height $height '
          '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode '
          '/Length ${compressed.length} >>\nstream\n');
      bytes.add(compressed);
      write('\nendstream\n');
    } else if (i == 4) {
      final content = 'q $pageWidth 0 0 $h 0 0 cm /Im0 Do Q';
      write('<< /Length ${content.length} >>\nstream\n$content\nendstream\n');
    } else {
      write('${objects[i]}\n');
    }

    write('endobj\n');
  }

  final xrefOffset = bytes.length;
  write('xref\n0 ${objects.length + 1}\n');
  write('0000000000 65535 f \n');
  for (final offset in offsets) {
    write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
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
