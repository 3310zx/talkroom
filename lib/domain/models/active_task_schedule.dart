import 'dart:convert';

/// 主动消息任务「触发规则」解析与描述（PRD 5.2.1 / 6.1.2）。
///
/// 规则以 JSON 字符串存于 `active_tasks.schedule_data`：
/// - 一次性  once    : {"time": "HH:mm"}
/// - 每天    daily   : {"time": "HH:mm"}
/// - 每周    weekly  : {"time": "HH:mm", "weekdays": [1..7]}
/// - 间隔    interval: {"interval_hours": N}
///
/// 时间均为系统本地时区（不依赖网络），夏令时由 DateTime 构造自动处理。
class ActiveTaskSchedule {
  const ActiveTaskSchedule({
    required this.taskType,
    this.time,
    this.weekdays = const [],
    this.intervalHours,
  });

  /// 'once' | 'daily' | 'weekly' | 'interval'
  final String taskType;

  /// HH:mm（once/daily/weekly 使用）
  final String? time;

  /// 周一=1 … 周日=7（weekly 使用）
  final List<int> weekdays;

  /// 间隔小时数（interval 使用）
  final int? intervalHours;

  int? get _hour => time == null ? null : int.tryParse(time!.split(':').first);
  int? get _minute => time == null ? null : int.tryParse(time!.split(':').last);

  bool get isInterval => taskType == 'interval';

  /// 序列化为数据库存储的 JSON。
  String toJson() {
    final map = <String, dynamic>{
      if (time != null) 'time': time,
      if (weekdays.isNotEmpty) 'weekdays': weekdays,
      if (intervalHours != null) 'interval_hours': intervalHours,
    };
    return jsonEncode(map);
  }

  factory ActiveTaskSchedule.fromJson(String? raw, {required String taskType}) {
    final map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) map.addAll(decoded);
      } catch (_) {
        // 解析失败按空规则处理，调度器会跳过该任务（避免错误触发）。
      }
    }
    return ActiveTaskSchedule(
      taskType: taskType,
      time: map['time'] as String?,
      weekdays: [
        if (map['weekdays'] is List)
          for (final w in (map['weekdays'] as List).whereType<num>()) w.toInt(),
      ],
      intervalHours: (map['interval_hours'] as num?)?.toInt(),
    );
  }

  /// 中文描述，供任务列表页展示（如「每天 08:00」「每周 一、三 09:00」）。
  String describe() {
    switch (taskType) {
      case 'once':
        return '一次性 ${time ?? ''}'.trim();
      case 'daily':
        return '每天 ${time ?? ''}'.trim();
      case 'weekly':
        final names = <int, String>{
          1: '一',
          2: '二',
          3: '三',
          4: '四',
          5: '五',
          6: '六',
          7: '日',
        };
        final days = weekdays.map((w) => names[w] ?? '$w').join('、');
        return '每周 $days ${time ?? ''}'.trim();
      case 'interval':
        return '每${intervalHours ?? 24}小时'.trim();
      default:
        return '未知规则';
    }
  }

  /// 周期毫秒数（用于速率保护：执行间隔不小于周期的 50%）。
  int cycleMillis() {
    switch (taskType) {
      case 'interval':
        return (intervalHours ?? 24) * 3600 * 1000;
      case 'daily':
        return 24 * 3600 * 1000;
      case 'weekly':
        return 7 * 24 * 3600 * 1000;
      default:
        return 0; // once 不设速率下限
    }
  }

  /// 计算 [from] 之后的下一次触发时间（本地时间戳毫秒）。
  /// 一次性任务返回 null（执行一次后不再调度）。
  int? computeNextRunAt(DateTime from) {
    switch (taskType) {
      case 'once':
        return _computeNextTime(from);
      case 'daily':
        return _computeNextTime(from);
      case 'weekly':
        return _computeNextWeekday(from);
      case 'interval':
        final hours = intervalHours ?? 24;
        return from.add(Duration(hours: hours)).millisecondsSinceEpoch;
      default:
        return null;
    }
  }

  int? _computeNextTime(DateTime from) {
    final h = _hour;
    final m = _minute;
    if (h == null || m == null) return null;
    var candidate = DateTime(from.year, from.month, from.day, h, m);
    // 目标时刻已过（或正好等于 from 时已执行），顺延到明天（跨午夜由构造自然处理）。
    if (!candidate.isAfter(from)) {
      candidate = candidate.add(const Duration(days: 1));
    }
    return candidate.millisecondsSinceEpoch;
  }

  int? _computeNextWeekday(DateTime from) {
    final h = _hour;
    final m = _minute;
    if (h == null || m == null || weekdays.isEmpty) return null;
    for (var offset = 0; offset < 8; offset++) {
      final day = from.add(Duration(days: offset));
      if (!weekdays.contains(day.weekday)) continue;
      final candidate = DateTime(day.year, day.month, day.day, h, m);
      if (candidate.isAfter(from)) return candidate.millisecondsSinceEpoch;
    }
    return null;
  }
}
