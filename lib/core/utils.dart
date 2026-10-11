/// 公共工具函数（v1.2.6 收敛重复私有实现，行为与原各页面等价）
library;

import 'package:flutter/material.dart';

import '../domain/models/api_config.dart';
import '../domain/models/conversation.dart';

/// 相对时间格式化（原 chat_session_drawer / chat_detail_panel /
/// archive_conversations_page / session_list_page 中 _formatTime 的等价实现）：
/// 今天显示 HH:mm，同年显示 MM-dd，跨年显示 yyyy-MM-dd。
String formatTime(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return '${two(dt.hour)}:${two(dt.minute)}';
  }
  if (dt.year == now.year) return '${two(dt.month)}-${two(dt.day)}';
  return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
}

/// 轻量 SnackBar 提示（原各页面 _toast / _showSnack 的等价实现，
/// 统一先隐藏当前 SnackBar 再展示，行为与原 settings_page / chat_page 一致）。
void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// 会话标题/摘要清洗：去掉零宽与不可见控制字符、压缩连续空白（含换行/
/// 全角空格）为单空格、去除首尾空白。
///
/// v1.2.20 修复：存量会话 title / last_message 以换行或不可见字符开头时，
/// 渲染层直接展示原串会导致列表条目「标题空白、摘要只剩日期」——
/// Text 单行/两行约束下首行被换行符顶空。此处统一清洗后供展示与写回。
String cleanConversationText(String? text) {
  if (text == null || text.isEmpty) return '';
  return text
      // 零宽连接符/左右标记/词连接符/软连字符/BOM 等不可见字符。
      .replaceAll(RegExp(r'[\u200B-\u200F\uFEFF\u2060\u00AD]'), '')
      // 连续空白（含 \n / \r / \t / 全角空格）压缩为单个空格。
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// 会话标题展示：清洗后为空则兜底「未命名会话」。
String conversationDisplayTitle(String title) {
  final cleaned = cleanConversationText(title);
  return cleaned.isEmpty ? '未命名会话' : cleaned;
}

/// 会话摘要展示：清洗后为空则兜底「暂无消息」。
String conversationDisplaySummary(String lastMessage) {
  final cleaned = cleanConversationText(lastMessage);
  return cleaned.isEmpty ? '暂无消息' : cleaned;
}

/// 解析当前生效模型：会话自带 modelId 优先，其次服务商首个模型，兜底空串。
String resolveModel(ApiConfig? config, Conversation? conv) {
  if (conv != null && conv.modelId != null && conv.modelId!.isNotEmpty) {
    return conv.modelId!;
  }
  if (config != null && config.modelIds.isNotEmpty) {
    return config.modelIds.first;
  }
  return '';
}

/// 读取 int 类型设置项（缺失或非法时返回 fallback）。
int intSetting(Map<String, String> settings, String key, int fallback) {
  final v = settings[key];
  if (v == null) return fallback;
  return int.tryParse(v) ?? fallback;
}

/// 消息摘要：去代码块/行内代码/Markdown 符号，压缩空白，截断 40 字。
String summarize(String text) {
  var plain = text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'`[^`]*`'), ' ')
      .replaceAll(RegExp(r'[#>*_~\[\]()!|-]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (plain.length > 40) plain = plain.substring(0, 40);
  return plain;
}
