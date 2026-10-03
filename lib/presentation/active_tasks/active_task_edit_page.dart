import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/active_tasks_provider.dart';
import '../../application/providers/api_configs_provider.dart';
import '../../application/providers/conversations_provider.dart';
import '../../domain/models/active_task.dart';
import '../../domain/models/active_task_schedule.dart';

/// 主动消息任务创建 / 编辑页（PRD 5.2.1）。
///
/// 字段：名称、触发时刻、重复频率（一次性 / 每天 / 每周指定星期 / 间隔）、
/// prompt、目标会话（为空则自动新建）、关联 API 配置（沿用默认或指定）、
/// 投递方式（chat / both / notification，PRD 5.1）与静默时段
/// （quiet_start / quiet_end，HH:mm，可选，PRD 5.2）。时间一律按系统
/// 本地时区存储（HH:mm）。
class ActiveTaskEditPage extends ConsumerStatefulWidget {
  const ActiveTaskEditPage({super.key, this.existing});

  /// 传入则进入编辑模式。
  final ActiveTask? existing;

  @override
  ConsumerState<ActiveTaskEditPage> createState() => _ActiveTaskEditPageState();
}

class _ActiveTaskEditPageState extends ConsumerState<ActiveTaskEditPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _promptCtrl;
  late final TextEditingController _intervalCtrl;
  late final TextEditingController _modelCtrl;

  String _taskType = 'daily';
  TimeOfDay _time = const TimeOfDay(hour: 8, minute: 0);
  Set<int> _weekdays = {DateTime.now().weekday};
  int _intervalHours = 24;
  int _apiConfigId = 0; // 0 = 沿用默认（启用配置 / 第一个）
  int? _conversationId; // null = 自动新建会话
  String _delivery = 'both';
  TimeOfDay? _quietStart; // 静默时段开始（HH:mm，null=未设置）
  TimeOfDay? _quietEnd; // 静默时段结束（HH:mm，null=未设置）

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing == null) {
      _nameCtrl = TextEditingController();
      _promptCtrl = TextEditingController();
      _intervalCtrl = TextEditingController(text: '24');
      _modelCtrl = TextEditingController();
      return;
    }
    final schedule =
        ActiveTaskSchedule.fromJson(existing.scheduleData, taskType: existing.taskType);
    _nameCtrl = TextEditingController(text: existing.taskName);
    _promptCtrl = TextEditingController(text: existing.prompt);
    _taskType = existing.taskType;
    _time = _parseTime(schedule.time) ?? const TimeOfDay(hour: 8, minute: 0);
    _weekdays = schedule.weekdays.toSet();
    _intervalHours = schedule.intervalHours ?? 24;
    _intervalCtrl = TextEditingController(text: '$_intervalHours');
    _apiConfigId = existing.apiConfigId;
    _conversationId = existing.targetConversationId;
    _delivery = existing.delivery;
    _quietStart = _parseTime(existing.quietStart);
    _quietEnd = _parseTime(existing.quietEnd);
    _modelCtrl = TextEditingController(text: existing.modelId);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _promptCtrl.dispose();
    _intervalCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  TimeOfDay? _parseTime(String? time) {
    if (time == null) return null;
    final parts = time.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    final apiConfigs = ref.watch(apiConfigsProvider);
    final conversations = ref.watch(conversationsProvider);
    final showWeekdays = _taskType == 'weekly';
    final showInterval = _taskType == 'interval';

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '编辑定时任务' : '新建定时任务')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '任务名称',
              hintText: '如：每日晨报',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('触发时刻'),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: Text(_time.format(context)),
                  onPressed: _pickTime,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('重复频率'),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'once', label: Text('一次性')),
              ButtonSegment(value: 'daily', label: Text('每天')),
              ButtonSegment(value: 'weekly', label: Text('每周')),
              ButtonSegment(value: 'interval', label: Text('间隔')),
            ],
            selected: {_taskType},
            onSelectionChanged: (values) =>
                setState(() => _taskType = values.first),
          ),
          if (showWeekdays) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in const {
                  1: '一',
                  2: '二',
                  3: '三',
                  4: '四',
                  5: '五',
                  6: '六',
                  7: '日',
                }.entries)
                  FilterChip(
                    label: Text('周${entry.value}'),
                    selected: _weekdays.contains(entry.key),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _weekdays.add(entry.key);
                      } else {
                        _weekdays.remove(entry.key);
                      }
                    }),
                  ),
              ],
            ),
          ],
          if (showInterval) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _intervalCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '间隔（小时）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _promptCtrl,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Prompt 内容',
              hintText: '告诉 LLM 主动生成什么内容',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _apiConfigId,
            decoration: const InputDecoration(
              labelText: '关联 API 配置',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: 0,
                child: Text('沿用默认（自动选择启用配置）'),
              ),
              for (final config in apiConfigs)
                DropdownMenuItem(
                  value: config.id,
                  child: Text(config.name),
                ),
            ],
            onChanged: (v) => setState(() => _apiConfigId = v ?? 0),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            initialValue: _conversationId,
            decoration: const InputDecoration(
              labelText: '目标会话',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('自动新建会话（推荐）'),
              ),
              for (final conv in conversations)
                DropdownMenuItem<int?>(
                  value: conv.id,
                  child: Text(conv.title, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (v) => setState(() => _conversationId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: '模型（可选，留空使用 API 配置的第一个模型）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('投递方式'),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'chat', label: Text('仅聊天')),
              ButtonSegment(value: 'both', label: Text('聊天 + 通知')),
              ButtonSegment(value: 'notification', label: Text('仅通知')),
            ],
            selected: {_delivery},
            onSelectionChanged: (values) =>
                setState(() => _delivery = values.first),
          ),
          const SizedBox(height: 16),
          Text('静默时段（可选）'),
          const SizedBox(height: 4),
          Text(
            '静默时段内不发送通知；「仅通知」任务会跳过本次执行（重新排下一次），'
            '「仅聊天 / 聊天+通知」任务仍写入聊天。支持跨午夜，如 23:00-06:00。',
            style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.bedtime_outlined),
                  label: Text(_formatQuiet(_quietStart)),
                  onPressed: () => _pickQuiet(isStart: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('~'),
              ),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: Text(_formatQuiet(_quietEnd)),
                  onPressed: () => _pickQuiet(isStart: false),
                ),
              ),
            ],
          ),
          if (_quietStart != null || _quietEnd != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _clearQuiet,
                child: const Text('清除静默时段'),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: '选择触发时刻',
    );
    if (picked != null) setState(() => _time = picked);
  }

  String _formatQuiet(TimeOfDay? t) => t == null
      ? '未设置'
      : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickQuiet({required bool isStart}) async {
    final current = isStart ? _quietStart : _quietEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? const TimeOfDay(hour: 22, minute: 0),
      helpText: isStart ? '选择静默开始时间' : '选择静默结束时间',
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _quietStart = picked;
      } else {
        _quietEnd = picked;
      }
    });
  }

  void _clearQuiet() => setState(() {
        _quietStart = null;
        _quietEnd = null;
      });

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final prompt = _promptCtrl.text.trim();
    if (name.isEmpty) {
      _snack('请填写任务名称');
      return;
    }
    if (prompt.isEmpty) {
      _snack('请填写 Prompt 内容');
      return;
    }
    if (_taskType == 'weekly' && _weekdays.isEmpty) {
      _snack('请至少选择一个星期');
      return;
    }
    if (_taskType == 'interval') {
      final hours = int.tryParse(_intervalCtrl.text.trim());
      if (hours == null || hours <= 0) {
        _snack('间隔小时需为正整数');
        return;
      }
      _intervalHours = hours;
    }
    if ((_quietStart == null) != (_quietEnd == null)) {
      _snack('静默时段需同时设置开始与结束时间');
      return;
    }

    final schedule = ActiveTaskSchedule(
      taskType: _taskType,
      time: _taskType == 'interval'
          ? null
          : '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      weekdays: _taskType == 'weekly' ? (_weekdays.toList()..sort()) : const [],
      intervalHours: _taskType == 'interval' ? _intervalHours : null,
    );
    final now = DateTime.now();
    final nextRunAt = schedule.computeNextRunAt(now);
    final notifier = ref.read(activeTasksProvider.notifier);
    final existing = widget.existing;

    final task = ActiveTask(
      id: existing?.id,
      taskName: name,
      taskType: _taskType,
      scheduleData: schedule.toJson(),
      prompt: prompt,
      apiConfigId: _apiConfigId,
      modelId: _modelCtrl.text.trim(),
      targetConversationId: _conversationId,
      delivery: _delivery,
      quietStart: _quietStart == null ? null : _formatQuiet(_quietStart),
      quietEnd: _quietEnd == null ? null : _formatQuiet(_quietEnd),
      enabled: existing?.enabled ?? true,
      nextRunAt: nextRunAt,
      lastRunAt: existing?.lastRunAt,
      lastStatus: existing?.lastStatus,
      createdAt: existing?.createdAt ?? now.millisecondsSinceEpoch,
    );

    if (existing == null) {
      await notifier.add(task);
    } else {
      await notifier.update(task);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
