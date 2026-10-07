import 'package:flutter/material.dart';

import '../domain/models/conversation.dart';
import '../domain/models/message.dart';

/// Web 平台会话导出 stub：浏览器文件落盘/分享能力有限，验证版明确提示不支持。
class ConversationExporter {
  ConversationExporter._();

  static const List<String> kFormats = ['markdown', 'text', 'pdf'];

  static const int kMaxMessages = 3000;

  static const int kMaxTotalChars = 30 * 1024 * 1024;

  static const String kPdfFontAsset = 'assets/fonts/NotoSansSC-Regular.ttf';

  static Future<void> exportConversation(
    BuildContext context,
    Conversation conversation,
    List<ChatMessage> messages,
  ) async {
    throw UnsupportedError('Web 平台暂不支持会话导出');
  }

  static List<List<ChatMessage>> chunkMessages(List<ChatMessage> messages) =>
      throw UnsupportedError('Web 平台暂不支持会话导出');
}
