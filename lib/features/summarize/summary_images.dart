import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'style_profile.dart';

@JS('renderPdfPages')
external JSPromise<JSArray<JSUint8Array?>> _renderPdfPages(
  JSUint8Array bytes,
  JSArray<JSNumber> pages,
  JSNumber width,
);

/// بيجيب صورة لكل بلوك صورة في التلخيص، ويشيل اللي ملقاش ليه صورة.
/// Finds a picture for each image block, dropping any that find none.
///
/// الترتيب: صفحة من السلايدات المرفوعة (رسمة الدكتور نفسها)، وبعدها ويكيبيديا
/// وويكيميديا. مفيش صور متولّدة: الرسم التشريحي لازم يبقى صح، والمتولّد
/// بيخترع تفاصيل — المخططات اللي بتترسم من الكلام هي اللي بتسد المكان ده.
/// The order: a page from the uploaded slides (the lecturer's own figure),
/// then Wikipedia and Wikimedia. Nothing is generated: an anatomy drawing has
/// to be right and generated ones invent details — the diagrams drawn from
/// the text are what fill that gap.
Future<SummaryPage> attachImages(
  SummaryPage page, {
  List<Uint8List> pdfs = const [],
  http.Client? client,
}) async {
  final images = page.blocks
      .where((b) => b.type == BlockType.image && !b.hasPicture)
      .toList();
  if (images.isEmpty) return page;

  final rendered = await _renderSlides(images, pdfs);

  final c = client ?? http.Client();
  try {
    final needWeb = images.where((b) => rendered[b] == null).toList();
    final urls = await Future.wait(
      needWeb.map((b) => _lookup(c, b.query.isEmpty ? b.text : b.query)),
    );
    final found = <SummaryBlock, String>{};
    final used = <String>{};
    for (var i = 0; i < needWeb.length; i++) {
      final url = urls[i];
      if (url != null && used.add(url)) found[needWeb[i]] = url;
    }

    return page.withBlocks([
      for (final b in page.blocks)
        if (b.type != BlockType.image || b.hasPicture)
          b
        else if (rendered[b] != null)
          b.copyWith(imageData: rendered[b])
        else if (found[b] != null)
          b.copyWith(imageUrl: found[b]),
    ]);
  } finally {
    if (client == null) c.close();
  }
}

/// بيرسم صفحات السلايدات المطلوبة، ملف ملف. أي فشل (pdf.js ما اتحمّلش، رقم
/// صفحة غلط) بيرجع لويكيبيديا بدل ما يوقّف التلخيص.
/// Renders the requested slide pages, file by file. Any failure (pdf.js did
/// not load, a wrong page number) falls back to Wikipedia instead of stopping
/// the summary.
Future<Map<SummaryBlock, Uint8List>> _renderSlides(
  List<SummaryBlock> images,
  List<Uint8List> pdfs,
) async {
  final out = <SummaryBlock, Uint8List>{};
  if (pdfs.isEmpty) return out;

  final byDoc = <int, List<SummaryBlock>>{};
  for (final b in images) {
    final page = b.page;
    if (page == null || b.doc < 1 || b.doc > pdfs.length) continue;
    byDoc.putIfAbsent(b.doc, () => []).add(b);
  }

  for (final entry in byDoc.entries) {
    try {
      final blocks = entry.value;
      final result = await _renderPdfPages(
        pdfs[entry.key - 1].toJS,
        [for (final b in blocks) b.page!.toJS].toJS,
        1100.toJS,
      ).toDart;
      final list = result.toDart;
      for (var i = 0; i < blocks.length && i < list.length; i++) {
        final bytes = list[i]?.toDart;
        if (bytes != null && bytes.isNotEmpty) out[blocks[i]] = bytes;
      }
    } catch (_) {}
  }
  return out;
}

Future<String?> _lookup(http.Client client, String query) async {
  if (query.trim().isEmpty) return null;
  try {
    return await _fromWikipedia(client, query) ?? await _fromCommons(client, query);
  } catch (_) {
    return null;
  }
}

/// الصورة الرئيسية لأقرب مقالة — غالبًا هي الرسم التوضيحي للموضوع نفسه.
/// The lead image of the closest article, usually the topic's own diagram.
Future<String?> _fromWikipedia(http.Client client, String query) async {
  final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
    'action': 'query',
    'format': 'json',
    'origin': '*',
    'generator': 'search',
    'gsrsearch': query,
    'gsrlimit': '3',
    'prop': 'pageimages',
    'piprop': 'thumbnail',
    'pithumbsize': '800',
  });
  final pages = await _pages(client, uri);
  if (pages == null) return null;

  final ranked = pages.toList()
    ..sort((a, b) => ((a['index'] as num?) ?? 99).compareTo((b['index'] as num?) ?? 99));
  for (final p in ranked) {
    final src = (p['thumbnail'] as Map?)?['source'];
    if (src is String && _isPicture(src)) return src;
  }
  return null;
}

Future<String?> _fromCommons(http.Client client, String query) async {
  final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
    'action': 'query',
    'format': 'json',
    'origin': '*',
    'generator': 'search',
    'gsrnamespace': '6',
    'gsrsearch': '$query filetype:bitmap|drawing',
    'gsrlimit': '3',
    'prop': 'imageinfo',
    'iiprop': 'url',
    'iiurlwidth': '800',
  });
  final pages = await _pages(client, uri);
  if (pages == null) return null;

  final ranked = pages.toList()
    ..sort((a, b) => ((a['index'] as num?) ?? 99).compareTo((b['index'] as num?) ?? 99));
  for (final p in ranked) {
    final info = p['imageinfo'];
    if (info is List && info.isNotEmpty) {
      final src = (info.first as Map?)?['thumburl'];
      if (src is String && _isPicture(src)) return src;
    }
  }
  return null;
}

Future<Iterable<Map<String, dynamic>>?> _pages(http.Client client, Uri uri) async {
  final res = await client.get(uri).timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) return null;
  final body = jsonDecode(res.body);
  final pages = (body is Map ? body['query'] : null)?['pages'];
  if (pages is! Map) return null;
  return pages.values.whereType<Map<String, dynamic>>();
}

/// الأيقونات والأعلام مش بتشرح حاجة.
/// Icons and flags explain nothing.
bool _isPicture(String url) {
  final lower = url.toLowerCase();
  return !lower.contains('flag_of') &&
      !lower.contains('icon') &&
      !lower.contains('logo') &&
      !lower.contains('question_book');
}
