import 'dart:convert';

import 'package:http/http.dart' as http;

import 'style_profile.dart';

/// بيجيب صورة حقيقية لكل بلوك صورة في التلخيص، ويشيل اللي ملقاش ليه صورة.
/// Finds a real picture for each image block, dropping any that find none.
///
/// الصور من ويكيبيديا وويكيميديا مش متولّدة: الرسم التشريحي أو مخطط الجهاز
/// لازم يبقى صح، والصورة المتولّدة بتخترع تفاصيل. وكمان السيرفرين دول بيسمحوا
/// بالقراية من موقع تاني، فالصورة بتتصوّر جوه الـ PNG/PDF عادي.
/// Pictures come from Wikipedia/Wikimedia rather than being generated: an
/// anatomy drawing or a device diagram has to be right, and generated images
/// invent details. Both servers also allow cross-origin reads, so the picture
/// still ends up inside the exported PNG/PDF.
Future<SummaryPage> attachImages(SummaryPage page, {http.Client? client}) async {
  final images = page.blocks.where((b) => b.type == BlockType.image).toList();
  if (images.isEmpty) return page;

  final c = client ?? http.Client();
  try {
    final urls = await Future.wait(
      images.map((b) => _lookup(c, b.query.isEmpty ? b.text : b.query)),
    );
    final found = <SummaryBlock, String>{};
    final used = <String>{};
    for (var i = 0; i < images.length; i++) {
      final url = urls[i];
      if (url != null && used.add(url)) found[images[i]] = url;
    }

    return page.withBlocks([
      for (final b in page.blocks)
        if (b.type != BlockType.image)
          b
        else if (found[b] != null)
          b.copyWith(imageUrl: found[b]),
    ]);
  } finally {
    if (client == null) c.close();
  }
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
