import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/constants.dart';
import '../../data/database/app_database.dart';
import '../../data/secure_storage/api_key_store.dart';
import '../../domain/models/api_config.dart';
import '../../domain/models/message.dart';
import '../../domain/repositories/active_task_repository.dart';
import '../../domain/repositories/api_config_repository.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/prompt_template_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import 'backup_models.dart';

/// 备份文件类型。
enum BackupFileType { talkroom, chatboxZip, unknown }

/// 备份 / 导入核心服务（v1.2.14「数据备份」）。
///
/// 职责：
/// - [buildBackupJson]：从仓储收集数据生成 .talkroom-backup.json（Map）；
/// - [parseBackupJson]：解析自身备份 JSON → [BackupData]；
/// - [importBackup]：事务性写入（失败回滚、外键重映射、去重）；
/// - [parseChatboxZip] / [mapChatboxToBackup]：Chatbox 备份 zip 解析与归一化。
///
/// 安全约束（与任务指令一致）：
/// - 导出不落 API Key 真身（仅引用键），导入后手动重填；
/// - 同步凭据（sync_device_token / server_pair_code 等）排除导出与导入。
abstract final class BackupService {
  /// 导出时从 settings 剔除的键前缀（同步凭据/配对状态，导入后重新配置）。
  static const List<String> kExcludedSettingKeyPrefixes = [
    'sync_',
    'server_pair_',
    'server_auto_',
    'server_last_',
  ];

  /// 是否应剔除该 settings 键（同步凭据/状态）。
  static bool isExcludedSettingKey(String key) {
    for (final prefix in kExcludedSettingKeyPrefixes) {
      if (key.startsWith(prefix)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------
  // 导出
  // ---------------------------------------------------------------

  /// 从仓储收集全部可备份数据并组装为备份 JSON Map。
  ///
  /// - settings 剔除 [kExcludedSettingKeyPrefixes] 前缀键；
  /// - api_configs 仅保留配置与引用键（api_key_ref），不含密钥；
  /// - conversations 内联 messages（含图片附件 base64）；
  /// - active_tasks 原样保存（含 api_config_id 引用，导入时重映射）。
  static Future<Map<String, dynamic>> buildBackupJson({
    required SettingsRepository settingsRepository,
    required ApiConfigRepository apiConfigRepository,
    required ConversationRepository conversationRepository,
    required MessageRepository messageRepository,
    required PromptTemplateRepository promptTemplateRepository,
    required ActiveTaskRepository activeTaskRepository,
    String appVersion = AppConstants.appVersion,
  }) async {
    final settings = await settingsRepository.getAll();
    final safeSettings = <String, String>{
      for (final e in settings.entries)
        if (!isExcludedSettingKey(e.key)) e.key: e.value,
    };

    final apiConfigs = await apiConfigRepository.getAll();
    final templates = await promptTemplateRepository.getAll();
    final conversations = await conversationRepository.getAll();
    final tasks = await activeTaskRepository.getAll();

    final backupConvos = <BackupConversation>[];
    for (final c in conversations) {
      final msgs = await messageRepository.listByConversation(c.id!);
      backupConvos.add(
        BackupConversation(
          refId: c.id,
          title: c.title,
          apiConfigRef: c.apiConfigId,
          modelId: c.modelId,
          systemPrompt: c.systemPrompt,
          temperature: c.temperature,
          maxTokens: c.maxTokens,
          topP: c.topP,
          frequencyPenalty: c.frequencyPenalty,
          presencePenalty: c.presencePenalty,
          pinned: c.pinned,
          archived: c.archived,
          promptTemplateRef: c.promptTemplateId,
          lastMessage: c.lastMessage,
          updatedAt: c.updatedAt,
          createdAt: c.createdAt,
          messages: msgs
              .map(
                (m) => BackupMessage(
                  role: m.role,
                  content: m.content,
                  contentType: m.contentType,
                  status: m.status,
                  modelId: m.modelId,
                  promptTokens: m.promptTokens,
                  completionTokens: m.completionTokens,
                  errorMessage: m.errorMessage,
                  createdAt: m.createdAt,
                  attachments: m.attachments,
                  reasoningContent: m.reasoningContent,
                  reasoningDurationMs: m.reasoningDurationMs,
                  reasoningTokens: m.reasoningTokens,
                  cachedTokens: m.cachedTokens,
                ),
              )
              .toList(),
        ),
      );
    }

    return BackupData(
      appVersion: appVersion,
      exportedAt: DateTime.now().millisecondsSinceEpoch,
      settings: safeSettings,
      apiConfigs: apiConfigs
          .map(
            (c) => BackupApiConfig(
              refId: c.id,
              name: c.name,
              baseUrl: c.baseUrl,
              apiKeyRef: c.apiKeyRef,
              modelIds: c.modelIds,
              enabled: c.enabled,
              createdAt: c.createdAt,
              updatedAt: c.updatedAt,
            ),
          )
          .toList(),
      promptTemplates: templates
          .map(
            (t) => BackupPromptTemplate(
              refId: t.id,
              name: t.name,
              content: t.content,
              builtin: t.builtin,
              createdAt: t.createdAt,
            ),
          )
          .toList(),
      conversations: backupConvos,
      activeTasks: tasks
          .map(
            (t) => BackupActiveTask(
              refId: t.id,
              taskName: t.taskName,
              taskType: t.taskType,
              scheduleData: t.scheduleData,
              prompt: t.prompt,
              apiConfigRef: t.apiConfigId,
              modelId: t.modelId,
              targetConversationRef: t.targetConversationId,
              delivery: t.delivery,
              quietStart: t.quietStart,
              quietEnd: t.quietEnd,
              enabled: t.enabled,
              nextRunAt: t.nextRunAt,
              lastRunAt: t.lastRunAt,
              lastStatus: t.lastStatus,
              createdAt: t.createdAt,
            ),
          )
          .toList(),
    ).toJson();
  }

  // ---------------------------------------------------------------
  // 解析
  // ---------------------------------------------------------------

  /// 解析自身备份 JSON；结构非法抛出 [FormatException]。
  static BackupData parseBackupJson(String jsonText) {
    final root = jsonDecode(jsonText);
    if (root is! Map<String, dynamic>) {
      throw const FormatException('备份文件不是有效的 JSON 对象');
    }
    return BackupData.fromJson(root);
  }

  /// 检测备份文件类型。
  static BackupFileType detectBackupType(List<int> bytes, {String? fileName}) {
    final lower = fileName?.toLowerCase() ?? '';
    if (lower.endsWith(kBackupFileSuffix)) return BackupFileType.talkroom;
    if (bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      // ZIP 魔数：进一步确认是否含 sessions/<uuid>/session.json
      try {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final f in archive.files) {
          if (f.name.startsWith('sessions/') && f.name.endsWith('/session.json')) {
            return BackupFileType.chatboxZip;
          }
        }
      } catch (_) {
        // 解析失败按 unknown 处理
      }
      return BackupFileType.unknown;
    }
    // 尝试解析为自身备份 JSON
    try {
      final text = decodeUtf8(bytes);
      final root = jsonDecode(text);
      if (root is Map<String, dynamic> &&
          root['schema_version'] is int &&
          root['data'] is Map) {
        return BackupFileType.talkroom;
      }
    } catch (_) {
      // 非 JSON
    }
    return BackupFileType.unknown;
  }

  /// Chatbox 备份 zip 解析（字段级；绝不含 apiKey 真身，仅 provider 名）。
  static ChatboxZip parseChatboxZip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sessions = <ChatboxSession>[];
    final providers = <String>{};
    final modelIds = <String>{};

    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name;
      if (name == 'settings.json') {
        try {
          final root = jsonDecode(decodeUtf8(file.content as List<int>));
          if (root is Map<String, dynamic>) {
            final providersMap = root['providers'];
            if (providersMap is Map<String, dynamic>) {
              // 仅取 provider 键名，绝不外露 apiKey 值
              providers.addAll(providersMap.keys);
            }
          }
        } catch (_) {
          // settings.json 解析失败不阻塞整体
        }
        continue;
      }
      if (!name.startsWith('sessions/') || !name.endsWith('/session.json')) {
        continue;
      }
      try {
        final root = jsonDecode(decodeUtf8(file.content as List<int>));
        if (root is! Map<String, dynamic>) continue;
        final session = _parseChatboxSession(root);
        sessions.add(session);
        if (session.provider != null && session.provider!.isNotEmpty) {
          providers.add(session.provider!);
        }
        if (session.modelId != null && session.modelId!.isNotEmpty) {
          modelIds.add(session.modelId!);
        }
      } catch (_) {
        // 单个会话解析失败跳过
      }
    }

    sessions.sort((a, b) {
      final aTs = a.createdMs ?? 0;
      final bTs = b.createdMs ?? 0;
      return aTs.compareTo(bTs);
    });

    return ChatboxZip(
      sessions: sessions,
      providers: providers,
      modelIds: modelIds,
    );
  }

  static ChatboxSession _parseChatboxSession(Map<String, dynamic> root) {
    final id = (root['id'] as String?) ?? '';
    final title = (root['name'] as String?) ??
        (root['threadName'] as String?) ??
        (id.isEmpty ? '未命名会话' : id);

    final settingsMap = root['settings'];
    String? provider;
    String? modelId;
    double? temperature;
    int? maxContextMessageCount;
    if (settingsMap is Map<String, dynamic>) {
      provider = settingsMap['provider'] as String?;
      modelId = settingsMap['modelId'] as String?;
      temperature = (settingsMap['temperature'] as num?)?.toDouble();
      maxContextMessageCount =
          (settingsMap['maxContextMessageCount'] as num?)?.toInt();
    }

    final messages = <ChatboxMessage>[];
    final rawMessages = root['messages'];
    if (rawMessages is List) {
      for (final raw in rawMessages) {
        if (raw is! Map<String, dynamic>) continue;
        messages.add(_parseChatboxMessage(raw));
      }
      messages.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    }

    return ChatboxSession(
      id: id,
      title: title,
      provider: provider,
      modelId: modelId,
      temperature: temperature,
      maxContextMessageCount: maxContextMessageCount,
      messages: messages,
      archived: root.containsKey('archivedAt'),
    );
  }

  static ChatboxMessage _parseChatboxMessage(Map<String, dynamic> raw) {
    final role = (raw['role'] as String?) ?? 'user';
    final contentParts = raw['contentParts'];
    final texts = <String>[];
    final reasoning = <String>[];
    if (contentParts is List) {
      for (final part in contentParts) {
        if (part is! Map<String, dynamic>) continue;
        final type = part['type'] as String?;
        final text = part['text'];
        final textStr = text is String ? text : '';
        if (type == 'reasoning') {
          if (textStr.isNotEmpty) reasoning.add(textStr);
        } else if (type == 'tool-call') {
          final result = part['result'];
          if (result is String && result.isNotEmpty) {
            texts.add('[工具结果] $result');
          }
        } else {
          // 'text' 及其它类型按正文处理
          if (textStr.isNotEmpty) texts.add(textStr);
        }
      }
    }

    final files = <ChatboxFileRef>[];
    final rawFiles = raw['files'];
    if (rawFiles is List) {
      for (final f in rawFiles) {
        if (f is! Map<String, dynamic>) continue;
        files.add(
          ChatboxFileRef(
            id: (f['id'] as String?) ?? '',
            name: (f['name'] as String?) ?? '附件',
            fileType: f['fileType'] as String?,
            byteLength: (f['byteLength'] as num?)?.toInt(),
          ),
        );
      }
    }

    return ChatboxMessage(
      role: role,
      content: texts.join('\n'),
      reasoningContent: reasoning.isEmpty ? null : reasoning.join('\n'),
      timestampMs: (raw['timestamp'] as num?)?.toInt() ?? 0,
      files: files,
    );
  }

  // ---------------------------------------------------------------
  // Chatbox → 统一备份数据映射
  // ---------------------------------------------------------------

  /// 将 [ChatboxZip] 归一化为 [BackupData]（可走统一事务导入）。
  ///
  /// 映射规则：
  /// - 会话：标题取 name/threadName；createdAt/updatedAt 由消息时间戳推断；
  /// - 消息：role 原样；contentParts 合并（text→正文、reasoning→思维链）；
  /// - 附件：Chatbox 备份仅含 storageKey 引用、无二进制 → 不生成附件，
  ///   计数与说明由调用方在导入报告中展示；
  /// - 模型：按 provider 匹配本地 api_configs（名称/基址包含关键字），
  ///   未匹配使用默认（第一个启用）配置，映射信息返回供报告使用。
  static BackupData mapChatboxToBackup(
    ChatboxZip chatbox,
    List<ApiConfig> localConfigs,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultConfig = _pickDefaultConfig(localConfigs);
    final conversations = <BackupConversation>[];

    for (final s in chatbox.sessions) {
      final config = _matchLocalConfig(s.provider, localConfigs) ??
          defaultConfig;
      final created = s.createdMs ?? now;
      final updated = s.updatedMs ?? created;

      final messages = s.messages
          .map(
            (m) => BackupMessage(
              role: m.role,
              content: m.content,
              contentType: 'text',
              status: 'done',
              modelId: config == null ? s.modelId : null,
              createdAt: m.timestampMs == 0 ? created : m.timestampMs,
              reasoningContent: m.reasoningContent,
            ),
          )
          .toList();

      conversations.add(
        BackupConversation(
          title: s.title,
          apiConfigRef: null,
          modelId: s.modelId,
          temperature: s.temperature,
          pinned: false,
          archived: s.archived,
          lastMessage: messages.isEmpty
              ? ''
              : messages.last.content,
          updatedAt: updated,
          createdAt: created,
          messages: messages,
        ),
      );
    }

    return BackupData(
      appVersion: '',
      exportedAt: now,
      conversations: conversations,
    );
  }

  /// 选择默认配置：第一个启用；无启用则第一个；无配置返回 null。
  static ApiConfig? _pickDefaultConfig(List<ApiConfig> configs) {
    for (final c in configs) {
      if (c.enabled) return c;
    }
    return configs.isEmpty ? null : configs.first;
  }

  /// 按 Chatbox provider 名匹配本地配置：
  /// 1) 本地配置名不区分大小写等于 provider（如 `siliconflow`）；
  /// 2) 本地配置名包含 provider 关键字；
  /// 3) base_url 包含 provider 关键字。
  static ApiConfig? _matchLocalConfig(
    String? provider,
    List<ApiConfig> configs,
  ) {
    if (provider == null || provider.isEmpty) return null;
    final p = provider.toLowerCase().trim();
    for (final c in configs) {
      final name = c.name.toLowerCase();
      if (name == p) return c;
    }
    for (final c in configs) {
      final name = c.name.toLowerCase();
      if (name.contains(p)) return c;
      final url = c.baseUrl.toLowerCase();
      if (url.contains(p)) return c;
    }
    return null;
  }

  // ---------------------------------------------------------------
  // 事务导入
  // ---------------------------------------------------------------

  /// 事务性导入 [data] 到当前数据库；任一步失败自动回滚。
  ///
  /// - 外键重映射：api_config_id / prompt_template_id / target_conversation_id
  ///   按导出时的原值映射到新 id；
  /// - 去重：模型配置按 (name+base_url)、模板按 (name+content)、会话按
  ///   (title+created_at)、任务按 (task_name+prompt)；
  /// - API Key：仅导入配置与引用占位，密钥不落盘，报告提示手动重填；
  /// - 同步字段：settings 层已剔除凭据，消息层同步字段（device_id 等）
  ///   不随备份写入。
  static Future<ImportReport> importBackup(
    AppDatabase db,
    BackupData data, {
    bool isChatbox = false,
  }) async {
    final report = ImportReport(isChatbox: isChatbox);
    final conn = db.db;
    final now = DateTime.now().millisecondsSinceEpoch;

    // 现有数据（去重基准）
    final existingApis = await db.apiConfigRepository.getAll();
    final existingTemplates = await db.promptTemplateRepository.getAll();
    final existingConvos = await db.conversationRepository.getAll();
    final existingTasks = await db.activeTaskRepository.getAll();

    final apiIdMap = <int, int>{};
    final templateIdMap = <int, int>{};
    final conversationIdMap = <int, int>{};

    await conn.transaction((txn) async {
      // 1. settings：剔除凭据键后 upsert
      for (final entry in data.settings.entries) {
        if (isExcludedSettingKey(entry.key)) continue;
        await txn.insert(
          'settings',
          {'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        report.settingsImported++;
      }

      // 2. api_configs：去重 + 新引用键（密钥未导入）
      for (final cfg in data.apiConfigs) {
        final dup = existingApis.any(
          (e) => e.name == cfg.name && e.baseUrl == cfg.baseUrl,
        );
        if (dup) {
          report.apiConfigsSkipped++;
          continue;
        }
        final id = await txn.insert('api_configs', {
          'name': cfg.name,
          'base_url': cfg.baseUrl,
          'api_key_ref': '', // 占位，下面回填
          'model_ids': jsonEncode(cfg.modelIds),
          'enabled': cfg.enabled ? 1 : 0,
          'created_at': cfg.createdAt == 0 ? now : cfg.createdAt,
          'updated_at': cfg.updatedAt == 0 ? now : cfg.updatedAt,
        });
        final refKey = ApiKeyStore.refKeyFor(id);
        await txn.update(
          'api_configs',
          {'api_key_ref': refKey},
          where: 'id = ?',
          whereArgs: [id],
        );
        apiIdMap[cfg.refId ?? id] = id;
        report.apiConfigsImported++;
      }

      // 3. prompt_templates：去重
      for (final t in data.promptTemplates) {
        final dup = existingTemplates.any(
          (e) => e.name == t.name && e.content == t.content,
        );
        if (dup) {
          report.promptTemplatesSkipped++;
          continue;
        }
        final id = await txn.insert('prompt_templates', {
          'name': t.name,
          'content': t.content,
          'builtin': t.builtin ? 1 : 0,
          'created_at': t.createdAt == 0 ? now : t.createdAt,
        });
        templateIdMap[t.refId ?? id] = id;
        report.promptTemplatesImported++;
      }

      // 4. conversations + messages
      for (final c in data.conversations) {
        final dup = existingConvos.any(
          (e) => e.title == c.title && e.createdAt == c.createdAt,
        );
        if (dup) {
          report.conversationsSkipped++;
          continue;
        }
        final apiConfigId = c.apiConfigRef == null
            ? null
            : apiIdMap[c.apiConfigRef];
        final templateId = c.promptTemplateRef == null
            ? null
            : templateIdMap[c.promptTemplateRef];
        final convId = await txn.insert('conversations', {
          'title': c.title,
          'api_config_id': apiConfigId,
          'model_id': c.modelId,
          'system_prompt': c.systemPrompt,
          'temperature': c.temperature,
          'max_tokens': c.maxTokens,
          'top_p': c.topP,
          'frequency_penalty': c.frequencyPenalty,
          'presence_penalty': c.presencePenalty,
          'pinned': c.pinned ? 1 : 0,
          'archived': c.archived ? 1 : 0,
          'prompt_template_id': templateId,
          'last_message': c.lastMessage,
          'updated_at': c.updatedAt == 0 ? now : c.updatedAt,
          'created_at': c.createdAt == 0 ? now : c.createdAt,
        });
        conversationIdMap[c.refId ?? convId] = convId;
        report.conversationsImported++;

        for (final m in c.messages) {
          final msgMap = <String, Object?>{
            'conversation_id': convId,
            'role': m.role,
            'content': m.content,
            'content_type': m.contentType,
            'status': m.status,
            'model_id': m.modelId,
            'prompt_tokens': m.promptTokens,
            'completion_tokens': m.completionTokens,
            'error_message': m.errorMessage,
            'created_at': m.createdAt == 0 ? now : m.createdAt,
            'attachments': MessageAttachment.encodeList(m.attachments),
            'reasoning_content': m.reasoningContent,
            'reasoning_duration_ms': m.reasoningDurationMs,
            'reasoning_tokens': m.reasoningTokens,
            'cached_tokens': m.cachedTokens,
            // 同步字段不随备份写入（device_id / server_id / updated_at = NULL）
          };
          await txn.insert('messages', msgMap);
          report.messagesImported++;
        }
      }

      // 5. active_tasks：外键映射失败降级处理
      for (final t in data.activeTasks) {
        final dup = existingTasks.any(
          (e) => e.taskName == t.taskName && e.prompt == t.prompt,
        );
        if (dup) {
          report.activeTasksSkipped++;
          continue;
        }
        final apiConfigId = t.apiConfigRef == null
            ? null
            : apiIdMap[t.apiConfigRef];
        if (apiConfigId == null) {
          report.activeTasksSkipped++;
          report.notes.add(
            '主动任务「${t.taskName}」因模型配置未导入已跳过，请先导入对应模型配置。',
          );
          continue;
        }
        var targetConvId = t.targetConversationRef == null
            ? null
            : conversationIdMap[t.targetConversationRef];
        var delivery = t.delivery;
        if (targetConvId == null && (delivery == 'chat' || delivery == 'both')) {
          // 目标会话未导入：避免写入不存在的会话，降级为仅通知
          delivery = 'notification';
          report.notes.add(
            '主动任务「${t.taskName}」的目标会话未导入，投递方式已降级为仅通知。',
          );
        }
        await txn.insert('active_tasks', {
          'task_name': t.taskName,
          'task_type': t.taskType,
          'schedule_data': t.scheduleData,
          'prompt': t.prompt,
          'api_config_id': apiConfigId,
          'model_id': t.modelId,
          'target_conversation_id': targetConvId,
          'delivery': delivery,
          'quiet_start': t.quietStart,
          'quiet_end': t.quietEnd,
          'enabled': t.enabled ? 1 : 0,
          'next_run_at': t.nextRunAt,
          'last_run_at': t.lastRunAt,
          'last_status': t.lastStatus,
          'created_at': t.createdAt == 0 ? now : t.createdAt,
        });
        report.activeTasksImported++;
      }
    });

    // 事务提交成功后补充提示
    if (report.apiConfigsImported > 0) {
      report.notes.add(
        '导入的模型配置不含 API Key，请在「服务商管理」中手动重填后使用。',
      );
    }
    if (isChatbox && report.conversationsImported > 0) {
      report.notes.add(
        'Chatbox 附件仅包含引用信息、不含图片二进制，已跳过附件内容。',
      );
    }
    return report;
  }

  // ---------------------------------------------------------------
  // 工具方法
  // ---------------------------------------------------------------

  /// UTF-8 解码（容忍非法字节并去除 BOM）。
  static String decodeUtf8(List<int> bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
      text = text.substring(1);
    }
    return text;
  }
}
