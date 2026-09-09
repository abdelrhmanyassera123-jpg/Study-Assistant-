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
  });

  final String fileName;
  final String text;

  /// عدد الشرايح (pptx) أو الفقرات (docx) — بنعرضه عشان المستخدم يطمن
  /// إن الاستخراج شغال قبل ما يستنى التلخيص.
  /// Slides (pptx) or paragraphs (docx); shown so the user can sanity-check
  /// the extraction before waiting on a summary.
  final int blocks;

  bool get isEmpty => text.trim().isEmpty;

  /// تقدير تقريبي — العربي بياخد توكنز أكتر من الإنجليزي لكل حرف.
  /// Rough estimate; Arabic runs more tokens per character than English.
  int get approxTokens => (text.length / 2.6).round();
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
    'pptx' => _extractPptx(fileName, bytes),
    'txt' || 'md' || 'markdown' => _extractPlain(fileName, bytes),
    _ => throw UnsupportedDocumentException(ext),
  };
}

/// الامتدادات اللي بنفك نصها في المتصفح.
/// Extensions whose text we unpack in the browser.
const extractableExtensions = ['pptx', 'docx', 'txt', 'md'];

/// الامتدادات اللي بنبعتها للموديل زي ما هي — الموديل بيقراها بنفسه.
/// Extensions handed to the model untouched; it reads them itself.
const modelReadableExtensions = ['pdf'];

const supportedDocumentExtensions = [
  ...extractableExtensions,
  ...modelReadableExtensions,
];

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
  for (var i = 0; i < slideFiles.length; i++) {
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
  );
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
