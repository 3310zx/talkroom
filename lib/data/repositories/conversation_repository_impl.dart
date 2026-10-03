import '../../domain/models/conversation.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../database/app_database.dart';

/// 会话仓储的 SQLite 实现。
class ConversationRepositoryImpl implements ConversationRepository {
  ConversationRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<Conversation>> getAll() async {
    final rows = await _appDatabase.db.query(
      'conversations',
      orderBy: 'pinned DESC, updated_at DESC',
    );
    return rows.map(Conversation.fromMap).toList();
  }

  @override
  Future<Conversation?> getById(int id) async {
    final rows = await _appDatabase.db.query(
      'conversations',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Conversation.fromMap(rows.first);
  }

  @override
  Future<int> insert(Conversation conversation) async {
    return _appDatabase.db.insert('conversations', conversation.toMap()..remove('id'));
  }

  @override
  Future<void> update(Conversation conversation) async {
    await _appDatabase.db.update(
      'conversations',
      conversation.toMap(),
      where: 'id = ?',
      whereArgs: [conversation.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _appDatabase.db.transaction((txn) async {
      await txn.delete('messages', where: 'conversation_id = ?', whereArgs: [id]);
      await txn.delete('conversations', where: 'id = ?', whereArgs: [id]);
    });
  }
}
