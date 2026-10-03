import 'package:sqflite/sqflite.dart';

import '../../domain/models/message.dart';
import '../../domain/repositories/message_repository.dart';
import '../database/app_database.dart';

/// 消息仓储的 SQLite 实现。
class MessageRepositoryImpl implements MessageRepository {
  MessageRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<ChatMessage>> listByConversation(int conversationId) async {
    final rows = await _appDatabase.db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  @override
  Future<ChatMessage?> getById(int id) async {
    final rows = await _appDatabase.db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatMessage.fromMap(rows.first);
  }

  @override
  Future<int> insert(ChatMessage message) async {
    return _appDatabase.db.insert('messages', message.toMap()..remove('id'));
  }

  @override
  Future<void> update(ChatMessage message) async {
    await _appDatabase.db.update(
      'messages',
      message.toMap(),
      where: 'id = ?',
      whereArgs: [message.id],
    );
  }

  @override
  Future<void> deleteByConversation(int conversationId) async {
    await _appDatabase.db.delete(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _appDatabase.db.delete('messages', where: 'id = ?', whereArgs: [id]);
  }

  // ---- 缓存命中记录（设置页「命中缓存」） ----

  @override
  Future<int> insertCacheHit(CacheHitRecord record) async {
    if (record.cachedTokens <= 0 && record.promptTokens == null) {
      return -1;
    }
    return _appDatabase.db.insert('cache_hits', record.toMap()..remove('id'));
  }

  @override
  Future<List<CacheHitRecord>> listCacheHits({int limit = 200}) async {
    final rows = await _appDatabase.db.query(
      'cache_hits',
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(CacheHitRecord.fromMap).toList();
  }

  @override
  Future<int> clearCacheHits() async {
    return _appDatabase.db.delete('cache_hits');
  }

  // ---- 局域网同步（PRD 第 7 章） ----

  @override
  Future<List<ChatMessage>> listByServerIdAfter({
    required int conversationId,
    required int afterServerId,
    int limit = 500,
  }) async {
    final rows = await _appDatabase.db.query(
      'messages',
      where: 'conversation_id = ? AND server_id IS NOT NULL AND server_id > ?',
      whereArgs: [conversationId, afterServerId],
      orderBy: 'server_id ASC',
      limit: limit,
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  @override
  Future<int> getMaxServerId() async {
    final rows = await _appDatabase.db.rawQuery(
      'SELECT COALESCE(MAX(server_id), 0) AS max_id FROM messages',
    );
    return rows.first['max_id'] as int? ?? 0;
  }

  @override
  Future<ChatMessage?> findByServerId(int serverId) async {
    final rows = await _appDatabase.db.query(
      'messages',
      where: 'server_id = ?',
      whereArgs: [serverId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ChatMessage.fromMap(rows.first);
  }

  @override
  Future<List<ChatMessage>> listPendingUpload(String deviceId) async {
    final rows = await _appDatabase.db.query(
      'messages',
      where: 'device_id = ? AND server_id IS NULL',
      whereArgs: [deviceId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  @override
  Future<bool> existsByDeviceAndClientTs(String deviceId, int clientTs) async {
    final rows = await _appDatabase.db.query(
      'messages',
      where: 'device_id = ? AND created_at = ?',
      whereArgs: [deviceId, clientTs],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<List<ChatMessage>> listByServerIdUpTo({
    required int conversationId,
    required int afterServerId,
    required int toServerId,
  }) async {
    final rows = await _appDatabase.db.query(
      'messages',
      where:
          'conversation_id = ? AND server_id IS NOT NULL AND server_id > ? AND server_id <= ?',
      whereArgs: [conversationId, afterServerId, toServerId],
      orderBy: 'server_id ASC',
    );
    return rows.map(ChatMessage.fromMap).toList();
  }

  @override
  Future<List<ChatMessage>> insertWithServerIds(List<ChatMessage> messages) async {
    if (messages.isEmpty) return const [];
    final result = <ChatMessage>[];
    await _appDatabase.db.transaction((txn) async {
      var nextId = await _nextServerId(txn);
      for (final m in messages) {
        nextId += 1;
        final map = m.toMap()
          ..remove('id')
          ..['server_id'] = nextId
          ..['updated_at'] = m.updatedAt ?? DateTime.now().millisecondsSinceEpoch;
        await txn.insert('messages', map);
        result.add(m.copyWith(serverId: nextId, updatedAt: map['updated_at'] as int?));
      }
    });
    return result;
  }

  @override
  Future<List<ChatMessage>> finalizeLocalMessages() async {
    final rows = await _appDatabase.db.query(
      'messages',
      where: 'server_id IS NULL',
      orderBy: 'created_at ASC, id ASC',
    );
    if (rows.isEmpty) return const [];
    final pending = rows.map(ChatMessage.fromMap).toList();
    final result = <ChatMessage>[];
    await _appDatabase.db.transaction((txn) async {
      var nextId = await _nextServerId(txn);
      for (final m in pending) {
        nextId += 1;
        final now = DateTime.now().millisecondsSinceEpoch;
        await txn.update(
          'messages',
          {'server_id': nextId, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [m.id],
        );
        result.add(m.copyWith(serverId: nextId, updatedAt: now));
      }
    });
    return result;
  }

  Future<int> _nextServerId(DatabaseExecutor txn) async {
    final rows = await txn.rawQuery(
      'SELECT COALESCE(MAX(server_id), 0) AS max_id FROM messages',
    );
    return rows.first['max_id'] as int? ?? 0;
  }
}
