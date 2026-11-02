import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:llm_chat_app/data/database/app_database.dart';

/// 构造一个 version 10 的旧版内存库：messages 表缺失 duration_ms 列
/// （模拟 v1.2.16 性能图表上线前的老库），其余表仅建占位结构。
Future<Database> _openV10Db() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false, version: 10),
  );
  // messages 为 v10 结构：无 duration_ms（性能图表列缺失）。
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
    CREATE TABLE api_configs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, base_url TEXT NOT NULL, api_key_ref TEXT NOT NULL,
      model_ids TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      favorite INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )''');
  return db;
}

/// 构造一个 version 12 的旧版内存库：conversations 表缺失上下文压缩摘要三列
/// （模拟 v1.2.23 及更早的库），messages 表为最新结构以简化断言。
Future<Database> _openV12Db() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false, version: 12),
  );
  // v12 结构：无 context_summary / context_summary_upto_id /
  // context_summary_updated_at 三列。
  await db.execute('''
    CREATE TABLE conversations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL, api_config_id INTEGER, model_id TEXT,
      system_prompt TEXT, temperature REAL, max_tokens INTEGER, top_p REAL,
      frequency_penalty REAL, presence_penalty REAL,
      pinned INTEGER NOT NULL DEFAULT 0, archived INTEGER NOT NULL DEFAULT 0,
      prompt_template_id INTEGER, last_message TEXT NOT NULL DEFAULT '',
      updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL
    )''');
  return db;
}

void main() {
  group('数据库迁移 v10 -> v11（duration_ms 列）', () {
    test('升级后 messages 表包含 duration_ms 列且性能查询可用', () async {
      final db = await _openV10Db();
      try {
        await AppDatabase.runMigrations(db, 10, 11);

        final cols = await db.rawQuery('PRAGMA table_info(messages)');
        final names = cols.map((c) => c['name']).toList();
        expect(names, contains('duration_ms'));

        // 插入带耗时数据后，性能图表同款查询可正常执行。
        await db.insert('messages', {
          'conversation_id': 1,
          'role': 'assistant',
          'content': 'ok',
          'status': 'done',
          'created_at': 1,
          'duration_ms': 123,
        });
        final rows = await db.rawQuery(
          'SELECT duration_ms FROM messages WHERE duration_ms IS NOT NULL '
          'ORDER BY created_at DESC LIMIT 1',
        );
        expect(rows.single['duration_ms'], 123);
      } finally {
        await db.close();
      }
    });

    test('重复执行迁移幂等，不重复加列、不报错', () async {
      final db = await _openV10Db();
      try {
        await AppDatabase.runMigrations(db, 10, 11);
        await AppDatabase.runMigrations(db, 10, 11);

        final cols = await db.rawQuery('PRAGMA table_info(messages)');
        final names = cols.map((c) => c['name']).toList();
        expect(names.where((n) => n == 'duration_ms'), hasLength(1));
      } finally {
        await db.close();
      }
    });
  });

  group('数据库迁移 v12 -> v13（上下文压缩摘要列）', () {
    const summaryColumns = [
      'context_summary',
      'context_summary_upto_id',
      'context_summary_updated_at',
    ];

    test('升级后 conversations 表补齐三列且可读写摘要状态', () async {
      final db = await _openV12Db();
      try {
        await AppDatabase.runMigrations(db, 12, 13);

        final cols = await db.rawQuery('PRAGMA table_info(conversations)');
        final names = cols.map((c) => c['name']).toList();
        for (final column in summaryColumns) {
          expect(names, contains(column));
        }

        // 老会话升级后三列为 NULL，视为「尚未压缩」。
        await db.insert('conversations', {
          'title': '老会话',
          'updated_at': 1,
          'created_at': 1,
        });
        final fresh = await db.query('conversations');
        expect(fresh.single['context_summary'], isNull);
        expect(fresh.single['context_summary_upto_id'], isNull);
        expect(fresh.single['context_summary_updated_at'], isNull);

        // 写入压缩状态后可正常读回（重启后一致）。
        await db.update(
          'conversations',
          {
            'context_summary': '历史已压缩为摘要',
            'context_summary_upto_id': 42,
            'context_summary_updated_at': 1730000000000,
          },
          where: 'id = ?',
          whereArgs: [fresh.single['id']],
        );
        final updated = await db.query('conversations');
        expect(updated.single['context_summary'], '历史已压缩为摘要');
        expect(updated.single['context_summary_upto_id'], 42);
        expect(updated.single['context_summary_updated_at'], 1730000000000);
      } finally {
        await db.close();
      }
    });

    test('重复执行迁移幂等，每个摘要列只存在一次', () async {
      final db = await _openV12Db();
      try {
        await AppDatabase.runMigrations(db, 12, 13);
        await AppDatabase.runMigrations(db, 12, 13);

        final cols = await db.rawQuery('PRAGMA table_info(conversations)');
        final names = cols.map((c) => c['name']).toList();
        for (final column in summaryColumns) {
          expect(names.where((n) => n == column), hasLength(1));
        }
      } finally {
        await db.close();
      }
    });
  });
}
