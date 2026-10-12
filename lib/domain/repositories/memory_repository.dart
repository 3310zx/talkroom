import '../models/memory_item.dart';

/// 记忆库仓储接口（外置记忆库，version 12）。
abstract class MemoryRepository {
  /// 按会话列出记忆（置顶优先，其次更新时间倒序）
  Future<List<MemoryItem>> listByConversation(int conversationId);

  /// 列出全部记忆（记忆库管理页，按会话 + 更新时间倒序）
  Future<List<MemoryItem>> listAll();

  /// 关键词搜索记忆（匹配 content 文本）
  Future<List<MemoryItem>> search(String keyword, {int limit = 200});

  /// 新增记忆条目，返回落库 id
  Future<int> insert(MemoryItem item);

  /// 更新记忆（内容 / 置顶状态）
  Future<void> update(MemoryItem item);

  /// 删除单条记忆
  Future<void> delete(int id);

  /// 删除某会话下的全部记忆（删除会话时级联清理）
  Future<void> deleteByConversation(int conversationId);

  /// 最近整理游标：某会话最后一次自动整理写入的 updated_at（无则为 null）
  Future<int?> lastAutoSummaryAt(int conversationId);
}
