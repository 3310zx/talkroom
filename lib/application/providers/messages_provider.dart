import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/message.dart';
import '../../domain/repositories/message_repository.dart';
import 'database_provider.dart';

/// 消息列表状态（PRD 2.2：messagesProvider，按会话维度加载）。
final messagesProvider =
    StateNotifierProvider<MessagesNotifier, List<ChatMessage>>(
  (ref) => MessagesNotifier(ref.watch(appDatabaseProvider).messageRepository),
);

class MessagesNotifier extends StateNotifier<List<ChatMessage>> {
  MessagesNotifier(this._repository) : super(const []);

  final MessageRepository _repository;

  Future<void> loadForConversation(int conversationId) async {
    state = await _repository.listByConversation(conversationId);
  }

  /// 插入消息并返回落库后的真实 id（用于流式占位消息的后续更新）。
  Future<int> add(ChatMessage message) async {
    final id = await _repository.insert(message);
    state = [...state, message.copyWith(id: id)];
    return id;
  }

  Future<void> update(ChatMessage message) async {
    await _repository.update(message);
    state = [
      for (final m in state)
        if (m.id == message.id) message else m,
    ];
  }

  /// 追加流式增量片段（骨架预留；完整流式见 lib/services/llm_client.dart）
  void appendStreamingFragment(int messageId, String fragment) {
    state = [
      for (final m in state)
        if (m.id == messageId)
          m.copyWith(content: m.content + fragment, status: 'streaming')
        else
          m,
    ];
  }

  /// 追加流式思维链增量片段：reasoning_content 每到达一段即累积到
  /// reasoningContent（与正文分离），使生成过程中即可看到思维链卡片。
  void appendReasoningFragment(int messageId, String fragment) {
    state = [
      for (final m in state)
        if (m.id == messageId)
          m.copyWith(
            reasoningContent: (m.reasoningContent ?? '') + fragment,
            status: 'streaming',
          )
        else
          m,
    ];
  }

  void clear() {
    state = const [];
  }
}
