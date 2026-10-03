import '../models/conversation.dart';

/// 会话仓储接口。
abstract class ConversationRepository {
  /// 按最近更新时间倒序
  Future<List<Conversation>> getAll();

  Future<Conversation?> getById(int id);
  Future<int> insert(Conversation conversation);
  Future<void> update(Conversation conversation);

  /// 删除会话（级联删除消息由调用方保证或由数据层事务处理）
  Future<void> delete(int id);
}
