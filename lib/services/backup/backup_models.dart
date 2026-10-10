library;

import '../../domain/models/message.dart';

/// 备份 / 导入数据模型（v1.2.14「数据备份」）。
///
/// 备份文件为单 JSON（.talkroom-backup.json），结构见 [BackupData]；
/// Chatbox 备份解析产物为 [ChatboxZip]，经 [BackupService.mapChatboxToBackup]
/// 归一化为 [BackupData] 后走同一套事务导入流程。
///
/// 安全约束：
/// - 导出不落 API Key 真身（仅保留 [BackupApiConfig.apiKeyRef] 引用键），
///   导入时生成新引用键，报告提示手动重填；
/// - 导出剔除同步凭据（sync_device_token / server_pair_code 等，见
///   [BackupService.kExcludedSettingKeyPrefixes]）。

/// 备份文件 schema 版本（当前唯一受支持版本）。
const int kBackupSchemaVersion = 1;

/// 备份文件后缀。
const String kBackupFileSuffix = '.talkroom-backup.json';

/// 统一备份数据（导出产物 / 自身导入输入 / Chatbox 归一化产物）。
class BackupData {
  final int schemaVersion;
  final String appVersion;
  final int exportedAt;
  final Map<String, String> settings;
  final List<BackupApiConfig> apiConfigs;
  final List<BackupPromptTemplate> promptTemplates;
  final List<BackupConversation> conversations;
  final List<BackupActiveTask> activeTasks;

  const BackupData({
    this.schemaVersion = kBackupSchemaVersion,
    this.appVersion = '',
    this.exportedAt = 0,
    this.settings = const {},
    this.apiConfigs = const [],
    this.promptTemplates = const [],
    this.conversations = const [],
    this.activeTasks = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'app_version': appVersion,
      'exported_at': exportedAt,
      'source_type': 'talkroom',
      'data': {
        'settings': settings,
        'api_configs': apiConfigs.map((e) => e.toJson()).toList(),
        'prompt_templates': promptTemplates.map((e) => e.toJson()).toList(),
        'conversations': conversations.map((e) => e.toJson()).toList(),
        'active_tasks': activeTasks.map((e) => e.toJson()).toList(),
      },
    };
  }

  /// 从备份 JSON 解析；结构非法时抛出 [FormatException]。
  factory BackupData.fromJson(Map<String, dynamic> root) {
    final schemaVersion = root['schema_version'] as int? ?? 0;
    if (schemaVersion != kBackupSchemaVersion) {
      throw FormatException('不支持的备份 schema 版本：$schemaVersion（当前支持 $kBackupSchemaVersion）');
    }
    final data = root['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('备份文件缺少 data 数据区');
    }
    return BackupData(
      schemaVersion: schemaVersion,
      appVersion: root['app_version'] as String? ?? '',
      exportedAt: root['exported_at'] as int? ?? 0,
      settings: (data['settings'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const {},
      apiConfigs: (data['api_configs'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BackupApiConfig.fromJson)
          .toList(),
      promptTemplates: (data['prompt_templates'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BackupPromptTemplate.fromJson)
          .toList(),
      conversations: (data['conversations'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BackupConversation.fromJson)
          .toList(),
      activeTasks: (data['active_tasks'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(BackupActiveTask.fromJson)
          .toList(),
    );
  }
}

/// API 配置备份项。`refId` 为导出时的数据库自增 id，仅用于导入时外键重映射。
class BackupApiConfig {
  final int? refId;
  final String name;
  final String baseUrl;
  final String apiKeyRef;
  final List<String> modelIds;
  final bool enabled;
  final int createdAt;
  final int updatedAt;

  const BackupApiConfig({
    this.refId,
    required this.name,
    required this.baseUrl,
    this.apiKeyRef = '',
    this.modelIds = const [],
    this.enabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'ref_id': refId,
        'name': name,
        'base_url': baseUrl,
        'api_key_ref': apiKeyRef,
        'model_ids': modelIds,
        'enabled': enabled ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory BackupApiConfig.fromJson(Map<String, dynamic> map) => BackupApiConfig(
        refId: map['ref_id'] as int?,
        name: map['name'] as String? ?? '',
        baseUrl: map['base_url'] as String? ?? '',
        apiKeyRef: map['api_key_ref'] as String? ?? '',
        modelIds: (map['model_ids'] as List?)
            ?.whereType<dynamic>()
            .map((e) => e.toString())
            .toList() ??
            const [],
        enabled: (map['enabled'] as int? ?? 1) == 1,
        createdAt: map['created_at'] as int? ?? 0,
        updatedAt: map['updated_at'] as int? ?? 0,
      );
}

/// System Prompt 模板备份项。
class BackupPromptTemplate {
  final int? refId;
  final String name;
  final String content;
  final bool builtin;
  final int createdAt;

  const BackupPromptTemplate({
    this.refId,
    required this.name,
    required this.content,
    this.builtin = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'ref_id': refId,
        'name': name,
        'content': content,
        'builtin': builtin ? 1 : 0,
        'created_at': createdAt,
      };

  factory BackupPromptTemplate.fromJson(Map<String, dynamic> map) =>
      BackupPromptTemplate(
        refId: map['ref_id'] as int?,
        name: map['name'] as String? ?? '',
        content: map['content'] as String? ?? '',
        builtin: (map['builtin'] as int? ?? 0) == 1,
        createdAt: map['created_at'] as int? ?? 0,
      );
}

/// 消息备份项。附件复用领域模型 [MessageAttachment]（含图片 base64）。
class BackupMessage {
  final String role;
  final String content;
  final String contentType;
  final String status;
  final String? modelId;
  final int? promptTokens;
  final int? completionTokens;
  final String? errorMessage;
  final int createdAt;
  final List<MessageAttachment> attachments;
  final String? reasoningContent;
  final int? reasoningDurationMs;
  final int? reasoningTokens;
  final int? cachedTokens;

  const BackupMessage({
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
  });

  Map<String, dynamic> toJson() => {
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
      };

  factory BackupMessage.fromJson(Map<String, dynamic> map) => BackupMessage(
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
      );
}

/// 会话备份项。`apiConfigRef` / `promptTemplateRef` 为导出时的外键原值，
/// 导入时按映射表重写为新 id；`refId` 仅用于 Chatbox/自身备份回环映射。
class BackupConversation {
  final int? refId;
  final String title;
  final int? apiConfigRef;
  final String? modelId;
  final String? systemPrompt;
  final double? temperature;
  final int? maxTokens;
  final double? topP;
  final double? frequencyPenalty;
  final double? presencePenalty;
  final bool pinned;
  final bool archived;
  final int? promptTemplateRef;
  final String? lastMessage;
  final int updatedAt;
  final int createdAt;
  final List<BackupMessage> messages;

  const BackupConversation({
    this.refId,
    required this.title,
    this.apiConfigRef,
    this.modelId,
    this.systemPrompt,
    this.temperature,
    this.maxTokens,
    this.topP,
    this.frequencyPenalty,
    this.presencePenalty,
    this.pinned = false,
    this.archived = false,
    this.promptTemplateRef,
    this.lastMessage,
    required this.updatedAt,
    required this.createdAt,
    this.messages = const [],
  });

  Map<String, dynamic> toJson() => {
        'ref_id': refId,
        'title': title,
        'api_config_ref': apiConfigRef,
        'model_id': modelId,
        'system_prompt': systemPrompt,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'top_p': topP,
        'frequency_penalty': frequencyPenalty,
        'presence_penalty': presencePenalty,
        'pinned': pinned ? 1 : 0,
        'archived': archived ? 1 : 0,
        'prompt_template_ref': promptTemplateRef,
        'last_message': lastMessage,
        'updated_at': updatedAt,
        'created_at': createdAt,
        'messages': messages.map((e) => e.toJson()).toList(),
      };

  factory BackupConversation.fromJson(Map<String, dynamic> map) =>
      BackupConversation(
        refId: map['ref_id'] as int?,
        title: map['title'] as String? ?? '新会话',
        apiConfigRef: map['api_config_ref'] as int?,
        modelId: map['model_id'] as String?,
        systemPrompt: map['system_prompt'] as String?,
        temperature: (map['temperature'] as num?)?.toDouble(),
        maxTokens: map['max_tokens'] as int?,
        topP: (map['top_p'] as num?)?.toDouble(),
        frequencyPenalty: (map['frequency_penalty'] as num?)?.toDouble(),
        presencePenalty: (map['presence_penalty'] as num?)?.toDouble(),
        pinned: (map['pinned'] as int? ?? 0) == 1,
        archived: (map['archived'] as int? ?? 0) == 1,
        promptTemplateRef: map['prompt_template_ref'] as int?,
        lastMessage: map['last_message'] as String?,
        updatedAt: map['updated_at'] as int? ?? 0,
        createdAt: map['created_at'] as int? ?? 0,
        messages: (map['messages'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(BackupMessage.fromJson)
            .toList(),
      );
}

/// 主动消息任务备份项。
class BackupActiveTask {
  final int? refId;
  final String taskName;
  final String taskType;
  final String scheduleData;
  final String prompt;
  final int? apiConfigRef;
  final String modelId;
  final int? targetConversationRef;
  final String delivery;
  final String? quietStart;
  final String? quietEnd;
  final bool enabled;
  final int? nextRunAt;
  final int? lastRunAt;
  final String? lastStatus;
  final int createdAt;

  const BackupActiveTask({
    this.refId,
    required this.taskName,
    required this.taskType,
    required this.scheduleData,
    required this.prompt,
    this.apiConfigRef,
    required this.modelId,
    this.targetConversationRef,
    this.delivery = 'both',
    this.quietStart,
    this.quietEnd,
    this.enabled = true,
    this.nextRunAt,
    this.lastRunAt,
    this.lastStatus,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'ref_id': refId,
        'task_name': taskName,
        'task_type': taskType,
        'schedule_data': scheduleData,
        'prompt': prompt,
        'api_config_ref': apiConfigRef,
        'model_id': modelId,
        'target_conversation_ref': targetConversationRef,
        'delivery': delivery,
        'quiet_start': quietStart,
        'quiet_end': quietEnd,
        'enabled': enabled ? 1 : 0,
        'next_run_at': nextRunAt,
        'last_run_at': lastRunAt,
        'last_status': lastStatus,
        'created_at': createdAt,
      };

  factory BackupActiveTask.fromJson(Map<String, dynamic> map) =>
      BackupActiveTask(
        refId: map['ref_id'] as int?,
        taskName: map['task_name'] as String? ?? '',
        taskType: map['task_type'] as String? ?? 'interval',
        scheduleData: map['schedule_data'] as String? ?? '{}',
        prompt: map['prompt'] as String? ?? '',
        apiConfigRef: map['api_config_ref'] as int?,
        modelId: map['model_id'] as String? ?? '',
        targetConversationRef: map['target_conversation_ref'] as int?,
        delivery: map['delivery'] as String? ?? 'both',
        quietStart: map['quiet_start'] as String?,
        quietEnd: map['quiet_end'] as String?,
        enabled: (map['enabled'] as int? ?? 1) == 1,
        nextRunAt: map['next_run_at'] as int?,
        lastRunAt: map['last_run_at'] as int?,
        lastStatus: map['last_status'] as String?,
        createdAt: map['created_at'] as int? ?? 0,
      );
}

/// Chatbox 备份解析产物（zip 目录式结构，非本应用备份）。
///
/// 真实结构（2026-10 实测）：
/// - settings.json：全局设置（providers 含 apiKey 真身，解析时不外露）；
/// - session-settings.json：默认模型、agent-soul、agent-memories；
/// - copilots.json：自定义角色；
/// - sessions/<uuid>/session.json：会话（name/messages/settings）。
class ChatboxZip {
  /// 会话列表（已按解析顺序稳定输出）。
  final List<ChatboxSession> sessions;

  /// 备份中出现的 provider 名集合（如 siliconflow / deepseek / gemini）。
  final Set<String> providers;

  /// 备份中出现的模型 id 集合（含 provider 前缀，如 Pro/deepseek-ai/DeepSeek-V3.1）。
  final Set<String> modelIds;

  const ChatboxZip({
    required this.sessions,
    required this.providers,
    required this.modelIds,
  });

  /// 全部会话的消息总数。
  int get messagesCount =>
      sessions.fold<int>(0, (sum, s) => sum + s.messages.length);
}

/// Chatbox 会话（session.json）。
class ChatboxSession {
  final String id; // uuid
  final String title; // name / threadName
  final String? provider; // settings.provider
  final String? modelId; // settings.modelId
  final double? temperature; // settings.temperature
  final int? maxContextMessageCount;
  final List<ChatboxMessage> messages;
  final bool archived; // archivedAt 存在即视为已归档

  const ChatboxSession({
    required this.id,
    required this.title,
    this.provider,
    this.modelId,
    this.temperature,
    this.maxContextMessageCount,
    required this.messages,
    this.archived = false,
  });

  int? get createdMs {
    if (messages.isEmpty) return null;
    var min = messages.first.timestampMs;
    for (final m in messages) {
      if (m.timestampMs < min) min = m.timestampMs;
    }
    return min;
  }

  int? get updatedMs {
    if (messages.isEmpty) return null;
    var max = messages.first.timestampMs;
    for (final m in messages) {
      if (m.timestampMs > max) max = m.timestampMs;
    }
    return max;
  }
}

/// Chatbox 消息（contentParts 已合并：text→content、reasoning→思维链）。
class ChatboxMessage {
  final String role; // system | user | assistant
  final String content;
  final String? reasoningContent;
  final int timestampMs;
  final List<ChatboxFileRef> files;

  const ChatboxMessage({
    required this.role,
    required this.content,
    this.reasoningContent,
    required this.timestampMs,
    this.files = const [],
  });
}

/// Chatbox 附件引用（仅元信息，备份不含二进制，storageKey 指向其本地存储）。
class ChatboxFileRef {
  final String id;
  final String name;
  final String? fileType;
  final int? byteLength;

  const ChatboxFileRef({
    required this.id,
    required this.name,
    this.fileType,
    this.byteLength,
  });
}

/// 导入结果报告（导入完成后 UI 展示 + 测试断言用）。
class ImportReport {
  final bool isChatbox;
  int settingsImported = 0;
  int apiConfigsImported = 0;
  int apiConfigsSkipped = 0;
  int promptTemplatesImported = 0;
  int promptTemplatesSkipped = 0;
  int conversationsImported = 0;
  int conversationsSkipped = 0;
  int messagesImported = 0;
  int activeTasksImported = 0;
  int activeTasksSkipped = 0;
  int attachmentsSkipped = 0;
  final List<String> notes;

  ImportReport({this.isChatbox = false, List<String>? notes})
      : notes = notes ?? [];

  String summarize() {
    final buffer = StringBuffer();
    if (isChatbox) {
      buffer.write('Chatbox 备份导入完成：');
    } else {
      buffer.write('备份导入完成：');
    }
    buffer
      ..write('会话 $conversationsImported 个')
      ..write(conversationsSkipped > 0 ? '（跳过 $conversationsSkipped）' : '')
      ..write('，消息 $messagesImported 条')
      ..write('，模型配置 $apiConfigsImported 个')
      ..write('，Prompt 模板 $promptTemplatesImported 个')
      ..write('，全局设置 $settingsImported 项')
      ..write('，主动任务 $activeTasksImported 个');
    if (activeTasksSkipped > 0) {
      buffer.write('（跳过 $activeTasksSkipped）');
    }
    if (attachmentsSkipped > 0) {
      buffer.write('，附件因无二进制数据跳过 $attachmentsSkipped 个');
    }
    return buffer.toString();
  }
}
