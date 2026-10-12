import 'package:sqflite/sqflite.dart';

import '../../domain/models/memory_item.dart';
import '../../domain/repositories/memory_repository.dart';
import '../database/app_database.dart';

/// 记忆库仓储的 SQLite 实现。
///
/// 记忆表与局域网同步 / 备份无关（决策 D7 / D8）：不参与 server_id 游标、
/// 不纳入导出导入，仅本机持久化。
class MemoryRepositoryImpl implements MemoryRepository {
  MemoryRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  Database get _db => _appDatabase.db;

  @override
  Future<List<MemoryItem>> listByConversation(int conversationId) async {
    final rows = await _db.query(
      'memories',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'pinned DESC, updated_at DESC, id DESC',
    );
    return rows.map(MemoryItem.fromMap).toList();
  }

  @override
  Future<List<MemoryItem>> listAll() async {
    final rows = await _db.query(
      'memories',
      orderBy: 'pinned DESC, updated_at DESC, id DESC',
    );
    return rows.map(MemoryItem.fromMap).toList();
  }

  @override
  Future<List<MemoryItem>> search(String keyword, {int limit = 200}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];
    final rows = await _db.query(
      'memories',
      where: 'content LIKE ?',
      whereArgs: ['%$kw%'],
      orderBy: 'pinned DESC, updated_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(MemoryItem.fromMap).toList();
  }

  @override
  Future<int> insert(MemoryItem item) async {
    final id = await _db.insert('memories', item.toMap());
    return id;
  }

  @override
  Future<void> update(MemoryItem item) async {
    final id = item.id;
    if (id == null) return;
    await _db.update(
      'memories',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> deleteByConversation(int conversationId) async {
    await _db.delete(
      'memories',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  @override
  Future<int?> lastAutoSummaryAt(int conversationId) async {
    final rows = await _db.query(
      'memories',
      columns: ['updated_at'],
      where: 'conversation_id = ? AND kind = ?',
      whereArgs: [conversationId, 'auto'],
      orderBy: 'updated_at DESC, id DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['updated_at'] as int?;
  }
}
