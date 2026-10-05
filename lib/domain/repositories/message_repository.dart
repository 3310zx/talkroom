import '../models/message.dart';
import '../models/message_search_hit.dart';

/// 消息仓储接口。
abstract class MessageRepository {
  /// 按创建时间升序返回某会话的全部消息
  Future<List<ChatMessage>> listByConversation(int conversationId);

  /// 跨会话全文搜索（R12，v1.0.15）：按关键词模糊匹配消息内容，
  /// 返回命中消息及其所属会话（按会话更新时间倒序、消息时间倒序），
  /// 供全局搜索页展示与跳转定位。
  Future<List<MessageSearchHit>> searchMessages(
    String keyword, {
    int limit = 100,
  });

  Future<ChatMessage?> getById(int id);
  Future<int> insert(ChatMessage message);
  Future<void> update(ChatMessage message);

  /// 删除会话下的全部消息（级联）
  Future<void> deleteByConversation(int conversationId);

  /// 删除单条消息
  Future<void> delete(int id);

  /// 删除某条消息及其之后的所有消息（同会话，编辑重发 / 重新生成时清理旧回复）
  Future<void> deleteFrom(int id);

  // ---- 局域网同步（PRD 第 7 章） ----

  /// 服务器权威库：拉取某会话 `server_id > afterServerId` 的增量消息（升序）
  Future<List<ChatMessage>> listByServerIdAfter({
    required int conversationId,
    required int afterServerId,
    int limit = 500,
  });

  /// 服务器权威库：当前最大 server_id（无则为 0）
  Future<int> getMaxServerId();

  /// 按 server_id 查消息（客户端增量去重用）
  Future<ChatMessage?> findByServerId(int serverId);

  /// 客户端：本机待上传消息（server_id IS NULL 且由本机产生）
  Future<List<ChatMessage>> listPendingUpload(String deviceId);

  /// 幂等去重：某设备在指定客户端时间戳是否已存在消息
  Future<bool> existsByDeviceAndClientTs(String deviceId, int clientTs);

  /// 按 server_id 升序取某会话在区间 (after, to] 的消息
  Future<List<ChatMessage>> listByServerIdUpTo({
    required int conversationId,
    required int afterServerId,
    required int toServerId,
  });

  /// 服务器权威库：在单事务中按给定顺序（已按冲突裁决排序）为新消息分配
  /// 递增 server_id 并插入，返回分配 server_id 后的完整消息。
  Future<List<ChatMessage>> insertWithServerIds(List<ChatMessage> messages);

  /// 服务器权威库：为电脑端本地产生的待同步消息（server_id IS NULL）分配
  /// server_id 并落库，使电脑端消息也能被增量同步到手机端。
  Future<List<ChatMessage>> finalizeLocalMessages();

  // ---- 缓存命中记录（设置页「命中缓存」） ----

  /// 记录一条缓存命中；无可写数据（cached_tokens=0 且无 prompt_tokens）时
  /// 返回 -1 表示已忽略。
  Future<int> insertCacheHit(CacheHitRecord record);

  /// 按时间倒序拉取缓存命中记录
  Future<List<CacheHitRecord>> listCacheHits({int limit = 200});

  /// 清空全部缓存命中记录（仅清 cache_hits 表，不动聊天历史）
  Future<int> clearCacheHits();
}
