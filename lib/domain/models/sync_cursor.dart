/// 设备×会话同步游标实体（对应 PRD 6.1.2 `sync_cursors` 表，第 7 章 7.3.1）。
///
/// 客户端按会话维护 `last_synced_msg_id`，只拉取 `server_id > 游标` 的增量消息。
class SyncCursor {
  final int? id;
  final String deviceId;
  final int conversationId;
  final int lastSyncedMsgId;
  final int updatedAt;

  const SyncCursor({
    this.id,
    required this.deviceId,
    required this.conversationId,
    required this.lastSyncedMsgId,
    required this.updatedAt,
  });

  SyncCursor copyWith({
    int? id,
    String? deviceId,
    int? conversationId,
    int? lastSyncedMsgId,
    int? updatedAt,
  }) {
    return SyncCursor(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      conversationId: conversationId ?? this.conversationId,
      lastSyncedMsgId: lastSyncedMsgId ?? this.lastSyncedMsgId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'conversation_id': conversationId,
      'last_synced_msg_id': lastSyncedMsgId,
      'updated_at': updatedAt,
    };
  }

  factory SyncCursor.fromMap(Map<String, Object?> map) {
    return SyncCursor(
      id: map['id'] as int?,
      deviceId: map['device_id'] as String? ?? '',
      conversationId: map['conversation_id'] as int? ?? 0,
      lastSyncedMsgId: map['last_synced_msg_id'] as int? ?? 0,
      updatedAt: map['updated_at'] as int? ?? 0,
    );
  }
}
