import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// صورة جاية من الحافظة (اتنسخت واتلصقت).
/// A picture from the clipboard (copied, then pasted).
class PastedImage {
  const PastedImage({required this.name, required this.mimeType, required this.bytes});

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// لصق الصور: خانة الكتابة في Flutter بتلصق نص بس، فالصور بتتمسك من حدث
/// "paste" بتاع المتصفح نفسه، وبتوصل لأي شاشة سامعة. الشاشة بتاخدها لو خانة
/// من خاناتها هي اللي عليها الفوكس.
/// Pasting pictures: a Flutter text field pastes text only, so pictures are
/// caught from the browser's own "paste" event and handed to whichever
/// screen is listening. A screen takes them when one of its fields has
/// focus.
class PasteImages {
  PasteImages._();

  static final _pasted = StreamController<List<PastedImage>>.broadcast();
  static bool _listening = false;

  /// الصور اللي اتلصقت، دفعة لكل لصقة.
  /// Pasted pictures, one batch per paste.
  static Stream<List<PastedImage>> get stream {
    _listen();
    return _pasted.stream;
  }

  static void _listen() {
    if (_listening) return;
    _listening = true;
    web.window.addEventListener(
      'paste',
      ((web.Event event) {
        final data = (event as web.ClipboardEvent).clipboardData;
        if (data == null) return;
        final files = <web.File>[];
        for (var i = 0; i < data.files.length; i++) {
          final f = data.files.item(i);
          if (f != null && f.type.startsWith('image/')) files.add(f);
        }
        if (files.isEmpty) return;
        // صورة من غير نص: منع اللصق العادي، عشان اسم الملف ما يتكتبش في الخانة.
        // A picture with no text: stop the ordinary paste so the file's name is
        // not typed into the field.
        if (data.getData('text/plain').isEmpty) event.preventDefault();
        _read(files).then((images) {
          if (images.isNotEmpty) _pasted.add(images);
        });
      }).toJS,
    );
  }

  static Future<List<PastedImage>> _read(List<web.File> files) async {
    final out = <PastedImage>[];
    for (final f in files) {
      final buffer = await f.arrayBuffer().toDart;
      out.add(PastedImage(
        name: f.name.isEmpty || f.name == 'image.png' ? _name(f.type) : f.name,
        mimeType: f.type,
        bytes: buffer.toDart.asUint8List(),
      ));
    }
    return out;
  }

  /// زرار "الصق": بيقرا الصور من الحافظة مباشرة — للموبايل، لأن لصق صورة جوه
  /// خانة نص مش بيشتغل في كل الكيبوردات. المتصفح بيسأل المستخدم أول مرة.
  /// The "paste" button: reads pictures straight off the clipboard. For
  /// phones, where pasting a picture into a text field does not work with
  /// every keyboard. The browser asks the user the first time.
  ///
  /// بيرجّع null لو المتصفح مش بيدعم أو المستخدم رفض.
  /// Returns null when the browser has no support or the user refused.
  static Future<List<PastedImage>?> readClipboard() async {
    try {
      final items = (await web.window.navigator.clipboard.read().toDart).toDart;
      final out = <PastedImage>[];
      for (final item in items) {
        for (final type in item.types.toDart.map((t) => t.toDart)) {
          if (!type.startsWith('image/')) continue;
          final blob = await item.getType(type).toDart;
          final buffer = await blob.arrayBuffer().toDart;
          out.add(PastedImage(name: _name(type), mimeType: type, bytes: buffer.toDart.asUint8List()));
          break;
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  static int _count = 0;

  static String _name(String type) {
    final ext = type.split('/').last.replaceAll('jpeg', 'jpg');
    final now = DateTime.now();
    return 'صورة ${now.hour}-${now.minute.toString().padLeft(2, '0')}-${++_count}.$ext';
  }
}
