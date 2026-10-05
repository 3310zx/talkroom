import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../domain/models/conversation.dart';
import '../domain/models/message.dart';

/// 会话导出（R11，v1.0.15）。
///
/// 支持将当前会话导出为 Markdown / 纯文本 / PDF 三种格式：
/// - Android：生成文件后调用系统分享面板（可「保存到下载目录」或分享到其它应用）；
/// - 桌面端：同样走系统分享/保存（macOS/Windows 分享面板或直接打开目录）。
class ConversationExporter {
  ConversationExporter._();

  static const List<String> kFormats = ['markdown', 'text', 'pdf'];

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
              subtitle: const Text('排版友好的 PDF 文件'),
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
      final file = await _buildFile(conversation, messages, format);
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '会话导出：${conversation.title}',
        text: '来自 LLM Chat 的会话导出',
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  static Future<File> _buildFile(
    Conversation conversation,
    List<ChatMessage> messages,
    String format,
  ) async {
    final dir = await getTemporaryDirectory();
    final safeTitle = _sanitize(conversation.title.isEmpty
        ? '未命名会话'
        : conversation.title);
    final base = '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}';
    switch (format) {
      case 'markdown':
        final file = File('${dir.path}/$base.md');
        await file.writeAsString(_buildMarkdown(conversation, messages));
        return file;
      case 'text':
        final file = File('${dir.path}/$base.txt');
        await file.writeAsString(_buildPlainText(conversation, messages));
        return file;
      case 'pdf':
        final file = File('${dir.path}/$base.pdf');
        final bytes = await _buildPdfBytes(conversation, messages);
        await file.writeAsBytes(bytes);
        return file;
      default:
        throw ArgumentError('未知导出格式：$format');
    }
  }

  /// Markdown 导出：标题 + 消息列表（角色、时间、正文）。
  static String _buildMarkdown(
    Conversation conversation,
    List<ChatMessage> messages,
  ) {
    final buffer = StringBuffer()
      ..writeln('# ${conversation.title.isEmpty ? '未命名会话' : conversation.title}')
      ..writeln()
      ..writeln('> 导出时间：${_formatFull(DateTime.now())}')
      ..writeln('> 消息数：${messages.length}')
      ..writeln();
    for (final message in messages) {
      if (message.role == 'system') continue;
      final role = message.role == 'user' ? '用户' : 'AI';
      buffer
        ..writeln('## $role（${_formatFull(DateTime.fromMillisecondsSinceEpoch(message.createdAt))}）')
        ..writeln()
        ..writeln(message.content.trim())
        ..writeln();
      if (message.attachments.isNotEmpty) {
        for (final attachment in message.attachments) {
          buffer.writeln('> [附件] ${attachment.name}');
        }
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  /// 纯文本导出：角色前缀 + 正文。
  static String _buildPlainText(
    Conversation conversation,
    List<ChatMessage> messages,
  ) {
    final buffer = StringBuffer()
      ..writeln(conversation.title.isEmpty ? '未命名会话' : conversation.title)
      ..writeln('导出时间：${_formatFull(DateTime.now())} · 消息数：${messages.length}')
      ..writeln('----------------------------------------')
      ..writeln();
    for (final message in messages) {
      if (message.role == 'system') continue;
      final role = message.role == 'user' ? '用户' : 'AI';
      buffer
        ..writeln('[$role ${_formatFull(DateTime.fromMillisecondsSinceEpoch(message.createdAt))}]')
        ..writeln(message.content.trim())
        ..writeln();
      if (message.attachments.isNotEmpty) {
        for (final attachment in message.attachments) {
          buffer.writeln('（附件：${attachment.name}）');
        }
        buffer.writeln();
      }
    }
    return buffer.toString();
  }

  /// PDF 导出：使用 pdf 包排版（标题 + 逐条消息）。
  static Future<Uint8List> _buildPdfBytes(
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    final doc = pw.Document();
    final font = pw.Font.helvetica();
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
                      child: pw.Text(
                        message.content.trim(),
                        style: pw.TextStyle(font: font, fontSize: 11),
                      ),
                    ),
                    if (message.attachments.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 3),
                        child: pw.Text(
                          message.attachments.map((a) => '附件：${a.name}').join('；'),
                          style: pw.TextStyle(
                              font: font, fontSize: 9, color: PdfColors.grey600),
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
