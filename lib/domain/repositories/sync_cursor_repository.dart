import '../models/sync_cursor.dart';

/// 设备×会话同步游标仓储接口（PRD 第 7 章 `sync_cursors` 表）。
abstract class SyncCursorRepository {
  Future<SyncCursor?> getCursor(String deviceId, int conversationId);

  /// 设置游标（不存在则插入，存在则更新）
  Future<void> setCursor(SyncCursor cursor);
}
