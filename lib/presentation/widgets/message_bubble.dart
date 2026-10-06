import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/models/message.dart';
import 'image_preview_page.dart';

/// 消息气泡（微信风格：左侧 AI、右侧用户）。
///
/// - 用户消息：右侧纯文本气泡；
/// - 助手消息：左侧 Markdown 渲染气泡（`flutter_markdown` + `flutter_highlight`
///   代码块高亮，识别 language 标签，深/浅色主题自适应；LaTeX 公式
///   `$$...$$` / `$...$` 经 flutter_math_fork 渲染为公式形态）；
/// - 思维链：`reasoningContent` 非空时以「思考过程 · 用时 X.Xs · 消耗 N tokens」
///   折叠卡片展示（默认收起，点击展开），与正文明显区分；
/// - 错误态：`status == 'error'` 显示错误边框与中文错误摘要 + 重试按钮；
/// - 停止态：`status == 'stopped'` 保留已生成内容并标注「已停止生成」；
/// - 长按菜单（R3）：复制 / 重新生成 / 编辑（仅用户）/ 删除 / 引用 / 分享。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.isUser,
    required this.content,
    this.status,
    this.errorMessage,
    this.onRetry,
    this.reasoningContent,
    this.reasoningDurationMs,
    this.reasoningTokens,
    this.onRegenerate,
    this.onEdit,
    this.onDelete,
    this.onQuote,
    this.attachments = const [],
  });

  final bool isUser;
  final String content;
  final String? status;
  final String? errorMessage;
  final VoidCallback? onRetry;

  /// R9：消息附件（图片/文件），仅用户消息携带。
  final List<MessageAttachment> attachments;

  /// 思维链文本（与正文分离展示，默认折叠）
  final String? reasoningContent;

  /// 思考耗时（毫秒），为空则不显示用时
  final int? reasoningDurationMs;

  /// 思考消耗 token 数（usage 缺失时为估算值），为空则不显示
  final int? reasoningTokens;

  // ---- 长按菜单（R3） ----
  /// 重新生成（重新发起该请求生成新回复）
  final VoidCallback? onRegenerate;

  /// 编辑原文重发（仅用户消息传入）
  final VoidCallback? onEdit;

  /// 删除该条消息
  final VoidCallback? onDelete;

  /// 以引用块样式带入输入框
  final VoidCallback? onQuote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = status == 'error';
    final isStreaming = status == 'streaming';
    final isStopped = status == 'stopped';
    final hasReasoning = reasoningContent != null && reasoningContent!.isNotEmpty;

    final bubbleColor = isError
        ? theme.colorScheme.errorContainer
        : isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showActionMenu(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 560),
          decoration: BoxDecoration(
            color: bubbleColor,
            border: isError
                ? Border.all(color: theme.colorScheme.error, width: 1)
                : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // R9：用户消息附件（图片缩略图 / 文件卡片）。
              if (attachments.isNotEmpty) ...[
                for (final att in attachments)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _AttachmentView(attachment: att),
                  ),
                if (content.trim().isNotEmpty)
                  const SizedBox(height: 2),
              ],
              // 思维链折叠卡片：灰色底、斜体小字、分隔线，与正文明显区分。
              if (hasReasoning && !isUser) ...[
                _ReasoningCard(
                  content: reasoningContent!,
                  durationMs: reasoningDurationMs,
                  tokens: reasoningTokens,
                ),
                if (content.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
              // 统一渲染：用户消息与助手消息都经 flutter_markdown 渲染，
              // 避免标题/列表/加粗等基础语法在部分消息中显示为原始标记符号。
              // 数学公式（R1）：注册 math_block / math_inline 语法与构建器，
              // 块级 $$...$$ 与行内 $...$ 渲染为公式形态而非纯文本。
              // v1.0.18 修复：气泡 shrink-wrap 导致 MarkdownBody 处于无界宽度
              // 环境，列表/长文本不换行被裁切或与相邻元素重叠；用
              // SizedBox(width: double.infinity) 提供有界宽度，使其正常换行。
              if (content.trim().isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: MarkdownBody(
                    data: content,
                    selectable: true,
                    extensionSet: md.ExtensionSet(
                      md.ExtensionSet.gitHubFlavored.blockSyntaxes +
                          [_MathBlockSyntax()],
                      md.ExtensionSet.gitHubFlavored.inlineSyntaxes +
                          [_MathInlineSyntax()],
                    ),
                    builders: {
                      'pre': _CodeBlockBuilder(),
                      'math_block': _MathBuilder(inline: false),
                      'math_inline': _MathBuilder(inline: true),
                      'table': _TableBuilder(),
                      'img': _MarkdownImageBuilder(),
                      'a': _LinkBuilder(),
                    },
                    styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                      p: theme.textTheme.bodyLarge,
                    ),
                  ),
                )
              else if (!hasReasoning)
                Text(
                  isStreaming ? '正在思考…' : '',
                  style: theme.textTheme.bodyLarge,
                ),
              if (isStreaming)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      const Text('生成中…', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              if (isStopped)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '已停止生成',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (isError && errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    errorMessage!,
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.error),
                  ),
                ),
              if (isError && onRetry != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 长按消息气泡弹出操作菜单（R3）：
  /// 复制 / 重新生成 / 编辑（仅用户）/ 删除 / 引用 / 分享。
  /// 复制与分享在气泡内直接完成；重新生成/编辑/删除/引用由上层回调驱动
  /// （回调未传入时对应菜单项隐藏）。
  void _showActionMenu(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[
      ListTile(
        leading: const Icon(Icons.copy),
        title: const Text('复制'),
        onTap: () {
          Navigator.of(context).pop();
          _copyContent(context);
        },
      ),
      if (onRegenerate != null)
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('重新生成'),
          onTap: () {
            Navigator.of(context).pop();
            onRegenerate!();
          },
        ),
      if (onEdit != null)
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('编辑'),
          onTap: () {
            Navigator.of(context).pop();
            onEdit!();
          },
        ),
      if (onDelete != null)
        ListTile(
          leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
          title: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
          onTap: () {
            Navigator.of(context).pop();
            onDelete!();
          },
        ),
      if (onQuote != null)
        ListTile(
          leading: const Icon(Icons.format_quote),
          title: const Text('引用'),
          onTap: () {
            Navigator.of(context).pop();
            onQuote!();
          },
        ),
      ListTile(
        leading: const Icon(Icons.share_outlined),
        title: const Text('分享'),
        onTap: () {
          Navigator.of(context).pop();
          Share.share(content, subject: 'LLM Chat 消息');
        },
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                isUser ? '消息操作' : '消息操作',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ...items,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _copyContent(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
  }
}

/// 思维链折叠卡片（默认收起，点击标题展开/收起）。
///
/// 样式刻意与正文区分：灰色圆角底、斜体小字、标题行显示
/// 「思考过程 · 用时 X.Xs · 消耗 N tokens」，防止与正文混淆。
class _ReasoningCard extends StatefulWidget {
  const _ReasoningCard({
    required this.content,
    this.durationMs,
    this.tokens,
  });

  final String content;
  final int? durationMs;
  final int? tokens;

  @override
  State<_ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<_ReasoningCard> {
  bool _expanded = false;

  String get _title {
    final parts = <String>['思考过程'];
    final ms = widget.durationMs;
    if (ms != null) {
      parts.add('用时 ${(ms / 1000).toStringAsFixed(1)}s');
    }
    final tokens = widget.tokens;
    if (tokens != null && tokens > 0) {
      parts.add('消耗 $tokens tokens');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.colorScheme.surfaceContainerHighest;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _title,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
              child: Text(
                widget.content,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// R9：用户消息附件视图。
///
/// - 图片（type == 'image'）：解码 `dataBase64` 显示圆角缩略图，
///   点击进入 [ImagePreviewPage] 全屏预览（R5）；
/// - 文件（type == 'file'）：文件卡片，展示类型图标 / 文件名 / 大小 /
///   文本预览（前 120 字符）。
class _AttachmentView extends StatelessWidget {
  const _AttachmentView({required this.attachment});

  final MessageAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final att = attachment;
    if (att.isImage) {
      final data = att.dataBase64;
      if (data == null || data.isEmpty) {
        return _FileCard(attachment: att);
      }
      return GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImagePreviewPage(
                base64Data: data,
                title: att.name,
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, maxHeight: 240),
            child: Image.memory(
              base64Decode(data),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
            ),
          ),
        ),
      );
    }
    return _FileCard(attachment: att);
  }
}

/// 文件卡片：类型图标（按 MIME 粗略分类）+ 文件名 + 大小 + 文本预览。
class _FileCard extends StatelessWidget {
  const _FileCard({required this.attachment});

  final MessageAttachment attachment;

  IconData get _icon {
    final mime = attachment.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('zip') ||
        mime.contains('compressed') ||
        mime.contains('tar')) {
      return Icons.folder_zip_outlined;
    }
    if (mime.contains('word') || mime.contains('document')) {
      return Icons.description_outlined;
    }
    if (mime.contains('excel') || mime.contains('sheet')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String get _sizeLabel {
    final size = attachment.sizeBytes;
    if (size == null || size <= 0) return '';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 240,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(_icon, size: 32, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  attachment.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (_sizeLabel.isNotEmpty)
                  Text(
                    _sizeLabel,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                if (attachment.textPreview != null &&
                    attachment.textPreview!.trim().isNotEmpty)
                  Text(
                    attachment.textPreview!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                // v1.2.1：文件解析状态行。
                if (attachment.parseStatus != 'none')
                  Text(
                    _parseStatusLine(attachment),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: attachment.parseStatus == 'failed'
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 解析状态展示文案。
  String _parseStatusLine(MessageAttachment att) {
    switch (att.parseStatus) {
      case 'done':
        final count = att.parsedCharCount ?? att.parsedText?.length ?? 0;
        return '已解析 $count 字符，以文本发送';
      case 'failed':
        return '解析失败，建议转图片发送';
      case 'skipped':
        return '不支持解析，已原样发送';
      case 'parsing':
        return '解析中';
      default:
        return '';
    }
  }
}

/// 图片加载失败占位。
class _BrokenImagePlaceholder extends StatelessWidget {
  const _BrokenImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.broken_image_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// R4：Markdown 表格渲染（长表格横向滚动 / 自适应宽度）。
///
/// 每列宽度取 `MaxColumnWidth(IntrinsicColumnWidth(), FlexColumnWidth())`：
/// 内容较窄时各列弹性分配铺满气泡宽度（自适应），内容超宽时按内容固有
/// 宽度撑开，整体由外层横向 `SingleChildScrollView` 滚动查看，
/// 避免手机端长表格被挤压变形。
class _TableBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // 收集表格行（thead/tbody 或平铺 tr）。
    final rows = <List<md.Element>>[];
    void collectRow(md.Element row) {
      if (row.tag != 'tr') return;
      final cells = <md.Element>[];
      for (final cell in row.children ?? const <md.Node>[]) {
        if (cell is md.Element && (cell.tag == 'th' || cell.tag == 'td')) {
          cells.add(cell);
        }
      }
      if (cells.isNotEmpty) rows.add(cells);
    }

    for (final child in element.children ?? const <md.Node>[]) {
      if (child is md.Element &&
          (child.tag == 'thead' || child.tag == 'tbody')) {
        for (final row in child.children ?? const <md.Node>[]) {
          if (row is md.Element) collectRow(row);
        }
      } else if (child is md.Element) {
        collectRow(child);
      }
    }
    if (rows.isEmpty) return null;

    final colCount =
        rows.fold<int>(0, (max, r) => r.length > max ? r.length : max);
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;
    final headerBg = theme.colorScheme.surfaceContainerHighest;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          for (var i = 0; i < colCount; i++)
            i: const MaxColumnWidth(
              IntrinsicColumnWidth(),
              FlexColumnWidth(),
            ),
        },
        border: TableBorder.all(color: borderColor, width: 0.6),
        children: [
          for (var r = 0; r < rows.length; r++)
            TableRow(
              decoration: rows[r].first.tag == 'th'
                  ? BoxDecoration(color: headerBg)
                  : null,
              children: [
                for (var c = 0; c < colCount; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                    child: c < rows[r].length
                        ? Text(
                            rows[r][c].textContent.trim(),
                            style: rows[r][c].tag == 'th'
                                ? (preferredStyle ??
                                        theme.textTheme.bodyMedium)
                                    ?.copyWith(fontWeight: FontWeight.bold)
                                : preferredStyle ?? theme.textTheme.bodyMedium,
                          )
                        : const SizedBox(),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// R5：Markdown 图片渲染（点击全屏预览，可关闭）。
class _MarkdownImageBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => false;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final src = element.attributes['src'] ?? '';
    final alt = element.attributes['alt'] ?? '';
    if (src.isEmpty) return null;
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ImagePreviewPage(
              url: src,
              title: alt.isEmpty ? null : alt,
            ),
          ),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
        child: Image.network(
          src,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const _BrokenImagePlaceholder(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: 120,
              height: 120,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// R5：Markdown 链接渲染（点击用系统浏览器打开；长按复制链接）。
class _LinkBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => false;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final href = element.attributes['href'] ?? '';
    final text = element.textContent;
    if (href.isEmpty) {
      return Text(text, style: preferredStyle ?? parentStyle);
    }
    final theme = Theme.of(context);
    final linkStyle = (preferredStyle ?? parentStyle ?? theme.textTheme.bodyMedium)
        ?.copyWith(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    return GestureDetector(
      onTap: () => _openLink(context, href),
      onLongPress: () => _copyLink(context, href),
      child: Text(text, style: linkStyle),
    );
  }

  Future<void> _openLink(BuildContext context, String href) async {
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }
  }

  Future<void> _copyLink(BuildContext context, String href) async {
    await Clipboard.setData(ClipboardData(text: href));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('链接已复制'), duration: Duration(seconds: 1)),
      );
  }
}

/// 提取 fenced code block 的源码与语言标签（`language-dart` 等），
/// 交给 [_CodeBlockView] 用 HighlightView 高亮渲染。
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag != 'pre') return null;
    var source = '';
    String? language;
    for (final node in element.children ?? const <md.Node>[]) {
      if (node is md.Element && node.tag == 'code') {
        source += node.textContent;
        final classes = node.attributes['class'] ?? '';
        final match = RegExp(r'language-(\S+)').firstMatch(classes);
        language = match?.group(1);
      } else if (node is md.Text) {
        source += node.textContent;
      }
    }
    return _CodeBlockView(source: source.trimRight(), language: language);
  }
}

/// 代码块高亮视图（PRD 2.4 P0）：识别语言标签后用 `flutter_highlight`
/// 渲染，深 / 浅色主题随应用 Theme.brightness 切换；
/// 未知语言或未标注语言时回退 plaintext（安全降级）。
/// 右上角提供「一键复制」按钮（R2）：点击复制全文并短暂提示「已复制」。
class _CodeBlockView extends StatefulWidget {
  const _CodeBlockView({required this.source, this.language});

  final String source;
  final String? language;

  @override
  State<_CodeBlockView> createState() => _CodeBlockViewState();
}

class _CodeBlockViewState extends State<_CodeBlockView> {
  bool _copied = false;

  /// highlight 内置支持的语言关键字；未知一律回退 plaintext。
  static const Set<String> _knownLanguages = {
    'plaintext',
    'text',
    'dart',
    'python',
    'py',
    'javascript',
    'js',
    'typescript',
    'ts',
    'java',
    'c',
    'cpp',
    'csharp',
    'cs',
    'go',
    'rust',
    'kotlin',
    'swift',
    'ruby',
    'php',
    'sql',
    'html',
    'xml',
    'css',
    'json',
    'yaml',
    'yml',
    'bash',
    'shell',
    'sh',
    'markdown',
    'md',
    'ini',
    'diff',
    'gradle',
    'groovy',
    'scala',
    'lua',
    'perl',
    'r',
    'haskell',
    'elixir',
    'erlang',
    'clojure',
    'd',
    'vbnet',
    'matlab',
    'julia',
    'powershell',
    'docker',
    'makefile',
    'nginx',
    'toml',
    'protobuf',
    'graphql',
    'latex',
  };

  String get _resolvedLanguage {
    final lang = widget.language?.toLowerCase() ?? '';
    return _knownLanguages.contains(lang) ? lang : 'plaintext';
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.source));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = _resolvedLanguage;
    final headerColor = scheme.surfaceContainerHighest;
    final labelColor = scheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            color: headerColor,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    resolved == 'plaintext' ? 'code' : resolved,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: labelColor,
                    ),
                  ),
                ),
                // 一键复制（R2）：点击复制全文，短暂显示「已复制」。
                InkWell(
                  onTap: _copied ? null : _copy,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 14,
                          color: _copied ? scheme.primary : labelColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? '已复制' : '复制',
                          style: TextStyle(
                            fontSize: 11,
                            color: _copied ? scheme.primary : labelColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: HighlightView(
              widget.source,
              language: resolved,
              theme: scheme.brightness == Brightness.dark
                  ? atomOneDarkTheme
                  : atomOneLightTheme,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

/// 数学公式块级语法：行首 `$$` 起，至下一个 `$$`（或文档末尾）为块级
/// LaTeX 公式（PRD 2.4 / R1），构建为 `math_block` 元素交给 [_MathBuilder]。
class _MathBlockSyntax extends md.BlockSyntax {
  @override
  RegExp get pattern => RegExp(r'^\$\$');

  @override
  bool canEndBlock(md.BlockParser parser) => true;

  @override
  md.Node parse(md.BlockParser parser) {
    final buffer = StringBuffer();
    parser.advance(); // 消费起始 $$
    while (parser.peek(0) != null) {
      final line = parser.peek(0)!;
      final text = line.content.trimRight();
      if (text.trim().startsWith(r'$$')) {
        parser.advance();
        break;
      }
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(text);
      parser.advance();
    }
    return md.Element('math_block', [md.Text(buffer.toString())]);
  }
}

/// 数学公式行内语法：`$...$` 渲染为行内 LaTeX 公式（R1）。
/// 负向断言避免把 `$$...$$` 块级分隔符误当作行内公式起点/终点。
class _MathInlineSyntax extends md.InlineSyntax {
  _MathInlineSyntax() : super(r'(?<!\$)\$([^\n$]+)\$(?!\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final element = md.Element('math_inline', [md.Text(match[1]!)]);
    parser.addNode(element);
    return true;
  }
}

/// 数学公式构建器：将 LaTeX 源码交给 flutter_math_fork 渲染为公式形态。
class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({required this.inline});

  final bool inline;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final tex = element.textContent.trim();
    if (tex.isEmpty) return null;
    return Padding(
      padding: inline ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 4),
      child: Math.tex(
        tex,
        mathStyle: inline ? MathStyle.text : MathStyle.display,
        textStyle: TextStyle(
          fontSize: inline ? 14 : 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
