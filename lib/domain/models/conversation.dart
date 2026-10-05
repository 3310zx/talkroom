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

  /// 是否已归档（v1.0.13 / DB version 5 起；归档会话移入归档列表，可从归档恢复）
  final bool archived;

  /// 会话默认 System Prompt 模板 id（v1.0.13 / DB version 5 起；null 表示跟随全局设置）
  final int? promptTemplateId;

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
    this.archived = false,
    this.promptTemplateId,
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
    bool? archived,
    int? promptTemplateId,
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
      archived: archived ?? this.archived,
      promptTemplateId: promptTemplateId ?? this.promptTemplateId,
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
      'archived': archived ? 1 : 0,
      'prompt_template_id': promptTemplateId,
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
      archived: (map['archived'] as int? ?? 0) == 1,
      promptTemplateId: map['prompt_template_id'] as int?,
      lastMessage: map['last_message'] as String? ?? '',
      updatedAt: map['updated_at'] as int? ?? 0,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }
}
