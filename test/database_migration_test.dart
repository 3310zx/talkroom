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
}
