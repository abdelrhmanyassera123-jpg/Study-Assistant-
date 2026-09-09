import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_assistant/features/summarize/document_text.dart';

/// بيبني ملف Office حقيقي (ZIP + XML) عشان نختبر الاستخراج على البنية الفعلية
/// مش على نص متزوّر.
/// Builds a real Office file (ZIP + XML) so extraction is tested against the
/// actual structure rather than a stand-in string.
Uint8List buildOfficeFile(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    archive.add(ArchiveFile.string(name, content));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String docxXml(List<List<String>> paragraphs) {
  final body = paragraphs
      .map((runs) =>
          '<w:p>${runs.map((r) => '<w:r><w:t>$r</w:t></w:r>').join()}</w:p>')
      .join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>$body</w:body></w:document>';
}

String slideXml(List<String> lines) {
  final shapes = lines
      .map((t) => '<p:sp><p:txBody><a:p><a:r><a:t>$t</a:t></a:r></a:p></p:txBody></p:sp>')
      .join();
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
      '<p:cSld><p:spTree>$shapes</p:spTree></p:cSld></p:sld>';
}

void main() {
  group('docx', () {
    test('joins runs inside a paragraph and separates paragraphs', () {
      // وورد بيقسم الجملة الواحدة لأجزاء عند أي تغيير تنسيق — لازم تتلزق
      // من غير مسافات زيادة.
      // Word splits one sentence into runs at any formatting change; they must
      // rejoin with no added spacing.
      final bytes = buildOfficeFile({
        'word/document.xml': docxXml([
          ['قانون ', 'أوم'],
          ['الجهد = التيار × المقاومة'],
        ]),
      });

      final doc = extractDocumentText('lecture.docx', bytes);

      expect(doc.text, 'قانون أوم\n\nالجهد = التيار × المقاومة');
      expect(doc.blocks, 2);
      expect(doc.isEmpty, isFalse);
    });

    test('skips empty paragraphs', () {
      final bytes = buildOfficeFile({
        'word/document.xml': docxXml([
          ['نص'],
          [],
          ['   '],
          ['تاني'],
        ]),
      });

      expect(extractDocumentText('a.docx', bytes).blocks, 2);
    });

    test('rejects a zip that is not a docx', () {
      final bytes = buildOfficeFile({'random.txt': 'nope'});
      expect(
        () => extractDocumentText('fake.docx', bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('pptx', () {
    test('reads slides in numeric order, not alphabetical', () {
      // slide10 لازم تيجي بعد slide2 — الترتيب الأبجدي بيحطها قبلها.
      // slide10 must come after slide2; alphabetical ordering puts it first.
      final bytes = buildOfficeFile({
        'ppt/slides/slide1.xml': slideXml(['الأولى']),
        'ppt/slides/slide2.xml': slideXml(['التانية']),
        'ppt/slides/slide10.xml': slideXml(['العاشرة']),
      });

      final doc = extractDocumentText('deck.pptx', bytes);

      expect(doc.blocks, 3);
      final first = doc.text.indexOf('الأولى');
      final second = doc.text.indexOf('التانية');
      final tenth = doc.text.indexOf('العاشرة');
      expect(first, greaterThanOrEqualTo(0));
      expect(second, greaterThan(first));
      expect(tenth, greaterThan(second));
    });

    test('keeps every text run on a slide', () {
      final bytes = buildOfficeFile({
        'ppt/slides/slide1.xml': slideXml(['العنوان', 'نقطة أولى', 'نقطة تانية']),
      });

      final doc = extractDocumentText('deck.pptx', bytes);
      expect(doc.text, contains('العنوان'));
      expect(doc.text, contains('نقطة أولى'));
      expect(doc.text, contains('نقطة تانية'));
    });

    test('ignores layouts and masters, counting only real slides', () {
      final bytes = buildOfficeFile({
        'ppt/slides/slide1.xml': slideXml(['محتوى']),
        'ppt/slideLayouts/slideLayout1.xml': slideXml(['قالب مش محتوى']),
        'ppt/slideMasters/slideMaster1.xml': slideXml(['ماستر']),
      });

      final doc = extractDocumentText('deck.pptx', bytes);
      expect(doc.blocks, 1);
      expect(doc.text, isNot(contains('قالب مش محتوى')));
      expect(doc.text, isNot(contains('ماستر')));
    });

    test('rejects a zip with no slides', () {
      final bytes = buildOfficeFile({'ppt/presentation.xml': '<x/>'});
      expect(
        () => extractDocumentText('empty.pptx', bytes),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('plain text and unsupported', () {
    test('reads utf-8 text files', () {
      final bytes = Uint8List.fromList(utf8.encode('سطر أول\n\nسطر تاني'));
      final doc = extractDocumentText('notes.txt', bytes);
      expect(doc.text, 'سطر أول\n\nسطر تاني');
      expect(doc.blocks, 2);
    });

    test('throws a typed error for unknown extensions', () {
      expect(
        () => extractDocumentText('lecture.pdf', Uint8List(0)),
        throwsA(isA<UnsupportedDocumentException>()),
      );
    });
  });
}
