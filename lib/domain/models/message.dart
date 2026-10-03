/// 消息实体（对应 PRD 6.1.2 `messages` 表）。
class ChatMessage {
  final int? id;
  final int conversationId;
  final String role; // 'user' | 'assistant' | 'system' | 'tool'
  final String content;
  final String contentType; // 'text' | 'image' | 'file'
  final String status; // 'sending'|'streaming'|'done'|'error'|'stopped'
  final String? modelId;
  final int? promptTokens;
  final int? completionTokens;
  final String? errorMessage;
  final int createdAt;

  // 局域网同步字段（PRD 第 7 章 7.4.2；未启用同步时为 null / 0，兼容单机旧数据）：
  final String? deviceId; // 产生该消息的设备 UUID
  final int? serverId; // 服务器权威自增序号（电脑端 SQLite 为权威源）
  final int? updatedAt; // 冲突裁决时间（毫秒）

  const ChatMessage({
    this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.contentType = 'text',
    this.status = 'done',
    this.modelId,
    this.promptTokens,
    this.completionTokens,
    this.errorMessage,
    required this.createdAt,
    this.deviceId,
    this.serverId,
    this.updatedAt,
  });

  ChatMessage copyWith({
    int? id,
    int? conversationId,
    String? role,
    String? content,
    String? contentType,
    String? status,
    String? modelId,
    int? promptTokens,
    int? completionTokens,
    String? errorMessage,
    int? createdAt,
    String? deviceId,
    int? serverId,
    int? updatedAt,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      contentType: contentType ?? this.contentType,
      status: status ?? this.status,
      modelId: modelId ?? this.modelId,
      promptTokens: promptTokens ?? this.promptTokens,
      completionTokens: completionTokens ?? this.completionTokens,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      deviceId: deviceId ?? this.deviceId,
      serverId: serverId ?? this.serverId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'role': role,
      'content': content,
      'content_type': contentType,
      'status': status,
      'model_id': modelId,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'error_message': errorMessage,
      'created_at': createdAt,
      'device_id': deviceId,
      'server_id': serverId,
      'updated_at': updatedAt,
    };
  }

  factory ChatMessage.fromMap(Map<String, Object?> map) {
    return ChatMessage(
      id: map['id'] as int?,
      conversationId: map['conversation_id'] as int? ?? 0,
      role: map['role'] as String? ?? '',
      content: map['content'] as String? ?? '',
      contentType: map['content_type'] as String? ?? 'text',
      status: map['status'] as String? ?? 'done',
      modelId: map['model_id'] as String?,
      promptTokens: map['prompt_tokens'] as int?,
      completionTokens: map['completion_tokens'] as int?,
      errorMessage: map['error_message'] as String?,
      createdAt: map['created_at'] as int? ?? 0,
      deviceId: map['device_id'] as String?,
      serverId: map['server_id'] as int?,
      updatedAt: map['updated_at'] as int?,
    );
  }
}
