import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF 中文标题导出复现', () async {
    final data = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    final font = pw.Font.ttf(data);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) {
          return <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text(
                '新会话',
                style: pw.TextStyle(font: font, fontSize: 18),
              ),
            ),
            pw.Text(
              '导出时间：2026-10-06 15:09:00 · 消息数：2',
              style: pw.TextStyle(font: font, fontSize: 10),
            ),
            pw.Text(
              '你好！我是DeepSeek，测试markdown语法。',
              style: pw.TextStyle(font: font, fontSize: 11),
            ),
            pw.Text(
              '**加粗中文测试** 与 `code` 混排',
              style: pw.TextStyle(font: font, fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
            pw.Paragraph(
              text: '长文本自动换行测试。' * 30,
              style: pw.TextStyle(font: font, fontSize: 11),
            ),
          ];
        },
      ),
    );
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(1000));
  });
}
