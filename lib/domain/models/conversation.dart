/// 会话实体（对应 PRD 6.1.2 `conversations` 表）。
class Conversation {
  final int? id;
  final String title;
  final int? apiConfigId;
  final String? modelId;
  final String? systemPrompt;
  final double? temperature;
  final int? maxTokens;
  final double? topP;
  final bool pinned;
  final String lastMessage;
  final int updatedAt;
  final int createdAt;

  const Conversation({
    this.id,
    this.title = '新会话',
    this.apiConfigId,
    this.modelId,
    this.systemPrompt,
    this.temperature,
    this.maxTokens,
    this.topP,
    this.pinned = false,
    this.lastMessage = '',
    required this.updatedAt,
    required this.createdAt,
  });

  Conversation copyWith({
    int? id,
    String? title,
    int? apiConfigId,
    String? modelId,
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
    double? topP,
    bool? pinned,
    String? lastMessage,
    int? updatedAt,
    int? createdAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      apiConfigId: apiConfigId ?? this.apiConfigId,
      modelId: modelId ?? this.modelId,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      pinned: pinned ?? this.pinned,
      lastMessage: lastMessage ?? this.lastMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'api_config_id': apiConfigId,
      'model_id': modelId,
      'system_prompt': systemPrompt,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'top_p': topP,
      'pinned': pinned ? 1 : 0,
      'last_message': lastMessage,
      'updated_at': updatedAt,
      'created_at': createdAt,
    };
  }

  factory Conversation.fromMap(Map<String, Object?> map) {
    return Conversation(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '新会话',
      apiConfigId: map['api_config_id'] as int?,
      modelId: map['model_id'] as String?,
      systemPrompt: map['system_prompt'] as String?,
      temperature: (map['temperature'] as num?)?.toDouble(),
      maxTokens: map['max_tokens'] as int?,
      topP: (map['top_p'] as num?)?.toDouble(),
      pinned: (map['pinned'] as int? ?? 0) == 1,
      lastMessage: map['last_message'] as String? ?? '',
      updatedAt: map['updated_at'] as int? ?? 0,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }
}
