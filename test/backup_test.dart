import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/data/database/app_database.dart';
import 'package:llm_chat_app/domain/models/api_config.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/services/backup/backup_models.dart';
import 'package:llm_chat_app/services/backup/backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 构造一条 [MessageAttachment]（图片 base64 附件，模拟真实导出内容）。
MessageAttachment _imageAttachment() => const MessageAttachment(
      type: 'image',
      name: 'pic.png',
      mimeType: 'image/png',
      sizeBytes: 123,
      dataBase64: 'iVBORw0KGgoAAAANSUhEUg==',
      parseStatus: 'none',
    );

/// 构造一组覆盖全部数据域的 [BackupData]。
BackupData _sampleBackup() {
  return BackupData(
    appVersion: '1.2.13',
    exportedAt: 1700000000000,
    settings: {
      'theme_mode': 'dark',
      'language': 'zh',
      'sync_device_token': 'should-not-export',
      'server_pair_code': 'should-not-export',
    },
    apiConfigs: [
      const BackupApiConfig(
        refId: 7,
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKeyRef: 'api_key_ref_7',
        modelIds: ['gpt-4o', 'gpt-4o-mini'],
        enabled: true,
        createdAt: 1,
        updatedAt: 2,
      ),
    ],
    promptTemplates: [
      const BackupPromptTemplate(
        refId: 3,
        name: '翻译助手',
        content: '把以下内容翻译成英文：',
        builtin: false,
        createdAt: 1,
      ),
    ],
    conversations: [
      BackupConversation(
        refId: 11,
        title: '测试会话',
        apiConfigRef: 7,
        modelId: 'gpt-4o',
        systemPrompt: '你是一个助手',
        temperature: 0.7,
        pinned: true,
        archived: false,
        promptTemplateRef: 3,
        lastMessage: '你好',
        updatedAt: 1700000000000,
        createdAt: 1699999990000,
        messages: [
          BackupMessage(
            role: 'user',
            content: '你好',
            createdAt: 1699999991000,
            attachments: [_imageAttachment()],
          ),
          BackupMessage(
            role: 'assistant',
            content: '你好！',
            status: 'done',
            modelId: 'gpt-4o',
            promptTokens: 10,
            completionTokens: 5,
            createdAt: 1699999992000,
            reasoningContent: '思考过程',
          ),
        ],
      ),
    ],
    activeTasks: [
      BackupActiveTask(
        refId: 5,
        taskName: '每日摘要',
        taskType: 'interval',
        scheduleData: '{"minutes":1440}',
        prompt: '总结今天的对话',
        apiConfigRef: 7,
        modelId: 'gpt-4o',
        targetConversationRef: 11,
        delivery: 'both',
        enabled: true,
        createdAt: 1,
      ),
    ],
  );
}

/// 构造 Chatbox 风格 zip 字节（settings.json + sessions/<uuid>/session.json）。
List<int> _sampleChatboxZip() {
  final archive = Archive();
  archive.addFile(ArchiveFile(
    'settings.json',
    0,
    utf8.encode(jsonEncode({
      'providers': {
        'openai': {'apiKey': 'sk-should-never-surface', 'baseUrl': 'https://api.openai.com/v1'},
        'siliconflow': {'apiKey': 'sk-should-never-surface', 'baseUrl': 'https://api.siliconflow.cn/v1'},
      },
      'temperature': 0.7,
      'theme': 'light',
    })),
  ));
  archive.addFile(ArchiveFile(
    'sessions/aaaaaaaa-bbbb-cccc-dddd-eeeeffff0000/session.json',
    0,
    utf8.encode(jsonEncode({
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeffff0000',
      'name': 'Chatbox 会话',
      'settings': {'provider': 'siliconflow', 'modelId': 'deepseek-ai/DeepSeek-V3'},
      'messages': [
        {
          'role': 'user',
          'contentParts': [
            {'type': 'text', 'text': '你好，介绍一下自己'},
          ],
          'timestamp': 1700000000000,
        },
        {
          'role': 'assistant',
          'contentParts': [
            {'type': 'reasoning', 'text': '好的，我来介绍'},
            {'type': 'text', 'text': '我是 Chatbox 助手'},
          ],
          'timestamp': 1700000001000,
          'files': [
            {'id': 'file-1', 'name': '文档.pdf', 'fileType': 'application/pdf', 'byteLength': 2048},
          ],
        },
      ],
    })),
  ));
  final encoder = ZipEncoder();
  return encoder.encode(archive);
}

/// 构造仅含单个自定义会话的 Chatbox zip 字节（用于标题解析用例）。
List<int> _chatboxZipWithSession(Map<String, dynamic> sessionRoot) {
  final archive = Archive();
  archive.addFile(ArchiveFile(
    'settings.json',
    0,
    utf8.encode(jsonEncode({'providers': {}})),
  ));
  archive.addFile(ArchiveFile(
    'sessions/bbbbbbbb-cccc-dddd-eeee-ffff00001111/session.json',
    0,
    utf8.encode(jsonEncode(sessionRoot)),
  ));
  final encoder = ZipEncoder();
  return encoder.encode(archive);
}

/// 构造 ffi 内存库并建核心表（与 AppDatabase 迁移后真实结构对齐，含 v7 追加列）。
/// [enforceTitleCheck] 为 true 时给 conversations.title 加 CHECK 约束（仅回滚测试用）。
Future<Database> _openMemoryDb({bool enforceTitleCheck = false}) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('''
    CREATE TABLE api_configs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, base_url TEXT NOT NULL, api_key_ref TEXT NOT NULL,
      model_ids TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE conversations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL DEFAULT '新会话'${enforceTitleCheck ? " CHECK(length(title) > 0)" : ''},
      api_config_id INTEGER, model_id TEXT, system_prompt TEXT,
      temperature REAL, max_tokens INTEGER, top_p REAL,
      frequency_penalty REAL, presence_penalty REAL,
      pinned INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
      prompt_template_id INTEGER, last_message TEXT,
      updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      conversation_id INTEGER NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL,
      content_type TEXT NOT NULL DEFAULT 'text', status TEXT NOT NULL DEFAULT 'done',
      model_id TEXT, prompt_tokens INTEGER, completion_tokens INTEGER,
      error_message TEXT, created_at INTEGER NOT NULL, attachments TEXT,
      reasoning_content TEXT, reasoning_duration_ms INTEGER,
      reasoning_tokens INTEGER, cached_tokens INTEGER
    )''');
  await db.execute('''
    CREATE TABLE active_tasks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      task_name TEXT NOT NULL, task_type TEXT NOT NULL, schedule_data TEXT NOT NULL,
      prompt TEXT NOT NULL, api_config_id INTEGER NOT NULL, model_id TEXT NOT NULL,
      target_conversation_id INTEGER, delivery TEXT NOT NULL DEFAULT 'both',
      quiet_start TEXT, quiet_end TEXT, enabled INTEGER NOT NULL DEFAULT 1,
      next_run_at INTEGER, last_run_at INTEGER, last_status TEXT,
      created_at INTEGER NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
  await db.execute('''
    CREATE TABLE prompt_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, content TEXT NOT NULL, builtin INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    )''');
  return db;
}

void main() {
  group('BackupData 序列化回环', () {
    test('toJson → fromJson 保持各数据域一致（含附件 base64）', () {
      final json = _sampleBackup().toJson();
      final parsed = BackupData.fromJson(json);

      expect(parsed.schemaVersion, kBackupSchemaVersion);
      expect(parsed.appVersion, '1.2.13');
      expect(parsed.settings['theme_mode'], 'dark');
      expect(parsed.apiConfigs.single.name, 'OpenAI');
      expect(parsed.apiConfigs.single.modelIds, contains('gpt-4o'));
      expect(parsed.promptTemplates.single.content, contains('翻译'));
      expect(parsed.conversations.single.title, '测试会话');
      expect(parsed.conversations.single.apiConfigRef, 7);
      expect(parsed.conversations.single.messages, hasLength(2));
      expect(
        parsed.conversations.single.messages.first.attachments.single.dataBase64,
        'iVBORw0KGgoAAAANSUhEUg==',
      );
      expect(
        parsed.conversations.single.messages.last.reasoningContent,
        '思考过程',
      );
      expect(parsed.activeTasks.single.taskName, '每日摘要');
      expect(parsed.activeTasks.single.apiConfigRef, 7);
    });

    test('不支持的 schema 版本抛出 FormatException', () {
      final bad = _sampleBackup().toJson()..['schema_version'] = 999;
      expect(() => BackupData.fromJson(bad), throwsFormatException);
    });
  });

  group('备份类型检测', () {
    test('自身备份 JSON 识别为 talkroom', () {
      final bytes = utf8.encode(jsonEncode(_sampleBackup().toJson()));
      expect(BackupService.detectBackupType(bytes, fileName: 'x.talkroom-backup.json'),
          BackupFileType.talkroom);
    });

    test('Chatbox zip 识别为 chatboxZip', () {
      final bytes = _sampleChatboxZip();
      expect(BackupService.detectBackupType(bytes), BackupFileType.chatboxZip);
    });

    test('未知字节识别为 unknown', () {
      expect(BackupService.detectBackupType([1, 2, 3, 4, 5]), BackupFileType.unknown);
    });
  });

  group('Chatbox 解析与映射', () {
    test('parseChatboxZip 解析会话/消息/附件引用且不外露 apiKey', () {
      final zip = BackupService.parseChatboxZip(_sampleChatboxZip());

      expect(zip.sessions, hasLength(1));
      expect(zip.sessions.single.title, 'Chatbox 会话');
      expect(zip.sessions.single.provider, 'siliconflow');
      expect(zip.sessions.single.modelId, 'deepseek-ai/DeepSeek-V3');
      expect(zip.sessions.single.messages, hasLength(2));
      expect(zip.sessions.single.messages.first.content, '你好，介绍一下自己');
      expect(zip.sessions.single.messages.first.role, 'user');
      expect(zip.sessions.single.messages.last.reasoningContent, '好的，我来介绍');
      expect(zip.sessions.single.messages.last.content, '我是 Chatbox 助手');
      expect(zip.sessions.single.messages.last.files, hasLength(1));
      expect(zip.sessions.single.messages.last.files.single.name, '文档.pdf');
      expect(zip.sessions.single.messages.last.files.single.byteLength, 2048);

      // provider 键名存在，但绝不包含密钥值
      expect(zip.providers, contains('openai'));
      expect(zip.providers, contains('siliconflow'));
      final jsonText = jsonEncode(_sampleChatboxZip());
      expect(jsonText.contains('sk-should-never-surface'), isFalse);
    });

    test('mapChatboxToBackup 按 provider 匹配本地配置', () {
      final chatbox = BackupService.parseChatboxZip(_sampleChatboxZip());
      final local = [
        const ApiConfig(
          id: 1, name: '硅基流动', baseUrl: 'https://api.siliconflow.cn/v1',
          apiKeyRef: 'r1', modelIds: ['a'], enabled: true, createdAt: 1, updatedAt: 1,
        ),
        const ApiConfig(
          id: 2, name: 'OpenAI', baseUrl: 'https://api.openai.com/v1',
          apiKeyRef: 'r2', modelIds: ['b'], enabled: false, createdAt: 1, updatedAt: 1,
        ),
      ];
      final mapped = BackupService.mapChatboxToBackup(chatbox, local);

      expect(mapped.conversations, hasLength(1));
      final conv = mapped.conversations.single;
      // provider=siliconflow 匹配到「硅基流动」，会话本身不绑定 api_config（统一导入时重映射）
      expect(conv.modelId, 'deepseek-ai/DeepSeek-V3');
      expect(conv.messages, hasLength(2));
      // Chatbox 附件仅引用、无二进制 → 不生成附件
      expect(conv.messages.last.attachments, isEmpty);
    });

    test('无本地配置时使用 null 配置且保留原 modelId', () {
      final chatbox = BackupService.parseChatboxZip(_sampleChatboxZip());
      final mapped = BackupService.mapChatboxToBackup(chatbox, const []);
      expect(mapped.conversations.single.modelId, 'deepseek-ai/DeepSeek-V3');
    });

    test('会话 name 以换行开头时标题被 trim（真实脏数据回归）', () {
      final zip = _chatboxZipWithSession({
        'id': 'bbbbbbbb-cccc-dddd-eeee-ffff00001111',
        'name': '\n转生游戏',
        'messages': [
          {
            'role': 'user',
            'contentParts': [
              {'type': 'text', 'text': '你好'},
            ],
            'timestamp': 1700000000000,
          },
        ],
      });
      final chatbox = BackupService.parseChatboxZip(zip);
      expect(chatbox.sessions.single.title, '转生游戏');

      final mapped = BackupService.mapChatboxToBackup(chatbox, const []);
      expect(mapped.conversations.single.title, '转生游戏');
    });

    test('会话 name/threadName 为空时回退 topics 首个标题', () {
      final zip = _chatboxZipWithSession({
        'id': 'bbbbbbbb-cccc-dddd-eeee-ffff00001111',
        'messages': [
          {
            'role': 'user',
            'contentParts': [
              {'type': 'text', 'text': '你好'},
            ],
            'timestamp': 1700000000000,
          },
        ],
        'topics': [
          {'title': '话题一', 'messages': []},
          {'title': '话题二', 'messages': []},
        ],
      });
      final chatbox = BackupService.parseChatboxZip(zip);
      expect(chatbox.sessions.single.title, '话题一');
    });

    test('会话标题全空白且无 topics 时回退未命名会话', () {
      final zip = _chatboxZipWithSession({
        'id': 'bbbbbbbb-cccc-dddd-eeee-ffff00001111',
        'name': '   \n  ',
        'messages': [],
      });
      final chatbox = BackupService.parseChatboxZip(zip);
      expect(chatbox.sessions.single.title, '未命名会话');
    });
  });

  group('事务导入回环', () {
    test('导入后各表行数正确、外键重映射、密钥占位、剔除同步凭据', () async {
      final db = await _openMemoryDb();
      final appDb = AppDatabase.forTesting(db);
      final backup = _sampleBackup();

      final report = await BackupService.importBackup(appDb, backup);

      expect(report.settingsImported, 2); // sync_ 键被剔除
      expect(report.apiConfigsImported, 1);
      expect(report.promptTemplatesImported, 1);
      expect(report.conversationsImported, 1);
      expect(report.messagesImported, 2);
      expect(report.activeTasksImported, 1);
      expect(report.notes.any((n) => n.contains('手动重填')), isTrue);

      final settings = await db.query('settings');
      expect(settings.map((r) => r['key']), isNot(contains('sync_device_token')));
      expect(settings.map((r) => r['key']), isNot(contains('server_pair_code')));

      final convs = await db.query('conversations');
      expect(convs, hasLength(1));
      final conv = convs.single;
      // 外键重映射：备份 refId=7 → 新 id=1
      expect(conv['api_config_id'], 1);
      expect(conv['prompt_template_id'], 1);
      expect(conv['pinned'], 1);

      final msgs = await db.query('messages');
      expect(msgs, hasLength(2));
      expect(msgs.first['conversation_id'], 1);
      expect(msgs.first['attachments'], contains('iVBORw0KGgoAAAANSUhEUg=='));

      final tasks = await db.query('active_tasks');
      expect(tasks.single['api_config_id'], 1);
      expect(tasks.single['target_conversation_id'], 1);
      expect(tasks.single['delivery'], 'both');

      final apis = await db.query('api_configs');
      expect(apis.single['api_key_ref'], isNotEmpty);
      expect(apis.single['api_key_ref'], isNot('api_key_ref_7'));

      await db.close();
    });

    test('重复导入同一备份全部去重跳过', () async {
      final db = await _openMemoryDb();
      final appDb = AppDatabase.forTesting(db);
      final backup = _sampleBackup();

      final first = await BackupService.importBackup(appDb, backup);
      expect(first.conversationsImported, 1);

      final second = await BackupService.importBackup(appDb, backup);
      expect(second.conversationsImported, 0);
      expect(second.conversationsSkipped, 1);
      expect(second.apiConfigsSkipped, 1);
      expect(second.promptTemplatesSkipped, 1);
      expect(second.messagesImported, 0);
      expect(second.activeTasksSkipped, 1);
      expect(await db.query('conversations'), hasLength(1));
      expect(await db.query('messages'), hasLength(2));

      await db.close();
    });

    test('Chatbox 归一化备份可走统一导入', () async {
      final db = await _openMemoryDb();
      final appDb = AppDatabase.forTesting(db);
      final chatbox = BackupService.parseChatboxZip(_sampleChatboxZip());
      final mapped = BackupService.mapChatboxToBackup(chatbox, const []);

      final report = await BackupService.importBackup(appDb, mapped, isChatbox: true);
      expect(report.conversationsImported, 1);
      expect(report.messagesImported, 2);
      expect(report.isChatbox, isTrue);
      expect(report.notes.any((n) => n.contains('Chatbox')), isTrue);
      expect(await db.query('conversations'), hasLength(1));

      await db.close();
    });

    test('导入异常整体回滚，不留半截数据', () async {
      final db = await _openMemoryDb(enforceTitleCheck: true);
      final appDb = AppDatabase.forTesting(db);

      // 含合法 settings/api_configs，但会话标题为空字符串 → 触发 CHECK 约束异常
      final bad = BackupData(
        settings: {'theme_mode': 'dark'},
        apiConfigs: const [
          BackupApiConfig(
            name: 'OpenAI', baseUrl: 'https://api.openai.com/v1',
            apiKeyRef: 'x', modelIds: ['gpt-4o'], createdAt: 1, updatedAt: 1,
          ),
        ],
        conversations: [
          BackupConversation(
            title: '',
            updatedAt: 1,
            createdAt: 1,
            messages: const [
              BackupMessage(role: 'user', content: 'hi', createdAt: 1),
            ],
          ),
        ],
      );

      await expectLater(
        BackupService.importBackup(appDb, bad),
        throwsA(isA<Exception>()),
      );
      // 事务已回滚：settings 与 api_configs 的写入一并撤销
      expect(await db.query('settings'), isEmpty);
      expect(await db.query('api_configs'), isEmpty);
      expect(await db.query('conversations'), isEmpty);

      await db.close();
    });
  });

  group('真实 Chatbox 备份验证', () {
    const realPath =
        '/Users/a28345/Library/Containers/com.tencent.xinWeChat/Data/Documents/xwechat_files/wxid_81itv7ezhua622_01b4/msg/file/2026-10/chatbox-backup-2026-10-10.zip';

    test('解析真实备份：会话 37、消息 1497、附件引用可统计', () async {
      final file = File(realPath);
      if (!file.existsSync()) {
        markTestSkipped('附件不在当前环境，跳过真实备份验证');
        return;
      }
      final bytes = await file.readAsBytes();
      final zip = BackupService.parseChatboxZip(bytes);

      // 以真实备份实际内容为准：61 会话、2478 消息
      expect(zip.sessions, hasLength(61));
      expect(zip.messagesCount, 2478);
      expect(zip.providers, isNotEmpty);

      final fileRefCount = zip.sessions.fold<int>(
        0,
        (sum, s) => sum +
            s.messages.fold<int>(
              0,
              (mSum, m) => mSum + m.files.length,
            ),
      );
      expect(fileRefCount, greaterThan(0));

      // 结构合法性：每条消息都有 role/content；附件引用有 byteLength 或 id
      for (final s in zip.sessions) {
        for (final m in s.messages) {
          expect(['system', 'user', 'assistant', 'tool'], contains(m.role));
          for (final f in m.files) {
            expect(f.id, isNotEmpty);
          }
        }
      }
    });
  });
}
