import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// ملف اختاره المستخدم من جهازه.
/// A file the user picked from their machine.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;

  /// نوع الملف زي ما المتصفح شافه — بيتبعت للموديل مع الملف.
  /// The browser's own view of the type; sent to the model with the file.
  final String mimeType;
}

/// بيفتح ديالوج اختيار ملف ويرجّع محتواه، أو null لو المستخدم لغى.
/// Opens the file dialog and returns the file's bytes, or null if cancelled.
///
/// مكتوب بالإيد بدل مكتبة جاهزة عن قصد: نسخ الويب من file_picker بتشيل الـ input
/// من الصفحة فورًا بعد `click()` وبتسجّل مستمع `focus` بيلغي العملية — والاتنين
/// بيمنعوا الديالوج إنه يفتح أصلاً في كروم. هنا الـ input بيفضل في الصفحة لحد ما
/// المستخدم يخلص.
///
/// Hand-written on purpose: file_picker's web implementation removes the input
/// from the DOM immediately after `click()` and registers a window `focus`
/// listener that cancels the pick — either is enough to stop Chrome opening the
/// dialog at all. Here the input stays in the document until the user is done.
String _mimeFromName(String name) => switch (name.split('.').last.toLowerCase()) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => 'application/octet-stream',
    };

Future<PickedFile?> pickLocalFile({required List<String> extensions}) {
  final completer = Completer<PickedFile?>();

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = extensions.map((e) => '.$e').join(',')
    ..multiple = false
    ..style.display = 'none';

  void finish(PickedFile? file) {
    if (completer.isCompleted) return;
    input.remove();
    completer.complete(file);
  }

  input.addEventListener(
    'change',
    (web.Event _) {
      final files = input.files;
      if (files == null || files.length == 0) {
        finish(null);
        return;
      }

      final file = files.item(0)!;
      final reader = web.FileReader();

      reader.addEventListener(
        'load',
        (web.Event _) {
          final buffer = reader.result as JSArrayBuffer?;
          if (buffer == null) {
            finish(null);
            return;
          }
          finish(PickedFile(
            name: file.name,
            bytes: buffer.toDart.asUint8List(),
            // بعض المتصفحات بتسيب النوع فاضي — بنستنتجه من الامتداد وقتها.
            // Some browsers leave the type blank; fall back to the extension.
            mimeType: file.type.isNotEmpty
                ? file.type
                : _mimeFromName(file.name),
          ));
        }.toJS,
      );

      reader.addEventListener('error', ((web.Event _) => finish(null)).toJS);
      reader.readAsArrayBuffer(file);
    }.toJS,
  );

  // المتصفحات الحديثة بتبعت 'cancel' لما المستخدم يقفل الديالوج من غير اختيار.
  // Modern browsers fire 'cancel' when the dialog closes with nothing chosen.
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);

  web.document.body!.append(input);
  input.click();

  return completer.future;
}
