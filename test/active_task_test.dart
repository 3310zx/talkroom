import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/domain/models/active_task.dart';

ActiveTask _task({
  String delivery = 'both',
  String? quietStart,
  String? quietEnd,
}) {
  return ActiveTask(
    taskName: '测试任务',
    taskType: 'daily',
    scheduleData: '{"time":"08:00","weekdays":[],"interval_hours":null}',
    prompt: 'prompt',
    apiConfigId: 0,
    modelId: '',
    delivery: delivery,
    quietStart: quietStart,
    quietEnd: quietEnd,
    createdAt: 0,
  );
}

void main() {
  group('静默时段判断（PRD 5.2）', () {
    test('未设置静默时段 → 恒为 false', () {
      final task = _task();
      expect(task.hasQuietPeriod, isFalse);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 8, 0)), isFalse);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 23, 30)), isFalse);
    });

    test('开始与结束只有一个 → 视为未配置', () {
      final onlyStart = _task(quietStart: '23:00');
      expect(onlyStart.hasQuietPeriod, isFalse);
      final onlyEnd = _task(quietEnd: '06:00');
      expect(onlyEnd.hasQuietPeriod, isFalse);
    });

    test('常规时段 09:00-17:00：区间内 true，边界按半开区间', () {
      final task = _task(quietStart: '09:00', quietEnd: '17:00');
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 9, 0)), isTrue);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 10, 30)), isTrue);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 16, 59)), isTrue);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 17, 0)), isFalse);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 8, 59)), isFalse);
    });

    test('跨午夜 23:00-06:00：深夜与凌晨均命中', () {
      final task = _task(quietStart: '23:00', quietEnd: '06:00');
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 23, 30)), isTrue);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 0, 30)), isTrue);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 5, 59)), isTrue);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 6, 0)), isFalse);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 22, 0)), isFalse);
    });

    test('开始时间等于结束时间 → 视为未设置', () {
      final task = _task(quietStart: '12:00', quietEnd: '12:00');
      expect(task.hasQuietPeriod, isFalse);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 12, 0)), isFalse);
    });

    test('非法 HH:mm 值 → 忽略', () {
      final task = _task(quietStart: '25:00', quietEnd: '06:00');
      expect(task.hasQuietPeriod, isFalse);
      expect(task.inQuietPeriod(DateTime(2026, 1, 1, 3, 0)), isFalse);
    });
  });

  group('投递通道（PRD 5.1）', () {
    test('chat 仅写聊天，不发通知', () {
      final task = _task(delivery: 'chat');
      expect(task.shouldWriteChat, isTrue);
      expect(task.shouldNotifyDuring(false), isFalse);
      expect(task.shouldNotifyDuring(true), isFalse);
      expect(task.shouldSkipRun(DateTime(2026, 1, 1, 3, 0)), isFalse);
    });

    test('notification 仅通知，不写聊天；静默时段内跳过本次投递', () {
      final task = _task(delivery: 'notification', quietStart: '23:00', quietEnd: '06:00');
      expect(task.shouldWriteChat, isFalse);
      expect(task.shouldNotifyDuring(false), isTrue);
      expect(task.shouldNotifyDuring(true), isFalse);
      // 非静默 → 正常执行
      expect(task.shouldSkipRun(DateTime(2026, 1, 1, 12, 0)), isFalse);
      // 静默时段内 → 跳过（重新排下一次）
      expect(task.shouldSkipRun(DateTime(2026, 1, 1, 23, 30)), isTrue);
      expect(task.shouldSkipRun(DateTime(2026, 1, 1, 3, 0)), isTrue);
    });

    test('both 双通道；静默时段仅抑制通知，仍写聊天不跳过', () {
      final task = _task(delivery: 'both', quietStart: '23:00', quietEnd: '06:00');
      expect(task.shouldWriteChat, isTrue);
      expect(task.shouldNotifyDuring(false), isTrue);
      expect(task.shouldNotifyDuring(true), isFalse);
      expect(task.shouldSkipRun(DateTime(2026, 1, 1, 23, 30)), isFalse);
    });
  });

  group('序列化与旧数据兼容', () {
    test('toMap / fromMap 往返保留 quiet 字段', () {
      final task = _task(delivery: 'both', quietStart: '23:00', quietEnd: '06:00');
      final map = task.toMap();
      final restored = ActiveTask.fromMap(map);
      expect(restored.delivery, 'both');
      expect(restored.quietStart, '23:00');
      expect(restored.quietEnd, '06:00');
      expect(restored.hasQuietPeriod, isTrue);
    });

    test('旧枚举 app_internal 归一化为 chat（version=2 迁移后数据）', () {
      final map = _task(delivery: 'chat').toMap()..['delivery'] = 'app_internal';
      final restored = ActiveTask.fromMap(map);
      expect(restored.delivery, 'chat');
      expect(restored.shouldWriteChat, isTrue);
      expect(restored.shouldNotifyDuring(false), isFalse);
    });

    test('delivery 缺省 → 默认 both', () {
      final map = _task().toMap()..remove('delivery');
      expect(ActiveTask.fromMap(map).delivery, 'both');
    });
  });
}
