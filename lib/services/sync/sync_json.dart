import '../../domain/models/message.dart';

/// 局域网同步消息的 JSON 序列化（PRD 第 7 章，服务端/客户端共用）。
///
/// 字段名与数据库列名一致（snake_case），时间一律毫秒时间戳。
Map<String, Object?> toSyncJson(ChatMessage m) {
  return {
    'conversation_id': m.conversationId,
    'role': m.role,
    'content': m.content,
    'content_type': m.contentType,
    'status': m.status,
    'model_id': m.modelId,
    'prompt_tokens': m.promptTokens,
    'completion_tokens': m.completionTokens,
    'error_message': m.errorMessage,
    'device_id': m.deviceId,
    'server_id': m.serverId,
    'created_at': m.createdAt,
    'updated_at': m.updatedAt,
  };
}

ChatMessage fromSyncJson(Map<String, Object?> map) {
  return ChatMessage(
    conversationId: map['conversation_id'] as int? ?? 0,
    role: map['role'] as String? ?? 'user',
    content: map['content'] as String? ?? '',
    contentType: map['content_type'] as String? ?? 'text',
    status: map['status'] as String? ?? 'done',
    modelId: map['model_id'] as String?,
    promptTokens: map['prompt_tokens'] as int?,
    completionTokens: map['completion_tokens'] as int?,
    errorMessage: map['error_message'] as String?,
    deviceId: map['device_id'] as String?,
    serverId: map['server_id'] as int?,
    createdAt: map['created_at'] as int? ?? 0,
    updatedAt: map['updated_at'] as int?,
  );
}
