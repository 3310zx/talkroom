import 'dart:async';

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

  /// v1.2.20：流式增量合并节流。SSE 片段到达频率远高于渲染帧率，
  /// 每次 append 都触发 state 复制 + 列表重建 + MarkdownBody 重解析是
  /// 卡顿主因。此处把片段累积到 pending，按 [_streamingThrottle] 周期
  /// 合并刷新一次（60ms，远低于人眼感知，渲染体验无感），将每 token
  /// 的重建降为约 16 帧/秒。
  static const Duration _streamingThrottle = Duration(milliseconds: 60);
  int? _streamingMessageId;
  String _pendingContent = '';
  String _pendingReasoning = '';
  Timer? _streamingTimer;

  /// 公开只读快照（H1：页面 dispose 后通过缓存的 Notifier 读取当前状态，
  /// 避免直接访问受保护的 state 成员）。
  List<ChatMessage> get snapshot => state;

  Future<void> loadForConversation(int conversationId) async {
    _cancelStreamingTimer();
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
  /// v1.2.20：片段累积后按节流周期合并刷新，避免每 token 全量重建。
  void appendStreamingFragment(int messageId, String fragment) {
    _streamingMessageId = messageId;
    _pendingContent += fragment;
    _scheduleFlush();
  }

  /// 追加流式思维链增量片段：reasoning_content 每到达一段即累积到
  /// reasoningContent（与正文分离），使生成过程中即可看到思维链卡片。
  void appendReasoningFragment(int messageId, String fragment) {
    _streamingMessageId = messageId;
    _pendingReasoning += fragment;
    _scheduleFlush();
  }

  /// 流式结束前同步刷新 pending（chat_page 在终态 update 前调用），
  /// 避免残余片段在 update 之后追加到已完成消息上。
  void flushStreaming() {
    _flushStreaming();
  }

  void _scheduleFlush() {
    _streamingTimer ??= Timer(_streamingThrottle, _flushStreaming);
  }

  void _flushStreaming() {
    _streamingTimer?.cancel();
    _streamingTimer = null;
    final id = _streamingMessageId;
    final contentDelta = _pendingContent;
    final reasoningDelta = _pendingReasoning;
    _pendingContent = '';
    _pendingReasoning = '';
    _streamingMessageId = null;
    if (id == null) return;
    if (contentDelta.isEmpty && reasoningDelta.isEmpty) return;
    state = [
      for (final m in state)
        if (m.id == id)
          m.copyWith(
            content: contentDelta.isEmpty
                ? m.content
                : m.content + contentDelta,
            reasoningContent: reasoningDelta.isEmpty
                ? m.reasoningContent
                : (m.reasoningContent ?? '') + reasoningDelta,
            status: 'streaming',
          )
        else
          m,
    ];
  }

  void _cancelStreamingTimer() {
    _streamingTimer?.cancel();
    _streamingTimer = null;
    _pendingContent = '';
    _pendingReasoning = '';
    _streamingMessageId = null;
  }

  /// 删除单条消息（R3 消息菜单「删除」）。
  Future<void> remove(ChatMessage message) async {
    final id = message.id;
    if (id == null) return;
    await _repository.delete(id);
    state = [for (final m in state) if (m.id != id) m];
  }

  /// 删除某条消息及其之后的所有消息（R3「编辑重发 / 重新生成」：
  /// 清理旧回复后再发起新请求）。
  Future<void> deleteFrom(int messageId) async {
    await _repository.deleteFrom(messageId);
    state = [for (final m in state) if (m.id == null || m.id! < messageId) m];
  }

  void clear() {
    _cancelStreamingTimer();
    state = const [];
  }
}
