import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'digest.dart';

/// بيرسم جدول اليوم صورة PNG للإشعار المفتوح — نفس شكل web/digest_table.js:
/// اللي شغالة دهبي، والجاية بإطار دهبي، واللي خلصت باهتة.
/// Draws the day's table as a PNG for the expanded notification, the same
/// look as web/digest_table.js: under way in gold, next outlined in gold,
/// finished ones faded.
Future<Uint8List> drawTable(List<DigestRow> all) async {
  // أكتر من 6 صفوف بيبقوا صغيرين أوي في عرض الإشعار؛ اللي بيتشال أقدم اللي خلص.
  // Past 6 rows they get too small at the notification's width; what goes is
  // the earliest of those already over.
  const max = 6;
  var rows = all;
  if (all.length > max) {
    final firstLive = all.indexWhere((r) => r.state != RowState.done);
    final from = ((firstLive < 0 ? all.length : firstLive) - 1).clamp(0, all.length - max);
    rows = all.sublist(from, from + max);
  }

  const w = 720.0;
  const pad = 18.0;
  const rowH = 78.0;
  const gap = 8.0;
  final h = pad * 2 + rows.length * rowH + (rows.length - 1) * gap;

  const page = Color(0xFF18201C);
  const rowColor = Color(0xFF222C27);
  const gold = Color(0xFFE3B341);
  const ink = Color(0xFFF2F5F3);
  const muted = Color(0xFF9DB0A6);
  const dark = Color(0xFF1A1A1A);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(28)),
    Paint()..color = page,
  );

  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    final y = pad + i * (rowH + gap);
    final now = row.state == RowState.now;
    final done = row.state == RowState.done;
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(pad, y, w - pad * 2, rowH), const Radius.circular(18));

    canvas.drawRRect(box, Paint()..color = now ? gold : rowColor);
    if (row.state == RowState.next) {
      canvas.drawRRect(
        box,
        Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }

    final alpha = done ? 0.38 : 1.0;
    final main = (now ? dark : ink).withValues(alpha: alpha);
    final soft = (now ? dark.withValues(alpha: 0.72) : muted).withValues(alpha: done ? 0.38 : null);
    final right = w - pad - 18;

    // الوقت على اليمين، والقاعة على الشمال، والاسم في النص.
    // The time on the right, the room on the left, the name in the middle.
    _text(canvas, row.start, 26, FontWeight.w700, main, right: right, top: y + 10, width: 150);
    _text(canvas, 'لحد ${row.end}', 18, FontWeight.w500, soft, right: right, top: y + 44, width: 150);

    var roomW = 0.0;
    if (row.room.isNotEmpty) {
      roomW = _text(canvas, row.room, 22, FontWeight.w700, main, left: pad + 18, top: y + 25, width: 170);
    }

    final titleRight = right - 150;
    final titleWidth = titleRight - (pad + 18 + roomW + (roomW > 0 ? 22 : 0));
    _text(canvas, row.title, 23, FontWeight.w700, main, right: titleRight, top: y + 12, width: titleWidth);

    final label = switch (row.state) {
      RowState.now => 'دلوقتي',
      RowState.next => 'الجاية',
      RowState.done => 'خلصت',
      RowState.later => '',
    };
    if (label.isNotEmpty) {
      _text(
        canvas,
        label,
        17,
        FontWeight.w600,
        now ? dark : row.state == RowState.next ? gold : soft,
        right: titleRight,
        top: y + 46,
        width: titleWidth,
      );
    }
  }

  final image = await recorder.endRecording().toImage(w.toInt(), h.ceil());
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  return png!.buffer.asUint8List();
}

/// بيكتب سطر واحد بـ "…" لو طويل، ويرجّع عرضه. الإنجليزي بيتكتب شمال-يمين عشان
/// "…" تيجي في آخره.
/// Writes one line, with "…" when too long, and returns its width. English is
/// laid out left-to-right so the "…" lands at its end.
double _text(
  Canvas canvas,
  String text,
  double size,
  FontWeight weight,
  Color color, {
  double? right,
  double? left,
  required double top,
  required double width,
}) {
  if (width <= 0) return 0;
  final latin = RegExp(r'^[^؀-ۿ]*[A-Za-z]').hasMatch(text);
  final painter = TextPainter(
    text: TextSpan(text: text, style: TextStyle(fontSize: size, fontWeight: weight, color: color)),
    textDirection: latin ? TextDirection.ltr : TextDirection.rtl,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: width);
  final x = right != null ? right - painter.width : left!;
  painter.paint(canvas, Offset(x, top));
  return painter.width;
}
