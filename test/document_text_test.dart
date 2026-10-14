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

  group('pptx pictures', () {
    String rels(List<String> targets) =>
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '${[
          for (var i = 0; i < targets.length; i++)
            '<Relationship Id="rId${i + 1}" '
                'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
                'Target="${targets[i]}"/>',
        ].join()}'
        '<Relationship Id="rLayout" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" '
        'Target="../slideLayouts/slideLayout1.xml"/>'
        '</Relationships>';

    Uint8List withMedia(Map<String, String> entries, Map<String, List<int>> media) {
      final archive = Archive();
      entries.forEach((name, content) => archive.add(ArchiveFile.string(name, content)));
      media.forEach((name, bytes) => archive.add(ArchiveFile(name, bytes.length, bytes)));
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    // سلايدات متصورة سكان: مفيش ولا كلمة نص، والمحاضرة كلها جوه الصور.
    // Scanned slides: not one word of text; the whole lecture is in the images.
    test('scanned slides hand their pictures over in slide order', () {
      final bytes = withMedia({
        'ppt/slides/slide1.xml': slideXml(const []),
        'ppt/slides/slide2.xml': slideXml(const []),
        'ppt/slides/_rels/slide1.xml.rels': rels(['../media/image9.png']),
        'ppt/slides/_rels/slide2.xml.rels': rels(['../media/image2.jpeg', '../media/logo.emf']),
      }, {
        'ppt/media/image9.png': [1, 2, 3],
        'ppt/media/image2.jpeg': [4, 5],
        'ppt/media/logo.emf': [6],
      });

      final doc = extractDocumentText('lecture.pptx', bytes);

      expect(doc.isEmpty, isTrue);
      expect(doc.slideCount, 2);
      expect(doc.mostlyPictures, isTrue);
      expect(doc.images.map((i) => i.name), ['ppt/media/image9.png', 'ppt/media/image2.jpeg']);
      expect(doc.images.first.mimeType, 'image/png');
      expect(doc.images.last.mimeType, 'image/jpeg');
    });

    // صورة اللوجو بتتكرر في كل شريحة — تتبعت مرة واحدة بس.
    // A logo repeated on every slide is sent once only.
    test('a picture used on many slides is kept once', () {
      final bytes = withMedia({
        'ppt/slides/slide1.xml': slideXml(const []),
        'ppt/slides/slide2.xml': slideXml(const []),
        'ppt/slides/_rels/slide1.xml.rels': rels(['../media/logo.png']),
        'ppt/slides/_rels/slide2.xml.rels': rels(['../media/logo.png']),
      }, {
        'ppt/media/logo.png': [1],
      });

      expect(extractDocumentText('l.pptx', bytes).images, hasLength(1));
    });

    test('slides full of text are not treated as pictures', () {
      final words = List.filled(20, 'الجهد يساوي التيار مضروب في المقاومة').join(' ');
      final bytes = withMedia({
        'ppt/slides/slide1.xml': slideXml([words]),
        'ppt/slides/_rels/slide1.xml.rels': rels(['../media/chart.png']),
      }, {
        'ppt/media/chart.png': [1],
      });

      final doc = extractDocumentText('l.pptx', bytes);
      expect(doc.images, hasLength(1));
      expect(doc.mostlyPictures, isFalse);
    });

    test('a slideshow (.ppsx) opens like a presentation', () {
      final bytes = buildOfficeFile({'ppt/slides/slide1.xml': slideXml(['قانون أوم'])});
      expect(extractDocumentText('l.ppsx', bytes).text, contains('قانون أوم'));
    });

    // الـ ppt القديم مش ZIP — لازم رسالة تقول للمستخدم يحفظه pptx، مش "صيغة
    // مش مدعومة" وخلاص.
    // The old ppt is not a ZIP: the user must be told to save it as pptx, not
    // just "unsupported".
    test('an old .ppt is recognised and explained, not just refused', () {
      expect(isExtractable('lecture.ppt'), isTrue);
      expect(
        () => extractDocumentText('lecture.ppt', Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0])),
        throwsA(isA<LegacyOfficeException>()),
      );
    });
  });
}
