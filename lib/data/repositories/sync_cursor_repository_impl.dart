import 'package:sqflite/sqflite.dart';

import '../../domain/models/sync_cursor.dart';
import '../../domain/repositories/sync_cursor_repository.dart';
import '../database/app_database.dart';

/// 同步游标仓储的 SQLite 实现。
class SyncCursorRepositoryImpl implements SyncCursorRepository {
  SyncCursorRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<SyncCursor?> getCursor(String deviceId, int conversationId) async {
    final rows = await _appDatabase.db.query(
      'sync_cursors',
      where: 'device_id = ? AND conversation_id = ?',
      whereArgs: [deviceId, conversationId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncCursor.fromMap(rows.first);
  }

  @override
  Future<void> setCursor(SyncCursor cursor) async {
    final map = cursor.toMap()..remove('id');
    await _appDatabase.db.insert(
      'sync_cursors',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
