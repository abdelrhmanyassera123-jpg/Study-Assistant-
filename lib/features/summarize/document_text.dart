import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// نص مستخرج من ملف محاضرة.
/// Text pulled out of a lecture file.
class ExtractedDocument {
  const ExtractedDocument({
    required this.fileName,
    required this.text,
    required this.blocks,
    this.slideCount = 0,
    this.images = const [],
  });

  final String fileName;
  final String text;

  /// عدد الشرايح كلها، حتى اللي مفيهاش كلام (pptx بس).
  /// Every slide, including those without text (pptx only).
  final int slideCount;

  /// الصور اللي جوه الشرايح بالترتيب (pptx بس).
  /// The pictures inside the slides, in order (pptx only).
  final List<SlideImage> images;

  /// عدد الشرايح (pptx) أو الفقرات (docx) — بنعرضه عشان المستخدم يطمن
  /// إن الاستخراج شغال قبل ما يستنى التلخيص.
  /// Slides (pptx) or paragraphs (docx); shown so the user can sanity-check
  /// the extraction before waiting on a summary.
  final int blocks;

  bool get isEmpty => text.trim().isEmpty;

  /// شرايح أغلبها صور: سلايدات متصورة سكان، أو كلام مرسوم جوه صور. نصها لوحده
  /// مش كفاية، فالصور بتتبعت للموديل يقراها.
  /// Slides that are mostly pictures: scanned slides, or words drawn inside
  /// images. Their text alone is not enough, so the pictures go to the model.
  bool get mostlyPictures =>
      images.isNotEmpty && text.trim().length < 60 * (slideCount < 1 ? 1 : slideCount);

  /// تقدير تقريبي — العربي بياخد توكنز أكتر من الإنجليزي لكل حرف.
  /// Rough estimate; Arabic runs more tokens per character than English.
  int get approxTokens => (text.length / 2.6).round();
}

/// صورة من جوه شريحة.
/// A picture from inside a slide.
class SlideImage {
  const SlideImage({required this.name, required this.mimeType, required this.bytes});

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// ملف Office قديم (قبل 2007) — مش أرشيف ZIP، فمينفعش يتفك في المتصفح.
/// An old (pre-2007) Office file: not a ZIP archive, so it cannot be opened in
/// the browser.
class LegacyOfficeException implements Exception {
  const LegacyOfficeException(this.extension);

  final String extension;

  @override
  String toString() => 'Old Office format: .$extension';
}

class UnsupportedDocumentException implements Exception {
  const UnsupportedDocumentException(this.extension);

  final String extension;

  @override
  String toString() => 'Unsupported file type: .$extension';
}

/// بيستخرج النص من pptx / docx / txt / md **جوه المتصفح**.
/// Extracts text from pptx / docx / txt / md **inside the browser**.
///
/// ملفات Office أصلاً أرشيف ZIP جواه XML، فمحتاجينش سيرفر يفكها — وده معناه
/// إن ملف المحاضرة نفسه ما بيخرجش من جهاز المستخدم أبدًا.
/// Office files are just ZIP archives of XML, so no server is needed to open
/// them — which means the lecture file itself never leaves the user's machine.
ExtractedDocument extractDocumentText(String fileName, Uint8List bytes) {
  final ext = fileName.split('.').last.toLowerCase();

  return switch (ext) {
    'docx' => _extractDocx(fileName, bytes),
    'pptx' || 'ppsx' || 'pptm' => _extractPptx(fileName, bytes),
    'ppt' || 'pps' || 'doc' => throw LegacyOfficeException(ext),
    'txt' || 'md' || 'markdown' => _extractPlain(fileName, bytes),
    _ => throw UnsupportedDocumentException(ext),
  };
}

/// الامتدادات اللي بنفك نصها في المتصفح.
/// Extensions whose text we unpack in the browser.
const extractableExtensions = ['pptx', 'ppsx', 'pptm', 'docx', 'txt', 'md'];

/// صيغ Office القديمة: بتظهر في الاختيار عشان المستخدم يلاقي ملفه ويعرف يعمل
/// إيه، بدل ما تبان رمادي من غير سبب.
/// The old Office formats: listed in the picker so the user finds their file
/// and is told what to do, instead of it showing greyed out for no reason.
const legacyOfficeExtensions = ['ppt', 'pps', 'doc'];

/// أنواع الملفات بالـ MIME — أندرويد بيفلتر بيها مش بالامتداد، فمن غيرها ملف
/// الباوربوينت ممكن يبان رمادي في الاختيار.
/// The file types by MIME: Android filters by these rather than the
/// extension, and without them a PowerPoint file can show greyed out.
const documentMimeTypes = [
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.openxmlformats-officedocument.presentationml.slideshow',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/msword',
  'application/pdf',
  'text/plain',
];

/// الامتدادات اللي بنبعتها للموديل زي ما هي — الموديل بيقراها بنفسه.
/// Extensions handed to the model untouched; it reads them itself.
const modelReadableExtensions = ['pdf'];

const supportedDocumentExtensions = [
  ...extractableExtensions,
  ...modelReadableExtensions,
  ...legacyOfficeExtensions,
];

/// الصور: صورة سبورة، سلايد، أو صفحة كتاب — الموديل بيقراها بنفسه.
/// Pictures: a whiteboard, a slide or a book page — the model reads them
/// itself.
const imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'heic'];

bool isImageFile(String fileName) =>
    imageExtensions.contains(fileName.split('.').last.toLowerCase());

bool isExtractable(String fileName) => [
      ...extractableExtensions,
      ...legacyOfficeExtensions,
    ].contains(fileName.split('.').last.toLowerCase());

/// هل الملف ده بيتبعت كملف بدل ما نستخرج نصه؟
/// Is this file sent as a file rather than text-extracted?
bool isModelReadable(String fileName) =>
    modelReadableExtensions.contains(fileName.split('.').last.toLowerCase());

ExtractedDocument _extractPlain(String fileName, Uint8List bytes) {
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  return ExtractedDocument(
    fileName: fileName,
    text: text,
    blocks: text.isEmpty ? 0 : text.split(RegExp(r'\n\s*\n')).length,
  );
}

/// docx: النص كله في word/document.xml، كل فقرة `<w:p>` فيها أجزاء `<w:t>`.
/// docx: everything lives in word/document.xml; each `<w:p>` paragraph holds
/// one or more `<w:t>` runs that must be joined without separators.
ExtractedDocument _extractDocx(String fileName, Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final entry = archive.findFile('word/document.xml');
  if (entry == null) {
    throw const FormatException('word/document.xml missing — not a valid .docx');
  }

  final document = XmlDocument.parse(_readAsString(entry));
  final paragraphs = <String>[];

  for (final p in document.findAllElements('p', namespaceUri: '*')) {
    final runs = p.findAllElements('t', namespaceUri: '*').map((t) => t.innerText);
    final line = runs.join().trim();
    if (line.isNotEmpty) paragraphs.add(line);
  }

  return ExtractedDocument(
    fileName: fileName,
    text: paragraphs.join('\n\n'),
    blocks: paragraphs.length,
  );
}

/// pptx: كل شريحة ملف ppt/slides/slideN.xml لوحدها، والنص في `<a:t>`.
/// pptx: each slide is its own ppt/slides/slideN.xml, with text in `<a:t>`.
ExtractedDocument _extractPptx(String fileName, Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  final slideFiles = archive.files
      .where((f) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f.name))
      .toList()
    // ترتيب رقمي مش أبجدي، وإلا slide10 هتيجي قبل slide2.
    // Numeric order, otherwise slide10 sorts before slide2.
    ..sort((a, b) => _slideNumber(a.name).compareTo(_slideNumber(b.name)));

  if (slideFiles.isEmpty) {
    throw const FormatException('no slides found — not a valid .pptx');
  }

  final slides = <String>[];
  final images = <SlideImage>[];
  final seen = <String>{};
  for (var i = 0; i < slideFiles.length; i++) {
    for (final image in _slideImages(archive, slideFiles[i].name)) {
      if (seen.add(image.name)) images.add(image);
    }
    final document = XmlDocument.parse(_readAsString(slideFiles[i]));
    final lines = document
        .findAllElements('t', namespaceUri: '*')
        .map((t) => t.innerText.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (lines.isNotEmpty) {
      slides.add('[${i + 1}]\n${lines.join('\n')}');
    }
  }

  return ExtractedDocument(
    fileName: fileName,
    text: slides.join('\n\n'),
    blocks: slides.length,
    slideCount: slideFiles.length,
    images: images,
  );
}

/// الصور اللي الشريحة بتستخدمها، من ملف علاقاتها
/// (ppt/slides/_rels/slideN.xml.rels) — كده بتيجي بترتيب الشرايح مش بترتيب
/// أسماء الملفات.
/// The pictures a slide uses, from its relationships file
/// (ppt/slides/_rels/slideN.xml.rels), so they come in slide order rather
/// than by file name.
///
/// الصيغ اللي الموديل بيقراها بس: EMF وWMF رسومات أوفيس الموديل بيرفضها.
/// Only formats the model reads: EMF and WMF are Office drawings it rejects.
List<SlideImage> _slideImages(Archive archive, String slidePath) {
  final slideName = slidePath.split('/').last;
  final rels = archive.findFile('ppt/slides/_rels/$slideName.rels');
  if (rels == null) return const [];

  final XmlDocument document;
  try {
    document = XmlDocument.parse(_readAsString(rels));
  } catch (_) {
    return const [];
  }

  final found = <SlideImage>[];
  for (final rel in document.findAllElements('Relationship', namespaceUri: '*')) {
    if (!(rel.getAttribute('Type') ?? '').endsWith('/image')) continue;
    final target = rel.getAttribute('Target') ?? '';
    final name = target.startsWith('../')
        ? 'ppt/${target.substring(3)}'
        : target.startsWith('/')
            ? target.substring(1)
            : 'ppt/slides/$target';
    final mime = switch (name.split('.').last.toLowerCase()) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      _ => null,
    };
    if (mime == null) continue;
    final bytes = archive.findFile(name)?.readBytes();
    if (bytes == null) continue;
    found.add(SlideImage(name: name, mimeType: mime, bytes: Uint8List.fromList(bytes)));
  }
  return found;
}

int _slideNumber(String path) =>
    int.tryParse(RegExp(r'slide(\d+)\.xml$').firstMatch(path)?.group(1) ?? '') ?? 0;

String _readAsString(ArchiveFile file) {
  final content = file.readBytes();
  if (content == null) {
    throw FormatException('could not read ${file.name} from the archive');
  }
  return utf8.decode(content, allowMalformed: true);
}
