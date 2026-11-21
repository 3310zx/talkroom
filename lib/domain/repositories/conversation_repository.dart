import '../models/conversation.dart';

/// 会话仓储接口。
abstract class ConversationRepository {
  /// 按最近更新时间倒序
  Future<List<Conversation>> getAll();

  Future<Conversation?> getById(int id);
  Future<int> insert(Conversation conversation);
  Future<void> update(Conversation conversation);

  /// 仅更新上下文压缩摘要三列（v1.2.25 / P1-02）。
  ///
  /// 压缩写回不得整行覆盖会话，否则会把并发修改的标题 / 最后消息 / 温度 /
  /// updatedAt 等字段回退到压缩开始时的陈旧快照；故单独提供只写三列接口。
  Future<void> updateContextSummary(
      int id, String? summary, int? uptoId, int? updatedAt);

  /// 删除会话（级联删除消息由调用方保证或由数据层事务处理）
  Future<void> delete(int id);
}
