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

  /// 频率惩罚（R14，v1.0.15 / DB version 7 起；NULL 表示跟随全局默认）
  final double? frequencyPenalty;

  /// 存在惩罚（R14，v1.0.15 / DB version 7 起；NULL 表示跟随全局默认）
  final double? presencePenalty;
  final bool pinned;

  /// 是否已归档（v1.0.13 / DB version 5 起；归档会话移入归档列表，可从归档恢复）
  final bool archived;

  /// 会话默认 System Prompt 模板 id（v1.0.13 / DB version 5 起；null 表示跟随全局设置）
  final int? promptTemplateId;

  /// 历史对话摘要（DB version 13 起；压缩上下文后写入，null / 空串表示尚未压缩）。
  final String? contextSummary;

  /// 摘要已覆盖到的消息 id（id <= 该值的消息不再参与请求组装）。
  final int? contextSummaryUptoId;

  /// 摘要最后更新时间（毫秒时间戳）。
  final int? contextSummaryUpdatedAt;

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
    this.frequencyPenalty,
    this.presencePenalty,
    this.pinned = false,
    this.archived = false,
    this.promptTemplateId,
    this.contextSummary,
    this.contextSummaryUptoId,
    this.contextSummaryUpdatedAt,
    this.lastMessage = '',
    required this.updatedAt,
    required this.createdAt,
  });

  /// [clearContextSummary] 为 true 时把三个摘要字段全部置空
  /// （普通 copyWith 无法用 null 覆盖已有值）。
  Conversation copyWith({
    int? id,
    String? title,
    int? apiConfigId,
    String? modelId,
    String? systemPrompt,
    double? temperature,
    int? maxTokens,
    double? topP,
    double? frequencyPenalty,
    double? presencePenalty,
    bool? pinned,
    bool? archived,
    int? promptTemplateId,
    String? contextSummary,
    int? contextSummaryUptoId,
    int? contextSummaryUpdatedAt,
    bool clearContextSummary = false,
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
      frequencyPenalty: frequencyPenalty ?? this.frequencyPenalty,
      presencePenalty: presencePenalty ?? this.presencePenalty,
      pinned: pinned ?? this.pinned,
      archived: archived ?? this.archived,
      promptTemplateId: promptTemplateId ?? this.promptTemplateId,
      contextSummary:
          clearContextSummary ? null : (contextSummary ?? this.contextSummary),
      contextSummaryUptoId: clearContextSummary
          ? null
          : (contextSummaryUptoId ?? this.contextSummaryUptoId),
      contextSummaryUpdatedAt: clearContextSummary
          ? null
          : (contextSummaryUpdatedAt ?? this.contextSummaryUpdatedAt),
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
      'frequency_penalty': frequencyPenalty,
      'presence_penalty': presencePenalty,
      'pinned': pinned ? 1 : 0,
      'archived': archived ? 1 : 0,
      'prompt_template_id': promptTemplateId,
      'context_summary': contextSummary,
      'context_summary_upto_id': contextSummaryUptoId,
      'context_summary_updated_at': contextSummaryUpdatedAt,
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
      frequencyPenalty: (map['frequency_penalty'] as num?)?.toDouble(),
      presencePenalty: (map['presence_penalty'] as num?)?.toDouble(),
      pinned: (map['pinned'] as int? ?? 0) == 1,
      archived: (map['archived'] as int? ?? 0) == 1,
      promptTemplateId: map['prompt_template_id'] as int?,
      contextSummary: map['context_summary'] as String?,
      contextSummaryUptoId: map['context_summary_upto_id'] as int?,
      contextSummaryUpdatedAt: map['context_summary_updated_at'] as int?,
      lastMessage: map['last_message'] as String? ?? '',
      updatedAt: map['updated_at'] as int? ?? 0,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }

  /// 清空会话级参数覆盖（R14：恢复为跟随全局默认设置）。
  Conversation clearedParamOverrides() {
    return Conversation(
      id: id,
      title: title,
      apiConfigId: apiConfigId,
      modelId: modelId,
      systemPrompt: null,
      temperature: null,
      maxTokens: null,
      topP: null,
      frequencyPenalty: null,
      presencePenalty: null,
      pinned: pinned,
      archived: archived,
      promptTemplateId: promptTemplateId,
      contextSummary: contextSummary,
      contextSummaryUptoId: contextSummaryUptoId,
      contextSummaryUpdatedAt: contextSummaryUpdatedAt,
      lastMessage: lastMessage,
      updatedAt: updatedAt,
      createdAt: createdAt,
    );
  }
}
