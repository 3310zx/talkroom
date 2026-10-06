import 'dart:convert';

/// 消息附件（PRD 2.4 / R9：图片与文件上传）。
///
/// - 图片（type == 'image'）：`dataBase64` 保存压缩后的图片 Base64 数据，
///   气泡缩略图与全屏预览直接解码渲染，发送时组装为 OpenAI 多模态
///   `image_url`（data URL）；
/// - 文件（type == 'file'）：`dataBase64` 为空，仅保存名称 / MIME / 大小 /
///   文本预览，发送时以文本形式携带文件名与预览（模型不支持时中文提示）。
class MessageAttachment {
  final String type; // 'image' | 'file'
  final String name;
  final String? mimeType;
  final int? sizeBytes;
  final String? dataBase64; // 图片：base64 数据（不含 data: 前缀）
  final String? textPreview; // 文件：文本类内容预览（前 N 字符）
  final String? url; // 可选来源 URL（后续扩展）

  // v1.2.1 文件解析器：发送前解析本地文档提取文本，节省 token。
  final String? parsedText; // 解析出的文本（已按上限截断）
  final int? parsedCharCount; // 解析的完整字符数（截断前）
  final String parseStatus; // 'none' | 'parsing' | 'done' | 'failed' | 'skipped'

  const MessageAttachment({
    required this.type,
    required this.name,
    this.mimeType,
    this.sizeBytes,
    this.dataBase64,
    this.textPreview,
    this.url,
    this.parsedText,
    this.parsedCharCount,
    this.parseStatus = 'none',
  });

  bool get isImage => type == 'image';

  /// 解析成功且含文本（供多模态预检放行/发送文本块判断）。
  bool get hasParsedText =>
      parseStatus == 'done' && (parsedText?.isNotEmpty ?? false);

  /// 解析状态中文标签（附件卡/气泡文件卡展示）。
  String get parseStatusLabel {
    switch (parseStatus) {
      case 'parsing':
        return '解析中';
      case 'done':
        return '已解析';
      case 'failed':
        return '解析失败';
      case 'skipped':
        return '跳过解析';
      default:
        return '';
    }
  }

  /// OpenAI 兼容 image_url data URL（如 `data:image/jpeg;base64,...`）。
  String? get imageDataUrl {
    final data = dataBase64;
    if (data == null || data.isEmpty) return null;
    return 'data:${mimeType ?? 'image/jpeg'};base64,$data';
  }

  MessageAttachment copyWith({
    String? type,
    String? name,
    String? mimeType,
    int? sizeBytes,
    String? dataBase64,
    String? textPreview,
    String? url,
    String? parsedText,
    int? parsedCharCount,
    String? parseStatus,
  }) {
    return MessageAttachment(
      type: type ?? this.type,
      name: name ?? this.name,
      mimeType: mimeType ?? this.mimeType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      dataBase64: dataBase64 ?? this.dataBase64,
      textPreview: textPreview ?? this.textPreview,
      url: url ?? this.url,
      parsedText: parsedText ?? this.parsedText,
      parsedCharCount: parsedCharCount ?? this.parsedCharCount,
      parseStatus: parseStatus ?? this.parseStatus,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'type': type,
      'name': name,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
      'data_base64': dataBase64,
      'text_preview': textPreview,
      'url': url,
      'parsed_text': parsedText,
      'parsed_char_count': parsedCharCount,
      'parse_status': parseStatus,
    };
  }

  factory MessageAttachment.fromMap(Map<String, Object?> map) {
    return MessageAttachment(
      type: map['type'] as String? ?? 'file',
      name: map['name'] as String? ?? '附件',
      mimeType: map['mime_type'] as String?,
      sizeBytes: map['size_bytes'] as int?,
      dataBase64: map['data_base64'] as String?,
      textPreview: map['text_preview'] as String?,
      url: map['url'] as String?,
      parsedText: map['parsed_text'] as String?,
      parsedCharCount: map['parsed_char_count'] as int?,
      parseStatus: map['parse_status'] as String? ?? 'none',
    );
  }

  /// JSON 序列化（存 messages.attachments TEXT 列）。
  static String? encodeList(List<MessageAttachment>? list) {
    if (list == null || list.isEmpty) return null;
    return jsonEncode(list.map((e) => e.toMap()).toList());
  }

  /// JSON 反序列化；null/空/损坏时安全返回空列表。
  static List<MessageAttachment> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MessageAttachment.fromMap)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

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

  // R9：附件列表（图片/文件；仅用户消息可携带，历史消息发送时回放）。
  final List<MessageAttachment> attachments;

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
    this.attachments = const [],
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
    List<MessageAttachment>? attachments,
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
      attachments: attachments ?? this.attachments,
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
      'attachments': MessageAttachment.encodeList(attachments),
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
      attachments: MessageAttachment.decodeList(map['attachments'] as String?),
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
