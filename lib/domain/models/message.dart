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

  // 思维链与缓存命中（version 4 起；旧数据为 null / 0，模型层归一化兼容）：
  final String? reasoningContent; // 思维链文本（与正文分离展示）
  final int? reasoningDurationMs; // 思考耗时（请求发出到首个正文 token）
  final int? reasoningTokens; // 思考消耗 token（usage 或估算）
  final int? cachedTokens; // 缓存命中 token（prompt_tokens_details.cached_tokens）

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
    this.reasoningContent,
    this.reasoningDurationMs,
    this.reasoningTokens,
    this.cachedTokens,
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
    String? reasoningContent,
    int? reasoningDurationMs,
    int? reasoningTokens,
    int? cachedTokens,
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
      reasoningContent: reasoningContent ?? this.reasoningContent,
      reasoningDurationMs: reasoningDurationMs ?? this.reasoningDurationMs,
      reasoningTokens: reasoningTokens ?? this.reasoningTokens,
      cachedTokens: cachedTokens ?? this.cachedTokens,
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
      'reasoning_content': reasoningContent,
      'reasoning_duration_ms': reasoningDurationMs,
      'reasoning_tokens': reasoningTokens,
      'cached_tokens': cachedTokens,
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
      reasoningContent: map['reasoning_content'] as String?,
      reasoningDurationMs: map['reasoning_duration_ms'] as int?,
      reasoningTokens: map['reasoning_tokens'] as int?,
      cachedTokens: map['cached_tokens'] as int?,
      deviceId: map['device_id'] as String?,
      serverId: map['server_id'] as int?,
      updatedAt: map['updated_at'] as int?,
    );
  }
}

/// 缓存命中记录（`cache_hits` 表，设置页「命中缓存」列表用）。
///
/// 独立于消息表保存，避免"清空命中记录"影响聊天历史；
/// 消息表仍保留 cached_tokens 字段用于气泡展示。
class CacheHitRecord {
  final int? id;
  final String? modelId;
  final int cachedTokens;
  final int? promptTokens;
  final int? completionTokens;
  final int createdAt;

  const CacheHitRecord({
    this.id,
    this.modelId,
    required this.cachedTokens,
    this.promptTokens,
    this.completionTokens,
    required this.createdAt,
  });

  /// 缓存命中率（0~1）；prompt_tokens 缺失时返回 null。
  double? get hitRate {
    final prompt = promptTokens;
    if (prompt == null || prompt <= 0) return null;
    return cachedTokens / prompt;
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'model_id': modelId,
      'cached_tokens': cachedTokens,
      'prompt_tokens': promptTokens,
      'completion_tokens': completionTokens,
      'created_at': createdAt,
    };
  }

  factory CacheHitRecord.fromMap(Map<String, Object?> map) {
    return CacheHitRecord(
      id: map['id'] as int?,
      modelId: map['model_id'] as String?,
      cachedTokens: map['cached_tokens'] as int? ?? 0,
      promptTokens: map['prompt_tokens'] as int?,
      completionTokens: map['completion_tokens'] as int?,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }
}
