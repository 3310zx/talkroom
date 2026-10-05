import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/active_task_repository.dart';
import '../../domain/repositories/api_config_repository.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../../domain/repositories/device_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/prompt_template_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/sync_cursor_repository.dart';
import '../repositories/active_task_repository_impl.dart';
import '../repositories/api_config_repository_impl.dart';
import '../repositories/conversation_repository_impl.dart';
import '../repositories/device_repository_impl.dart';
import '../repositories/message_repository_impl.dart';
import '../repositories/prompt_template_repository_impl.dart';
import '../repositories/settings_repository_impl.dart';
import '../repositories/sync_cursor_repository_impl.dart';

/// SQLite 数据库单例：负责打开、建表、迁移，并暴露各仓储实现。
///
/// 建表 SQL 对齐 PRD 第 6.1.2 节（M0 范围六张表；局域网同步表见 TODO）。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> open() async {
    if (_db != null) return _db!;

    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/llm_chat_app.db';

    _db = await openDatabase(
      path,
      version: 5,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('AppDatabase.open() 尚未调用，请先初始化数据库。');
    }
    return database;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE api_configs (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT NOT NULL,
        base_url    TEXT NOT NULL,
        api_key_ref TEXT NOT NULL,
        model_ids   TEXT NOT NULL,
        enabled     INTEGER NOT NULL DEFAULT 1,
        created_at  INTEGER NOT NULL,
        updated_at  INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_api_configs_enabled ON api_configs(enabled)');

    await db.execute('''
      CREATE TABLE conversations (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        title         TEXT NOT NULL DEFAULT '新会话',
        api_config_id INTEGER,
        model_id      TEXT,
        system_prompt TEXT,
        temperature   REAL,
        max_tokens    INTEGER,
        top_p         REAL,
        pinned        INTEGER NOT NULL DEFAULT 0,
        archived      INTEGER NOT NULL DEFAULT 0,
        prompt_template_id INTEGER,
        last_message  TEXT,
        updated_at    INTEGER NOT NULL,
        created_at    INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_conversations_updated ON conversations(updated_at DESC)');

    await db.execute('''
      CREATE TABLE messages (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        conversation_id     INTEGER NOT NULL,
        role                TEXT NOT NULL,
        content             TEXT NOT NULL,
        content_type        TEXT NOT NULL DEFAULT 'text',
        status              TEXT NOT NULL DEFAULT 'done',
        model_id            TEXT,
        prompt_tokens       INTEGER,
        completion_tokens   INTEGER,
        error_message       TEXT,
        created_at          INTEGER NOT NULL,
        reasoning_content   TEXT,
        reasoning_duration_ms INTEGER,
        reasoning_tokens    INTEGER,
        cached_tokens       INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_messages_conv ON messages(conversation_id, created_at)');

    await db.execute('''
      CREATE TABLE cache_hits (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        model_id          TEXT,
        cached_tokens     INTEGER NOT NULL DEFAULT 0,
        prompt_tokens     INTEGER,
        completion_tokens INTEGER,
        created_at        INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_cache_hits_created ON cache_hits(created_at DESC)');

    await db.execute('''
      CREATE TABLE active_tasks (
        id                     INTEGER PRIMARY KEY AUTOINCREMENT,
        task_name              TEXT NOT NULL,
        task_type              TEXT NOT NULL,
        schedule_data          TEXT NOT NULL,
        prompt                 TEXT NOT NULL,
        api_config_id          INTEGER NOT NULL,
        model_id               TEXT NOT NULL,
        target_conversation_id INTEGER,
        delivery               TEXT NOT NULL DEFAULT 'both',
        quiet_start            TEXT,
        quiet_end              TEXT,
        enabled                INTEGER NOT NULL DEFAULT 1,
        next_run_at            INTEGER,
        last_run_at            INTEGER,
        last_status            TEXT,
        created_at             INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_active_tasks_next ON active_tasks(enabled, next_run_at)');

    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE prompt_templates (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL,
        content    TEXT NOT NULL,
        builtin    INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // 局域网同步（PRD 第 7 章 7.4；version 2 起建表，旧库通过 onUpgrade 迁移）：
    await _createSyncTables(db);
  }

  Future<void> _createSyncTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id    TEXT NOT NULL UNIQUE,
        device_name  TEXT NOT NULL,
        device_type  TEXT NOT NULL DEFAULT 'client',
        token        TEXT,
        pair_code    TEXT,
        is_trusted   INTEGER NOT NULL DEFAULT 0,
        fail_count   INTEGER NOT NULL DEFAULT 0,
        lock_until   INTEGER NOT NULL DEFAULT 0,
        last_seen_at INTEGER NOT NULL DEFAULT 0,
        created_at   INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursors (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id           TEXT NOT NULL,
        conversation_id     INTEGER NOT NULL,
        last_synced_msg_id  INTEGER NOT NULL DEFAULT 0,
        updated_at          INTEGER NOT NULL,
        UNIQUE(device_id, conversation_id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_cursors_device ON sync_cursors(device_id)');
    // messages 追加同步字段（幂等：列不存在才添加）
    final messageCols = await db.rawQuery('PRAGMA table_info(messages)');
    final existing = messageCols.map((c) => c['name'] as String).toSet();
    if (!existing.contains('device_id')) {
      await db.execute('ALTER TABLE messages ADD COLUMN device_id TEXT');
    }
    if (!existing.contains('server_id')) {
      await db.execute('ALTER TABLE messages ADD COLUMN server_id INTEGER');
    }
    if (!existing.contains('updated_at')) {
      await db.execute('ALTER TABLE messages ADD COLUMN updated_at INTEGER');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_server ON messages(server_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // version 1 -> 2：局域网同步表与字段（PRD 7.4）
    if (oldVersion < 2) {
      await _createSyncTables(db);
    }
    // version 2 -> 3：静默时段字段 + delivery 枚举收敛（PRD 5.1 / 5.2）
    if (oldVersion < 3) {
      await _migrateActiveTasksV3(db);
    }
    // version 3 -> 4：思维链字段 + 缓存命中字段与 cache_hits 表
    if (oldVersion < 4) {
      await _migrateMessagesV4(db);
    }
  }

  /// version 3 -> 4 迁移：
  /// - `messages` 追加 `reasoning_content` / `reasoning_duration_ms` /
  ///   `reasoning_tokens` / `cached_tokens` 四列（幂等，旧数据为 NULL，
  ///   模型层 fromMap 归一化兼容）；
  /// - 新建 `cache_hits` 表（设置页「命中缓存」列表 / 清空用）。
  Future<void> _migrateMessagesV4(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(messages)');
    final existing = cols.map((c) => c['name'] as String).toSet();
    if (!existing.contains('reasoning_content')) {
      await db.execute('ALTER TABLE messages ADD COLUMN reasoning_content TEXT');
    }
    if (!existing.contains('reasoning_duration_ms')) {
      await db.execute(
          'ALTER TABLE messages ADD COLUMN reasoning_duration_ms INTEGER');
    }
    if (!existing.contains('reasoning_tokens')) {
      await db.execute(
          'ALTER TABLE messages ADD COLUMN reasoning_tokens INTEGER');
    }
    if (!existing.contains('cached_tokens')) {
      await db.execute('ALTER TABLE messages ADD COLUMN cached_tokens INTEGER');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cache_hits (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        model_id          TEXT,
        cached_tokens     INTEGER NOT NULL DEFAULT 0,
        prompt_tokens     INTEGER,
        completion_tokens INTEGER,
        created_at        INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cache_hits_created ON cache_hits(created_at DESC)');
  }

  /// version 2 -> 3 迁移：
  /// - `active_tasks` 追加 `quiet_start` / `quiet_end`（HH:mm，可空）；
  /// - 旧枚举 `app_internal` 统一改写为 `chat`（delivery 枚举收敛为
  ///   chat / notification / both，默认 both）。
  Future<void> _migrateActiveTasksV3(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(active_tasks)');
    final existing = cols.map((c) => c['name'] as String).toSet();
    if (!existing.contains('quiet_start')) {
      await db.execute('ALTER TABLE active_tasks ADD COLUMN quiet_start TEXT');
    }
    if (!existing.contains('quiet_end')) {
      await db.execute('ALTER TABLE active_tasks ADD COLUMN quiet_end TEXT');
    }
    await db.execute(
      "UPDATE active_tasks SET delivery = 'chat' WHERE delivery = 'app_internal'",
    );
  }

  // ---- 仓储实例 ----
  late final ActiveTaskRepository activeTaskRepository = ActiveTaskRepositoryImpl(this);
  late final ApiConfigRepository apiConfigRepository = ApiConfigRepositoryImpl(this);
  late final ConversationRepository conversationRepository = ConversationRepositoryImpl(this);
  late final MessageRepository messageRepository = MessageRepositoryImpl(this);
  late final PromptTemplateRepository promptTemplateRepository = PromptTemplateRepositoryImpl(this);
  late final SettingsRepository settingsRepository = SettingsRepositoryImpl(this);
  late final DeviceRepository deviceRepository = DeviceRepositoryImpl(this);
  late final SyncCursorRepository syncCursorRepository = SyncCursorRepositoryImpl(this);
}
