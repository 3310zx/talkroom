/// 主动消息任务实体（对应 PRD 6.1.2 `active_tasks` 表，P1 功能预留）。
class ActiveTask {
  final int? id;
  final String taskName;
  final String taskType; // 'daily'|'weekly'|'interval'|'event'
  final String scheduleData; // JSON：{time, weekdays, interval_hours, event_type}
  final String prompt;
  final int apiConfigId;
  final String modelId;
  final int? targetConversationId;
  final String delivery; // 'chat'|'notification'|'both'（PRD 5.1）
  final String? quietStart; // HH:mm，null = 未设置（PRD 5.2）
  final String? quietEnd; // HH:mm，null = 未设置（PRD 5.2）
  final bool enabled;
  final int? nextRunAt;
  final int? lastRunAt;
  final String? lastStatus; // 'ok'|'failed'|'skipped'|'missed'
  final int createdAt;

  const ActiveTask({
    this.id,
    required this.taskName,
    required this.taskType,
    required this.scheduleData,
    required this.prompt,
    required this.apiConfigId,
    required this.modelId,
    this.targetConversationId,
    this.delivery = 'both',
    this.quietStart,
    this.quietEnd,
    this.enabled = true,
    this.nextRunAt,
    this.lastRunAt,
    this.lastStatus,
    required this.createdAt,
  });

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'task_name': taskName,
      'task_type': taskType,
      'schedule_data': scheduleData,
      'prompt': prompt,
      'api_config_id': apiConfigId,
      'model_id': modelId,
      'target_conversation_id': targetConversationId,
      'delivery': delivery,
      'quiet_start': quietStart,
      'quiet_end': quietEnd,
      'enabled': enabled ? 1 : 0,
      'next_run_at': nextRunAt,
      'last_run_at': lastRunAt,
      'last_status': lastStatus,
      'created_at': createdAt,
    };
  }

  factory ActiveTask.fromMap(Map<String, Object?> map) {
    return ActiveTask(
      id: map['id'] as int?,
      taskName: map['task_name'] as String? ?? '',
      taskType: map['task_type'] as String? ?? 'interval',
      scheduleData: map['schedule_data'] as String? ?? '{}',
      prompt: map['prompt'] as String? ?? '',
      apiConfigId: map['api_config_id'] as int? ?? 0,
      modelId: map['model_id'] as String? ?? '',
      targetConversationId: map['target_conversation_id'] as int?,
      delivery: _normalizeDelivery(map['delivery'] as String?),
      quietStart: map['quiet_start'] as String?,
      quietEnd: map['quiet_end'] as String?,
      enabled: (map['enabled'] as int? ?? 1) == 1,
      nextRunAt: map['next_run_at'] as int?,
      lastRunAt: map['last_run_at'] as int?,
      lastStatus: map['last_status'] as String?,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }

  ActiveTask copyWith({
    int? id,
    String? taskName,
    String? taskType,
    String? scheduleData,
    String? prompt,
    int? apiConfigId,
    String? modelId,
    int? targetConversationId,
    String? delivery,
    String? quietStart,
    String? quietEnd,
    bool? enabled,
    int? nextRunAt,
    int? lastRunAt,
    String? lastStatus,
    int? createdAt,
  }) {
    return ActiveTask(
      id: id ?? this.id,
      taskName: taskName ?? this.taskName,
      taskType: taskType ?? this.taskType,
      scheduleData: scheduleData ?? this.scheduleData,
      prompt: prompt ?? this.prompt,
      apiConfigId: apiConfigId ?? this.apiConfigId,
      modelId: modelId ?? this.modelId,
      targetConversationId:
          targetConversationId ?? this.targetConversationId,
      delivery: delivery ?? this.delivery,
      quietStart: quietStart ?? this.quietStart,
      quietEnd: quietEnd ?? this.quietEnd,
      enabled: enabled ?? this.enabled,
      nextRunAt: nextRunAt ?? this.nextRunAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      lastStatus: lastStatus ?? this.lastStatus,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ---- 静默时段与投递决策（PRD 5.1 / 5.2） ----

  /// 兼容旧枚举：version=2 及更早的 `app_internal` 等价于「仅写聊天」。
  static String _normalizeDelivery(String? raw) {
    final value = raw ?? 'both';
    return value == 'app_internal' ? 'chat' : value;
  }

  (int, int)? get _quietStartHm => _parseHm(quietStart);
  (int, int)? get _quietEndHm => _parseHm(quietEnd);

  static (int, int)? _parseHm(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return (h, m);
  }

  /// 是否配置了完整（开始 + 结束）的静默时段；开始等于结束视为未设置。
  bool get hasQuietPeriod {
    final s = _quietStartHm;
    final e = _quietEndHm;
    return s != null &&
        e != null &&
        !(s.$1 == e.$1 && s.$2 == e.$2);
  }

  /// 判断 [now] 是否落在静默时段内；支持跨午夜（如 23:00-06:00）。
  /// 开始时间等于结束时间视为未设置（返回 false）。
  bool inQuietPeriod(DateTime now) {
    final start = _quietStartHm;
    final end = _quietEndHm;
    if (start == null || end == null) return false;
    final minute = now.hour * 60 + now.minute;
    final s = start.$1 * 60 + start.$2;
    final e = end.$1 * 60 + end.$2;
    if (s == e) return false;
    if (s < e) return minute >= s && minute < e;
    return minute >= s || minute < e; // 跨午夜：23:00-06:00 等
  }

  /// 是否写入目标会话（chat / both 通道）。
  bool get shouldWriteChat => delivery == 'chat' || delivery == 'both';

  /// 是否发送本地通知；[quiet] 为当前是否处于静默时段。
  /// 静默时段内统一抑制通知（PRD 5.2）。
  bool shouldNotifyDuring(bool quiet) {
    if (delivery == 'chat') return false;
    if (quiet) return false;
    return delivery == 'notification' || delivery == 'both';
  }

  /// 是否应跳过本次投递：仅通知通道（notification）在静默时段内跳过
  /// （无聊天通道可写，直接重新排下一次）；chat / both 不受静默影响。
  bool shouldSkipRun(DateTime now) =>
      delivery == 'notification' && inQuietPeriod(now);
}
