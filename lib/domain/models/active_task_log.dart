/// 主动消息任务执行日志（PRD 5.5；v1.0.15 / DB version 7 起）。
///
/// 每次调度器尝试执行任务都会写入一条记录，用于查看执行历史与排障。
class ActiveTaskLog {
  final int? id;
  final int taskId;

  /// 执行时刻（Unix 毫秒）。
  final int runAt;

  /// 执行状态：`success` / `failure` / `skipped`。
  final String status;

  /// 摘要（中文）：成功时为首句摘要，失败时为错误原因，跳过时为跳过原因。
  final String summary;

  final int createdAt;

  const ActiveTaskLog({
    this.id,
    required this.taskId,
    required this.runAt,
    required this.status,
    required this.summary,
    required this.createdAt,
  });

  ActiveTaskLog copyWith({
    int? id,
    int? taskId,
    int? runAt,
    String? status,
    String? summary,
    int? createdAt,
  }) {
    return ActiveTaskLog(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      runAt: runAt ?? this.runAt,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'task_id': taskId,
      'run_at': runAt,
      'status': status,
      'summary': summary,
      'created_at': createdAt,
    };
  }

  factory ActiveTaskLog.fromMap(Map<String, Object?> map) {
    return ActiveTaskLog(
      id: map['id'] as int?,
      taskId: map['task_id'] as int? ?? 0,
      runAt: map['run_at'] as int? ?? 0,
      status: map['status'] as String? ?? 'failure',
      summary: map['summary'] as String? ?? '',
      createdAt: map['created_at'] as int? ?? 0,
    );
  }

  /// 状态中文名（界面展示）。
  String get statusLabel {
    switch (status) {
      case 'success':
        return '成功';
      case 'skipped':
        return '跳过';
      default:
        return '失败';
    }
  }
}
