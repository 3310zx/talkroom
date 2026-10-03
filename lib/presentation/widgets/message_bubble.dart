import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// 消息气泡（微信风格：左侧 AI、右侧用户）。
///
/// - 用户消息：右侧纯文本气泡；
/// - 助手消息：左侧 Markdown 渲染气泡（`flutter_markdown` + `flutter_highlight`
///   代码块高亮，识别 language 标签，深/浅色主题自适应）；
/// - 错误态：`status == 'error'` 显示错误边框与中文错误摘要 + 重试按钮；
/// - 停止态：`status == 'stopped'` 保留已生成内容并标注「已停止生成」。
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.isUser,
    required this.content,
    this.status,
    this.errorMessage,
    this.onRetry,
  });

  final bool isUser;
  final String content;
  final String? status;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isError = status == 'error';
    final isStreaming = status == 'streaming';
    final isStopped = status == 'stopped';

    final bubbleColor = isError
        ? theme.colorScheme.errorContainer
        : isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
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
            if (isUser)
              Text(content, style: theme.textTheme.bodyLarge)
            else if (content.trim().isEmpty)
              Text(
                isStreaming ? '正在思考…' : '',
                style: theme.textTheme.bodyLarge,
              )
            else
              MarkdownBody(
                data: content,
                selectable: true,
                builders: {
                  'pre': _CodeBlockBuilder(),
                },
                styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
                  p: theme.textTheme.bodyLarge,
                ),
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
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '已停止生成',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
class _CodeBlockView extends StatelessWidget {
  const _CodeBlockView({required this.source, this.language});

  final String source;
  final String? language;

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
    final lang = language?.toLowerCase() ?? '';
    return _knownLanguages.contains(lang) ? lang : 'plaintext';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolved = _resolvedLanguage;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0x33777777) : const Color(0x33000000),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (resolved != 'plaintext')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              color: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFE8E8E8),
              child: Text(
                resolved,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(10),
            child: HighlightView(
              source,
              language: resolved,
              theme: isDark ? atomOneDarkTheme : atomOneLightTheme,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
