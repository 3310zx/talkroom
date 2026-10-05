import 'message.dart';

/// 跨会话消息搜索命中项（R12，v1.0.15）。
///
/// 由 `MessageRepository.searchMessages` 返回：命中消息 + 所属会话信息，
/// 供全局搜索页展示摘要并跳转到对应会话定位。
class MessageSearchHit {
  final ChatMessage message;
  final int conversationId;
  final String conversationTitle;

  const MessageSearchHit({
    required this.message,
    required this.conversationId,
    required this.conversationTitle,
  });
}
