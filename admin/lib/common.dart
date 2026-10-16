import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:web/web.dart' as web;

import 'api.dart';

const brand = Color(0xFF176B58);

String day(DateTime? d) => d == null ? '—' : DateFormat('d/M/yyyy').format(d);
String dayTime(DateTime? d) =>
    d == null ? '—' : '${DateFormat('d/M/yyyy  h:mm').format(d)} ${d.hour < 12 ? 'ص' : 'م'}';

String kindLabel(String kind) => kind == 'paid' ? 'مدفوع' : 'تجريبي';

String sourceLabel(String? source) => switch (source) {
      'legacy' => 'قديم (مجاني)',
      'code' => 'كود',
      'admin' => 'من عندك',
      _ => 'مالوش اشتراك',
    };

/// حالة الكود في كلمتين، ولونها.
/// A code's state in a couple of words, and its colour.
({String label, Color color}) codeState(CodeRow c, UserRow? redeemer) {
  if (c.disabled) return (label: 'مقفول', color: Colors.red.shade700);
  if (c.lapsed) return (label: 'انتهت صلاحيته', color: Colors.grey.shade600);
  if (!c.used) return (label: 'لسه ما اتستخدمش', color: Colors.blue.shade700);
  final left = redeemer?.daysLeft;
  if (redeemer != null && !redeemer.active) return (label: 'خلص', color: Colors.grey.shade700);
  return (label: left == null ? 'شغال' : 'شغال — فاضل $left يوم', color: Colors.green.shade700);
}

class StateChip extends StatelessWidget {
  const StateChip(this.label, this.color, {super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      );
}

void snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

Future<void> copy(BuildContext context, String text, {String message = 'اتنسخ'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) snack(context, message);
}

/// بينزّل جدول كملف CSV بيفتح في Excel (بـ BOM عشان العربي يظهر صح).
/// Downloads a table as a CSV that opens in Excel (with a BOM so Arabic
/// shows correctly).
void downloadCsv(String fileName, List<List<String>> rows) {
  String cell(String v) => '"${v.replaceAll('"', '""')}"';
  final text = '﻿${rows.map((r) => r.map(cell).join(',')).join('\r\n')}';
  final blob = web.Blob([utf8.encode(text).toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}

/// سؤال "متأكد؟" قبل أي حاجة مينفعش ترجع.
/// An "are you sure?" before anything that cannot be undone.
Future<bool> confirm(BuildContext context, String title, String body, {String action = 'تمام'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

/// بيطلب رقم (أيام مثلًا).
/// Asks for a number (days, say).
Future<int?> askNumber(BuildContext context, String title, {int? initial, String hint = ''}) async {
  final field = TextEditingController(text: initial?.toString() ?? '');
  final value = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: field,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(field.text)), child: const Text('حفظ')),
      ],
    ),
  );
  field.dispose();
  return value;
}

/// بيطلب نص (ملاحظة مثلًا).
/// Asks for text (a note, say).
Future<String?> askText(BuildContext context, String title, {String initial = ''}) async {
  final field = TextEditingController(text: initial);
  final value = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: field, autofocus: true, onSubmitted: (v) => Navigator.pop(ctx, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, field.text), child: const Text('حفظ')),
      ],
    ),
  );
  field.dispose();
  return value;
}

/// بيعرض الخطأ بكلام مفهوم بدل نص الاستثناء.
/// Shows a failure in plain words rather than the exception's text.
String errorText(Object e) {
  final s = '$e';
  if (s.contains('admins only')) return 'الحساب ده مش أدمن.';
  if (s.contains('only unused codes')) return 'مينفعش تمسح كود اتستخدم — اقفله بدل كده.';
  if (s.contains('Failed to fetch') || s.contains('SocketException')) return 'مفيش نت.';
  return s;
}

class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      );
}
