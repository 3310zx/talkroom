import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:xml/xml.dart';

/// 文件解析器（v1.2.1）：发送本地文档前提取文本内容，节省 token。
///
/// 支持：
/// - txt / md：直接 UTF-8 解码；
/// - pdf：Syncfusion 纯 Dart 提取文本层（扫描件/加密无文本层 → failed，
///   提示转图片发送）；
/// - docx：archive 解 zip + xml 解析 `word/document.xml` 的 `<w:t>`；
/// - 音视频 / 未知格式：skipped（原样发送，不解析）。
///
/// 解析在 compute isolate 中执行（防大文件阻塞 UI）。PDF 使用
/// syncfusion_flutter_pdf（纯 Dart，无平台通道），故 isolate 与单测均可用；
/// pdfx 2.x 已移除文本提取 API 且依赖平台插件，不满足上述约束。
class AttachmentParser {
  AttachmentParser._();

  /// 解析文本截断上限（字符数），约 2000 token（按 4 字符/token 保守估算）。
  static const int kMaxParsedChars = 8000;

  /// 在 compute isolate 中解析（防大文件阻塞 UI）。
  static Future<AttachmentParseResult> parseInBackground(
    String path,
    String name,
  ) {
    return compute(_parseEntry, AttachmentParseRequest(path, name));
  }

  /// 判断扩展名是否属于可解析文本类（用于 pick 后立即决定是否触发解析）。
  static bool isParsableName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.pdf') ||
        lower.endsWith('.docx');
  }

  /// compute isolate 入口（顶层函数；compute 支持 async 回调）。
  static Future<AttachmentParseResult> _parseEntry(
      AttachmentParseRequest req) async {
    final lower = req.name.toLowerCase();
    try {
      if (lower.endsWith('.txt') || lower.endsWith('.md')) {
        return _parseTextFile(req.path);
      }
      if (lower.endsWith('.pdf')) {
        return _parsePdf(req.path);
      }
      if (lower.endsWith('.docx')) {
        return _parseDocx(req.path);
      }
      return AttachmentParseResult.skipped();
    } catch (e) {
      return AttachmentParseResult.failed('$e');
    }
  }

  static AttachmentParseResult _parseTextFile(String path) {
    final bytes = File(path).readAsBytesSync();
    final text = utf8.decode(bytes, allowMalformed: true);
    return _buildResult(text);
  }

  static AttachmentParseResult _parsePdf(String path) {
    final bytes = File(path).readAsBytesSync();
    sf.PdfDocument? doc;
    try {
      doc = sf.PdfDocument(inputBytes: bytes);
      if (doc.pages.count == 0) {
        return AttachmentParseResult.failed('PDF 无页面');
      }
      final raw = sf.PdfTextExtractor(doc).extractText();
      if (raw.trim().isEmpty) {
        return AttachmentParseResult.failed(
            '扫描件或加密 PDF 无文本层，建议转图片发送');
      }
      return _buildResult(raw);
    } catch (e) {
      return AttachmentParseResult.failed('$e');
    } finally {
      doc?.dispose();
    }
  }

  static AttachmentParseResult _parseDocx(String path) {
    final bytes = File(path).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    String? xmlContent;
    for (final file in archive) {
      if (file.name == 'word/document.xml') {
        xmlContent = utf8.decode(file.content, allowMalformed: true);
        break;
      }
    }
    if (xmlContent == null) {
      return AttachmentParseResult.failed('docx 缺少 document.xml');
    }
    final document = XmlDocument.parse(xmlContent);
    final buffer = StringBuffer();
    // 段落级拼接：每个 <w:p> 内 <w:t> 文本合并，段落间换行。
    // 用 localName 过滤（xml 7.x 的 namespaceUri 匹配不可靠）。
    Iterable<XmlElement> byLocal(String local) =>
        document.descendants.whereType<XmlElement>().where((e) => e.name.local == local);
    for (final paragraph in byLocal('p')) {
      final parts = <String>[];
      for (final t in byLocal('t')) {
        if (t.ancestors.contains(paragraph)) {
          parts.add(t.innerText);
        }
      }
      final line = parts.join();
      if (line.trim().isNotEmpty) {
        buffer.writeln(line);
      }
      if (buffer.length > kMaxParsedChars * 2) break;
    }
    if (buffer.toString().trim().isEmpty) {
      return AttachmentParseResult.failed('docx 未提取到文本');
    }
    return _buildResult(buffer.toString());
  }

  /// 统一截断并生成 done 结果。
  static AttachmentParseResult _buildResult(String raw) {
    final normalized = raw.replaceAll('\u0000', '');
    final total = normalized.length;
    if (total <= kMaxParsedChars) {
      return AttachmentParseResult.done(normalized, total);
    }
    return AttachmentParseResult.done(
        normalized.substring(0, kMaxParsedChars), total);
  }
}

/// compute isolate 入参。
class AttachmentParseRequest {
  final String path;
  final String name;

  const AttachmentParseRequest(this.path, this.name);
}

/// 解析结果。
class AttachmentParseResult {
  final String text;
  final int charCount;
  final String parseStatus; // 'done' | 'failed' | 'skipped'
  final String? error;

  const AttachmentParseResult({
    required this.text,
    required this.charCount,
    required this.parseStatus,
    this.error,
  });

  factory AttachmentParseResult.done(String text, int charCount) =>
      AttachmentParseResult(
          text: text, charCount: charCount, parseStatus: 'done');

  factory AttachmentParseResult.failed(String error) => AttachmentParseResult(
      text: '', charCount: 0, parseStatus: 'failed', error: error);

  factory AttachmentParseResult.skipped() => const AttachmentParseResult(
      text: '', charCount: 0, parseStatus: 'skipped');
}
