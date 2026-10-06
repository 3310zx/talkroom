import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/models/conversation.dart';
import '../domain/models/message.dart';

/// 会话导出（R11，v1.0.15；v1.0.18 修复导出失败与内存问题）。
///
/// 支持将当前会话导出为 Markdown / 纯文本 / PDF 三种格式：
/// - Android：生成文件后调用系统分享面板（可「保存到下载目录」或分享到其它应用）；
/// - 桌面端：同样走系统分享/保存（macOS/Windows 分享面板或直接打开目录）。
///
/// v1.0.18 变更：
/// - Markdown / 纯文本改为流式写入（IOSink 分批 add + flush，最后 close），
///   避免大会话一次性 StringBuffer 拼接导致峰值内存过高；
/// - PDF 打包中文字体 NotoSansSC-Regular.ttf，正文使用 pw.Paragraph 自动换行，
///   避免 helvetica 缺中文字形导致乱码、溢出与内存暴涨；
/// - 导出前做规模防护：消息数 > 3000 或总文本 > 30MB 时抛出明确异常，
///   提示用户先精简会话或改用分页导出。
class ConversationExporter {
  ConversationExporter._();

  static const List<String> kFormats = ['markdown', 'text', 'pdf'];

  /// 导出规模防护上限：消息条数（M6 起用于分卷粒度，超限自动分卷）。
  static const int kMaxMessages = 3000;

  /// 导出规模防护上限：总文本字符数（30MB，粗略按 1 字符 = 1 字节估算）。
  static const int kMaxTotalChars = 30 * 1024 * 1024;

  /// PDF 中文字体资源路径（pubspec.yaml assets/fonts/ 已注册）。
  static const String kPdfFontAsset = 'assets/fonts/NotoSansSC-Regular.ttf';

  /// 弹出格式选择并导出当前会话。
  static Future<void> exportConversation(
    BuildContext context,
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    final format = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '导出会话',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('导出为 Markdown'),
              subtitle: const Text('保留标题与角色标注，适合文档归档'),
              onTap: () => Navigator.of(sheetContext).pop('markdown'),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('导出为纯文本'),
              subtitle: const Text('无格式纯文本，适合记事本查看'),
              onTap: () => Navigator.of(sheetContext).pop('text'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('导出为 PDF'),
              subtitle: const Text('排版友好的 PDF 文件（含中文字体）'),
              onTap: () => Navigator.of(sheetContext).pop('pdf'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // M6：超过规模上限时自动分卷导出，不再抛异常拒绝。
      final files = await _buildFiles(conversation, messages, format);
      final volumeSuffix = files.length > 1 ? '（${files.length} 卷）' : '';
      await Share.shareXFiles(
        files.map((f) => XFile(f.path)).toList(),
        subject: '会话导出：${conversation.title}$volumeSuffix',
        text: '来自 LLM Chat 的会话导出',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  /// M6：按规模上限把消息拆成若干卷，每卷消息数 ≤ [kMaxMessages] 且
  /// 总字符数 ≤ [kMaxTotalChars]。未超限时返回单卷。
  ///
  /// 边界规则：单条消息自身超过字符上限时仍单独成卷（宁可超限也不丢弃）；
  /// 拆分只按「消息」粒度进行，不会截断单条消息内容。
  static List<List<ChatMessage>> chunkMessages(List<ChatMessage> messages) {
    if (messages.length <= kMaxMessages &&
        _estimateChars(messages) <= kMaxTotalChars) {
      return [messages];
    }
    final chunks = <List<ChatMessage>>[];
    var current = <ChatMessage>[];
    var currentChars = 0;
    for (final message in messages) {
      final messageChars = _messageChars(message);
      if (current.isNotEmpty &&
          (current.length >= kMaxMessages ||
              currentChars + messageChars > kMaxTotalChars)) {
        chunks.add(current);
        current = <ChatMessage>[];
        currentChars = 0;
      }
      current.add(message);
      currentChars += messageChars;
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  static int _messageChars(ChatMessage message) {
    var total = message.content.length;
    for (final attachment in message.attachments) {
      total += attachment.name.length;
    }
    return total;
  }

  static int _estimateChars(List<ChatMessage> messages) {
    var total = 0;
    for (final message in messages) {
      total += _messageChars(message);
      if (total > kMaxTotalChars) break;
    }
    return total;
  }

  static Future<List<File>> _buildFiles(
    Conversation conversation,
    List<ChatMessage> messages,
    String format,
  ) async {
    final chunks = chunkMessages(messages);
    final dir = await getTemporaryDirectory();
    final safeTitle = _sanitize(conversation.title.isEmpty
        ? '未命名会话'
        : conversation.title);
    final base = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}';
    final files = <File>[];
    for (var i = 0; i < chunks.length; i++) {
      final volume = chunks.length == 1 ? '' : '_第${i + 1}卷';
      final chunk = chunks[i];
      switch (format) {
        case 'markdown':
          final file = File('${dir.path}/$base$volume.md');
          final sink = file.openWrite();
          try {
            await _writeMarkdown(sink, conversation, chunk);
            await sink.flush();
          } finally {
            await sink.close();
          }
          files.add(file);
        case 'text':
          final file = File('${dir.path}/$base$volume.txt');
          final sink = file.openWrite();
          try {
            await _writePlainText(sink, conversation, chunk);
            await sink.flush();
          } finally {
            await sink.close();
          }
          files.add(file);
        case 'pdf':
          final file = File('${dir.path}/$base$volume.pdf');
          final bytes = await _buildPdfBytes(conversation, chunk);
          await file.writeAsBytes(bytes);
          files.add(file);
        default:
          throw ArgumentError('未知导出格式：$format');
      }
    }
    return files;
  }

  /// Markdown 导出：标题 + 消息列表（角色、时间、正文），流式写入。
  static Future<void> _writeMarkdown(
    IOSink sink,
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    sink
      ..writeln('# ${conversation.title.isEmpty ? '未命名会话' : conversation.title}')
      ..writeln()
      ..writeln('> 导出时间：${_formatFull(DateTime.now())}')
      ..writeln('> 消息数：${messages.length}')
      ..writeln();
    for (final message in messages) {
      if (message.role == 'system') continue;
      final role = message.role == 'user' ? '用户' : 'AI';
      sink
        ..writeln('## $role（${_formatFull(DateTime.fromMillisecondsSinceEpoch(message.createdAt))}）')
        ..writeln()
        ..writeln(message.content.trim())
        ..writeln();
      if (message.attachments.isNotEmpty) {
        for (final attachment in message.attachments) {
          sink.writeln('> [附件] ${attachment.name}');
        }
        sink.writeln();
      }
      // 分批 flush，控制写入缓冲水位，避免峰值内存过高。
      if (messages.length > 200 && (messages.indexOf(message) % 200 == 199)) {
        await sink.flush();
      }
    }
  }

  /// 纯文本导出：角色前缀 + 正文，流式写入。
  static Future<void> _writePlainText(
    IOSink sink,
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    sink
      ..writeln(conversation.title.isEmpty ? '未命名会话' : conversation.title)
      ..writeln('导出时间：${_formatFull(DateTime.now())} · 消息数：${messages.length}')
      ..writeln('----------------------------------------')
      ..writeln();
    for (final message in messages) {
      if (message.role == 'system') continue;
      final role = message.role == 'user' ? '用户' : 'AI';
      sink
        ..writeln('[$role ${_formatFull(DateTime.fromMillisecondsSinceEpoch(message.createdAt))}]')
        ..writeln(message.content.trim())
        ..writeln();
      if (message.attachments.isNotEmpty) {
        for (final attachment in message.attachments) {
          sink.writeln('（附件：${attachment.name}）');
        }
        sink.writeln();
      }
      if (messages.length > 200 && (messages.indexOf(message) % 200 == 199)) {
        await sink.flush();
      }
    }
  }

  /// PDF 导出：使用 pdf 包排版（标题 + 逐条消息）。
  ///
  /// v1.0.18：加载 NotoSansSC-Regular.ttf 中文字体；正文改用
  /// pw.Paragraph 自动换行（受页面宽度约束），避免长内容溢出与内存暴涨。
  static Future<Uint8List> _buildPdfBytes(
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    final fontData = await rootBundle.load(kPdfFontAsset);
    final font = pw.Font.ttf(fontData);
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          final children = <pw.Widget>[
            pw.Header(
              level: 0,
              child: pw.Text(
                conversation.title.isEmpty ? '未命名会话' : conversation.title,
                style: pw.TextStyle(font: font, fontSize: 18),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 12),
              child: pw.Text(
                '导出时间：${_formatFull(DateTime.now())} · 消息数：${messages.length}',
                style: pw.TextStyle(
                    font: font, fontSize: 10, color: PdfColors.grey700),
              ),
            ),
          ];
          for (final message in messages) {
            if (message.role == 'system') continue;
            final role = message.role == 'user' ? '用户' : 'AI';
            children.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '$role · ${_formatFull(DateTime.fromMillisecondsSinceEpoch(message.createdAt))}',
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 11,
                        color: message.role == 'user'
                            ? PdfColors.blueGrey700
                            : PdfColors.teal700,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 3),
                      child: pw.Paragraph(
                        text: message.content.trim(),
                        style: pw.TextStyle(font: font, fontSize: 11),
                        textAlign: pw.TextAlign.left,
                      ),
                    ),
                    if (message.attachments.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Paragraph(
                          text: message.attachments
                              .map((a) => '附件：${a.name}')
                              .join('；'),
                          style: pw.TextStyle(
                              font: font, fontSize: 9, color: PdfColors.grey600),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }
          return children;
        },
      ),
    );
    return doc.save();
  }

  static String _sanitize(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    return cleaned.isEmpty ? '未命名会话' : cleaned;
  }

  static String _formatFull(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
