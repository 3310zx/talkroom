/// 记忆条目（外置记忆库，version 12 新增 memories 表）。
///
/// - 归属：每条记忆挂在某个会话下（决策 D5：按会话记忆）；
/// - 来源：`kind == 'manual'` 手动收藏（消息长按「保存到记忆库」/ 记忆库页添加），
///   `kind == 'auto'` 自动整理（定时任务 memory_summary 写入）；
/// - 独立于消息：`source_message_id` 仅作溯源，源消息删除后记忆仍保留；
/// - 置顶：`pinned == 1` 的记忆在注入与列表排序中优先；
/// - 记忆不纳入局域网同步与备份（决策 D7 / D8，仅本机数据）。
class MemoryItem {
  final int? id;
  final int conversationId;
  final String content;
  final String kind; // 'manual' | 'auto'
  final int? sourceMessageId;
  final bool pinned;
  final int createdAt; // 毫秒时间戳
  final int updatedAt; // 毫秒时间戳

  const MemoryItem({
    this.id,
    required this.conversationId,
    required this.content,
    this.kind = 'manual',
    this.sourceMessageId,
    this.pinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 中文来源标签（记忆库列表 / 详情面板展示）。
  String get kindLabel => kind == 'auto' ? '自动整理' : '手动收藏';

  MemoryItem copyWith({
    int? id,
    int? conversationId,
    String? content,
    String? kind,
    int? sourceMessageId,
    bool? pinned,
    int? createdAt,
    int? updatedAt,
  }) {
    return MemoryItem(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      content: content ?? this.content,
      kind: kind ?? this.kind,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      pinned: pinned ?? this.pinned,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory MemoryItem.fromMap(Map<String, Object?> map) {
    return MemoryItem(
      id: map['id'] as int?,
      conversationId: map['conversation_id'] as int,
      content: map['content'] as String,
      kind: (map['kind'] as String?) ?? 'manual',
      sourceMessageId: map['source_message_id'] as int?,
      pinned: ((map['pinned'] as int?) ?? 0) == 1,
      createdAt: map['created_at'] as int,
      updatedAt: map['updated_at'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'content': content,
      'kind': kind,
      'source_message_id': sourceMessageId,
      'pinned': pinned ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
