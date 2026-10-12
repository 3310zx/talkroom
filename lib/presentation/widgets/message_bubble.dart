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
    this.onVariantReply,
    this.onSaveToMemory,
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

  /// 消息变体动作（功能一）：以指令文本触发重新生成变体
  /// （「更详尽地回答 / 更简洁地回答 / 更个性化的回答」）。
  final void Function(String instruction)? onVariantReply;

  /// 保存到记忆库（功能三）：将该助手消息内容收藏为记忆条目。
  final VoidCallback? onSaveToMemory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = status == 'error';
    final isStreaming = status == 'streaming';
    final isStopped = status == 'stopped';
    final hasReasoning =
        reasoningContent != null && reasoningContent!.isNotEmpty;

    final bubbleColor = isError
        ? theme.colorScheme.errorContainer
        : isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;
    // 暗色模式对比度修复：气泡前景文字必须使用对应的「on」语义色。
    // 用户消息（primaryContainer 底）→ onPrimaryContainer；错误消息
    // （errorContainer 底）→ onErrorContainer；助手消息（surface 底）→
    // onSurface。此前气泡内文字继承 onSurface——暗色 / Monet 动态取色下
    // M3 的 primaryContainer 为亮浅蓝，浅色文字叠浅蓝背景对比度严重不足。
    final fgColor = isError
        ? theme.colorScheme.onErrorContainer
        : isUser
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onLongPress: () {
              HapticFeedback.heavyImpact();
              _showActionMenu(context);
            },
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
              child: DefaultTextStyle(
                style: theme.textTheme.bodyLarge!.copyWith(color: fgColor),
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
                      if (content.trim().isNotEmpty) const SizedBox(height: 2),
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
                            'a': _LinkBuilder(fgColor),
                          },
                          styleSheet: _markdownStyle(theme, fgColor),
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
                            color: fgColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    if (isError && errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onErrorContainer),
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
          ),
          // 消息操作工具栏（R11）：气泡下方图标栏，复制 / 点赞 / 不喜欢 /
          // 分享 / 更多（三点）。「更多」二级菜单承载重试、变体、保存记忆、
          // 重新生成、编辑、删除、引用等；长按菜单保留作为辅助入口。
          _MessageActionBar(
            isUser: isUser,
            content: content,
            status: status,
            onRetry: onRetry,
            onRegenerate: onRegenerate,
            onVariantReply: onVariantReply,
            onSaveToMemory: onSaveToMemory,
            onEdit: onEdit,
            onDelete: onDelete,
            onQuote: onQuote,
            onCopy: () => _copyContent(context),
          ),
        ],
      ),
    );
  }

  /// 长按消息气泡弹出操作菜单（R3）：
  /// 复制 / 重新生成 / 编辑（仅用户）/ 删除 / 引用 / 分享。
  /// 复制与分享在气泡内直接完成；重新生成/重试/变体/保存记忆/编辑/删除/引用
  /// 由上层回调驱动（回调未传入时对应菜单项隐藏）。
  void _showActionMenu(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = status == 'error' || status == 'stopped';
    final items = <Widget>[
      ListTile(
        leading: const Icon(Icons.copy),
        title: const Text('复制'),
        onTap: () {
          Navigator.of(context).pop();
          HapticFeedback.lightImpact();
          _copyContent(context);
        },
      ),
      // 功能一：失败（error / stopped）助手消息显示「重试」（沿用失败重试语义）；
      // 已完成的助手消息显示「重新生成」。
      if (isFailed && onRetry != null)
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('重试'),
          onTap: () {
            Navigator.of(context).pop();
            onRetry!();
          },
        )
      else if (onRegenerate != null)
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('重新生成'),
          onTap: () {
            Navigator.of(context).pop();
            onRegenerate!();
          },
        ),
      // 功能一：消息变体动作分组（仅已完成助手消息注入 onVariantReply）。
      if (onVariantReply != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            '变体回复',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notes),
          title: const Text('更详尽地回答'),
          onTap: () {
            Navigator.of(context).pop();
            onVariantReply!('请基于上一问给出更详尽、更完整的回答');
          },
        ),
        ListTile(
          leading: const Icon(Icons.compress),
          title: const Text('更简洁地回答'),
          onTap: () {
            Navigator.of(context).pop();
            onVariantReply!('请用更简洁的方式重新回答，避免冗长');
          },
        ),
        ListTile(
          leading: const Icon(Icons.face_retouching_natural),
          title: const Text('更个性化的回答'),
          onTap: () {
            Navigator.of(context).pop();
            onVariantReply!('请用更有个性、更有个人风格与温度的方式重新回答');
          },
        ),
      ],
      if (onSaveToMemory != null)
        ListTile(
          leading: const Icon(Icons.bookmark_add_outlined),
          title: const Text('保存到记忆库'),
          onTap: () {
            Navigator.of(context).pop();
            onSaveToMemory!();
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
          Share.share(content, subject: 'Talkroom 消息');
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
      ..showSnackBar(
          const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)));
  }

  /// Markdown 样式：将全部文本元素前景色统一为气泡前景语义色
  /// （onPrimaryContainer / onSurface / onErrorContainer），确保暗色模式 /
  /// Monet 动态取色下浅色文字不再叠浅蓝容器背景，标题、引用、行内代码、
  /// 表格等子元素与正文保持同一前景色，对比度始终达标。
  static MarkdownStyleSheet _markdownStyle(ThemeData theme, Color fgColor) {
    final base = MarkdownStyleSheet.fromTheme(theme);
    TextStyle? withFg(TextStyle? s) => s?.copyWith(color: fgColor);
    return base.copyWith(
      p: withFg(base.p),
      h1: withFg(base.h1),
      h2: withFg(base.h2),
      h3: withFg(base.h3),
      h4: withFg(base.h4),
      h5: withFg(base.h5),
      h6: withFg(base.h6),
      em: withFg(base.em),
      strong: withFg(base.strong),
      del: withFg(base.del),
      blockquote: withFg(base.blockquote),
      code: withFg(base.code),
      listBullet: withFg(base.listBullet),
      tableHead: withFg(base.tableHead),
      tableBody: withFg(base.tableBody),
      a: withFg(base.a)?.copyWith(decoration: TextDecoration.underline),
    );
  }
}

/// 消息操作工具栏（R11）：气泡下方图标栏 —— 复制 / 点赞 / 不喜欢 / 分享 /
/// 更多（三点）。「更多」展开二级底部菜单，承载重试、变体、保存记忆、
/// 重新生成、编辑、删除、引用等动作；长按气泡菜单保留作为辅助入口。
/// 点赞 / 不喜欢为会话内即时反馈（互斥切换，不持久化）。
class _MessageActionBar extends StatefulWidget {
  const _MessageActionBar({
    required this.isUser,
    required this.content,
    this.status,
    this.onRetry,
    this.onRegenerate,
    this.onVariantReply,
    this.onSaveToMemory,
    this.onEdit,
    this.onDelete,
    this.onQuote,
    this.onCopy,
  });

  final bool isUser;
  final String content;
  final String? status;
  final VoidCallback? onRetry;
  final VoidCallback? onRegenerate;
  final void Function(String instruction)? onVariantReply;
  final VoidCallback? onSaveToMemory;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onQuote;
  final VoidCallback? onCopy;

  @override
  State<_MessageActionBar> createState() => _MessageActionBarState();
}

class _MessageActionBarState extends State<_MessageActionBar> {
  /// 点赞 / 不喜欢反馈状态：none / like / dislike（互斥）。
  String _reaction = 'none';

  void _toggleLike() {
    HapticFeedback.mediumImpact();
    setState(() => _reaction = _reaction == 'like' ? 'none' : 'like');
    _toast(_reaction == 'like' ? '已点赞' : '已取消点赞');
  }

  void _toggleDislike() {
    HapticFeedback.mediumImpact();
    setState(() => _reaction = _reaction == 'dislike' ? 'none' : 'dislike');
    _toast(_reaction == 'dislike' ? '已不喜欢' : '已取消不喜欢');
  }

  void _copy() {
    HapticFeedback.lightImpact();
    widget.onCopy?.call();
  }

  Future<void> _share() async {
    HapticFeedback.lightImpact();
    await Share.share(
      widget.content,
      subject: 'Talkroom 消息',
    );
  }

  void _showMoreMenu() {
    HapticFeedback.selectionClick();
    final theme = Theme.of(context);
    final isFailed = widget.status == 'error' || widget.status == 'stopped';
    final w = widget;
    // P2-04：error/stopped 终态仅保留「重试」与「删除」，隐藏变体 /
    // 保存记忆 / 编辑 / 引用 / 重新生成等常规操作，避免对失败内容误操作。
    final items = <Widget>[
      if (isFailed && w.onRetry != null)
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('重试'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.mediumImpact();
            w.onRetry!();
          },
        )
      else if (!isFailed && w.onRegenerate != null)
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('重新生成'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.mediumImpact();
            w.onRegenerate!();
          },
        ),
      if (!isFailed && w.onVariantReply != null) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Text(
            '变体回复',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notes),
          title: const Text('更详尽地回答'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.mediumImpact();
            w.onVariantReply!('请基于上一问给出更详尽、更完整的回答');
          },
        ),
        ListTile(
          leading: const Icon(Icons.compress),
          title: const Text('更简洁地回答'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.mediumImpact();
            w.onVariantReply!('请用更简洁的方式重新回答，避免冗长');
          },
        ),
        ListTile(
          leading: const Icon(Icons.face_retouching_natural),
          title: const Text('更个性化的回答'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.mediumImpact();
            w.onVariantReply!('请用更有个性、更有个人风格与温度的方式重新回答');
          },
        ),
      ],
      if (!isFailed && w.onSaveToMemory != null)
        ListTile(
          leading: const Icon(Icons.bookmark_add_outlined),
          title: const Text('保存到记忆库'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.mediumImpact();
            w.onSaveToMemory!();
          },
        ),
      if (!isFailed && w.onEdit != null)
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('编辑'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.mediumImpact();
            w.onEdit!();
          },
        ),
      if (w.onDelete != null)
        ListTile(
          leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
          title: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.heavyImpact();
            w.onDelete!();
          },
        ),
      if (!isFailed && w.onQuote != null)
        ListTile(
          leading: const Icon(Icons.format_quote),
          title: const Text('引用'),
          onTap: () {
            Navigator.of(context).pop();
            HapticFeedback.lightImpact();
            w.onQuote!();
          },
        ),
    ];
    if (items.isEmpty) return;

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
                '更多操作',
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

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 1),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurfaceVariant;
    final liked = _reaction == 'like';
    final disliked = _reaction == 'dislike';
    final status = widget.status;
    // P2-04：工具栏按消息状态显隐 ——
    // - streaming：内容未完成，隐藏复制/点赞/分享等全部图标（气泡内已有
    //   「生成中…」指示，避免复制到半截内容）；
    // - error/stopped：终态失败，仅保留「更多」入口（其内只含重试/删除），
    //   不展示复制/点赞/分享等常规操作；
    // - 其他（done / 用户消息）：完整展示。
    final isStreaming = status == 'streaming';
    final isFailed = status == 'error' || status == 'stopped';
    if (isStreaming) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(
        left: widget.isUser ? 0 : 24,
        right: widget.isUser ? 24 : 0,
        top: 2,
        bottom: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isFailed) ...[
            _toolbarIcon(
              icon: Icons.copy_outlined,
              tooltip: '复制',
              color: iconColor,
              onPressed: _copy,
            ),
            _toolbarIcon(
              icon: liked ? Icons.thumb_up : Icons.thumb_up_outlined,
              tooltip: '点赞',
              color: liked ? theme.colorScheme.primary : iconColor,
              onPressed: _toggleLike,
            ),
            _toolbarIcon(
              icon: disliked ? Icons.thumb_down : Icons.thumb_down_outlined,
              tooltip: '不喜欢',
              color: disliked ? theme.colorScheme.error : iconColor,
              onPressed: _toggleDislike,
            ),
            _toolbarIcon(
              icon: Icons.share_outlined,
              tooltip: '分享',
              color: iconColor,
              onPressed: _share,
            ),
          ],
          _toolbarIcon(
            icon: Icons.more_horiz,
            tooltip: '更多操作',
            color: iconColor,
            onPressed: _showMoreMenu,
          ),
        ],
      ),
    );
  }

  Widget _toolbarIcon({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 18),
      color: color,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }
}

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
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
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

  /// v1.2.19：base64 解码结果静态 LRU 缓存 —— 列表滚动/重建时同一附件
  /// 复用已解码字节（Uint8List 实例相同，Flutter ImageCache 可命中），
  /// 避免滑动过程中反复执行 CPU 密集的 base64Decode 与图片解码。
  static final Map<String, Uint8List> _decodedBase64 = {};
  static const int _decodeCacheLimit = 16;

  static Uint8List _decodeCached(String data) {
    final cached = _decodedBase64[data];
    if (cached != null) return cached;
    final bytes = base64Decode(data);
    if (_decodedBase64.length >= _decodeCacheLimit) {
      // 简单 FIFO 淘汰，足够覆盖最近滑过的附件图。
      _decodedBase64.remove(_decodedBase64.keys.first);
    }
    _decodedBase64[data] = bytes;
    return bytes;
  }

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
              _decodeCached(data),
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
    // 表格文字跟随气泡前景语义色（DefaultTextStyle 已注入），避免暗色下
    // 浅色文字叠浅蓝容器背景对比度不足。
    final fgColor =
        DefaultTextStyle.of(context).style.color ?? theme.colorScheme.onSurface;

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: c < rows[r].length
                        ? Text(
                            rows[r][c].textContent.trim(),
                            style: rows[r][c].tag == 'th'
                                ? (preferredStyle ?? theme.textTheme.bodyMedium)
                                    ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: fgColor)
                                : (preferredStyle ?? theme.textTheme.bodyMedium)
                                    ?.copyWith(color: fgColor),
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
/// P2-03：链接颜色跟随气泡前景色（fgColor），不再硬编码主题 primary，
/// 保证深浅色与用户/助手气泡下对比度一致。
class _LinkBuilder extends MarkdownElementBuilder {
  _LinkBuilder(this.fgColor);

  final Color fgColor;

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
    // P2-03：链接颜色跟随气泡前景色，深浅色/用户气泡下均可读；
    // 下划线仍保留以维持「可点击」语义。
    final linkStyle =
        (preferredStyle ?? parentStyle ?? theme.textTheme.bodyMedium)?.copyWith(
      color: fgColor,
      decoration: TextDecoration.underline,
      decorationColor: fgColor,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
    final theme = Theme.of(context);
    final fgColor =
        DefaultTextStyle.of(context).style.color ?? theme.colorScheme.onSurface;
    return Padding(
      padding:
          inline ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 4),
      child: Math.tex(
        tex,
        mathStyle: inline ? MathStyle.text : MathStyle.display,
        textStyle: TextStyle(
          fontSize: inline ? 14 : 16,
          color: fgColor,
        ),
      ),
    );
  }
}
