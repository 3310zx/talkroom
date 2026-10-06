import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/services/attachment_parser.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// v1.2.1 文件解析器单元测试：
/// txt/md/pdf/docx 提取、8000 字符截断、失败/跳过降级、状态字段序列化。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('llm_chat_app_parser_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String writeTemp(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file.path;
  }

  group('txt/md 提取', () {
    test('txt 完整提取文本', () async {
      final path = writeTemp(
          'note.txt', utf8.encode('第一行中文\nsecond line English\n'));
      final r = await AttachmentParser.parseInBackground(path, 'note.txt');
      expect(r.parseStatus, 'done');
      expect(r.text, contains('第一行中文'));
      expect(r.text, contains('second line English'));
      expect(r.charCount, greaterThan(10));
    });

    test('md 完整提取并保留换行', () async {
      final path = writeTemp(
          'readme.md',
          utf8.encode('# 标题\n\n- 列表项一\n- 列表项二\n\n```dart\nvoid main() {}\n```'));
      final r = await AttachmentParser.parseInBackground(path, 'readme.md');
      expect(r.parseStatus, 'done');
      expect(r.text, contains('# 标题'));
      expect(r.text, contains('列表项二'));
      expect(r.text, contains('void main() {}'));
      expect(r.charCount, greaterThan(20));
    });

    test('超过 8000 字符自动截断并记录完整长度', () async {
      final long = '${'A' * 100}\n${'中文' * 5000}';
      final path = writeTemp('long.txt', utf8.encode(long));
      final r = await AttachmentParser.parseInBackground(path, 'long.txt');
      expect(r.parseStatus, 'done');
      expect(r.text.length, AttachmentParser.kMaxParsedChars);
      expect(r.charCount, greaterThan(AttachmentParser.kMaxParsedChars));
      expect(r.charCount, long.length);
    });
  });

  group('pdf 提取', () {
    test('pdf 文本层提取', () async {
      final doc = pw.Document();
      doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (ctx) =>
              pw.Text('Hello PDF 你好世界\nThis is a pdf text layer.')));
      final bytes = await doc.save();
      final path = writeTemp('sample.pdf', bytes);
      final r = await AttachmentParser.parseInBackground(path, 'sample.pdf');
      expect(r.parseStatus, 'done');
      // Syncfusion 提取器按行/词换行（如 Hello\r\nPDF），归一化空白后断言。
      // 注：pdf 包默认字体无中文字形，样本仅含英文可提取文本。
      final normalized = r.text.replaceAll(RegExp(r'\s+'), ' ');
      expect(normalized, contains('Hello PDF'));
      expect(normalized, contains('pdf text layer'));
      expect(r.charCount, greaterThan(10));
    });

    test('损坏 PDF 标记 failed', () async {
      final path = writeTemp('broken.pdf', utf8.encode('not a pdf at all'));
      final r = await AttachmentParser.parseInBackground(path, 'broken.pdf');
      expect(r.parseStatus, 'failed');
      expect(r.error, isNotNull);
      expect(r.text, isEmpty);
    });
  });

  group('docx 提取', () {
    test('docx 解包提取 w:t 文本（按段落换行）', () async {
      const documentXml =
          '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>第一段：你好世界</w:t></w:r></w:p>
    <w:p><w:r><w:t>第二段：Docx 解析测试</w:t></w:r></w:p>
  </w:body>
</w:document>''';
      final zip = Archive()
        ..addFile(ArchiveFile(
            '[Content_Types].xml',
            utf8.encode(
                    '<?xml version="1.0" encoding="UTF-8"?>'
                    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                    '<Default Extension="xml" ContentType="application/xml"/>'
                    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
                    '</Types>')
                .length,
            utf8.encode(
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
                '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                '<Default Extension="xml" ContentType="application/xml"/>'
                '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
                '</Types>')))
        ..addFile(ArchiveFile(
            '_rels/.rels',
            utf8.encode(
                    '<?xml version="1.0" encoding="UTF-8"?>'
                    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
                    '</Relationships>')
                .length,
            utf8.encode(
                '<?xml version="1.0" encoding="UTF-8"?>'
                '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
                '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
                '</Relationships>')))
        ..addFile(ArchiveFile('word/document.xml', utf8.encode(documentXml).length,
            utf8.encode(documentXml)));
      final bytes = ZipEncoder().encode(zip);
      final path = writeTemp('sample.docx', bytes);
      final r = await AttachmentParser.parseInBackground(path, 'sample.docx');
      expect(r.parseStatus, 'done');
      expect(r.text, contains('第一段：你好世界'));
      expect(r.text, contains('第二段：Docx 解析测试'));
      expect(r.charCount, greaterThan(15));
    });

    test('非 docx 压缩包标记 failed', () async {
      final zip = Archive()
        ..addFile(ArchiveFile('hello.txt', 5, utf8.encode('hello')));
      final bytes = ZipEncoder().encode(zip);
      final path = writeTemp('fake.docx', bytes);
      final r = await AttachmentParser.parseInBackground(path, 'fake.docx');
      expect(r.parseStatus, 'failed');
    });
  });

  group('失败/跳过降级', () {
    test('音视频/未知格式标记 skipped 原样发送', () async {
      final path = writeTemp('movie.mp4', utf8.encode('binary data'));
      final r = await AttachmentParser.parseInBackground(path, 'movie.mp4');
      expect(r.parseStatus, 'skipped');
      expect(r.text, isEmpty);
    });

    test('不存在的文件标记 failed', () async {
      final r = await AttachmentParser.parseInBackground(
          '${tempDir.path}/nope.txt', 'nope.txt');
      expect(r.parseStatus, 'failed');
    });
  });

  group('MessageAttachment 状态字段序列化', () {
    test('toMap/fromMap 保留解析状态字段', () {
      final att = MessageAttachment(
        type: 'file',
        name: 'report.pdf',
        mimeType: 'application/pdf',
        sizeBytes: 2048,
        dataBase64: 'aGVsbG8=',
        parsedText: '解析文本',
        parsedCharCount: 120,
        parseStatus: 'done',
      );
      final restored = MessageAttachment.fromMap(att.toMap());
      expect(restored.parsedText, '解析文本');
      expect(restored.parsedCharCount, 120);
      expect(restored.parseStatus, 'done');
      expect(restored.hasParsedText, isTrue);
    });

    test('旧数据（无解析字段）默认 none 无需迁移', () {
      final legacy = MessageAttachment.fromMap({
        'type': 'file',
        'name': 'old.txt',
        'data_base64': 'aGVsbG8=',
      });
      expect(legacy.parseStatus, 'none');
      expect(legacy.parsedText, isNull);
      expect(legacy.parsedCharCount, isNull);
      expect(legacy.hasParsedText, isFalse);
    });

    test('copyWith 更新解析状态', () {
      final base = MessageAttachment(type: 'file', name: 'a.txt');
      final updated =
          base.copyWith(parsedText: 'x', parsedCharCount: 1, parseStatus: 'done');
      expect(updated.parseStatus, 'done');
      expect(updated.hasParsedText, isTrue);
      expect(base.parseStatus, 'none'); // 原对象不变
    });
  });
}
