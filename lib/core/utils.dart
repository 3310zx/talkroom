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
