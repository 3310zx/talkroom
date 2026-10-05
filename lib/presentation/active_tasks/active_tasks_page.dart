import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/active_tasks_provider.dart';
import '../../domain/models/active_task.dart';
import '../../domain/models/active_task_schedule.dart';
import 'active_task_edit_page.dart';
import 'active_task_log_page.dart';

/// 主动消息管理页（PRD 5.1 方案 A：定时任务管理）。
///
/// 从设置页进入，支持创建 / 编辑 / 删除 / 启停定时任务，
/// 列表展示下次执行时间、启停状态、最近执行结果与时间。
class ActiveTasksPage extends ConsumerWidget {
  const ActiveTasksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(activeTasksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('主动消息')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEdit(context, ref, existing: null),
        icon: const Icon(Icons.add),
        label: const Text('新建任务'),
      ),
      body: tasks.isEmpty ? const _EmptyView() : _TaskListView(tasks: tasks),
    );
  }

  Future<void> _openEdit(BuildContext context, WidgetRef ref,
      {ActiveTask? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveTaskEditPage(existing: existing),
      ),
    );
    // 返回后无论是否保存都重新加载，保证状态一致。
    await ref.read(activeTasksProvider.notifier).load();
  }
}

class _TaskListView extends ConsumerWidget {
  const _TaskListView({required this.tasks});

  final List<ActiveTask> tasks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(activeTasksProvider.notifier);
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final task = tasks[index];
        final schedule = ActiveTaskSchedule.fromJson(
          task.scheduleData,
          taskType: task.taskType,
        );
        return ListTile(
          leading: Switch(
            value: task.enabled,
            onChanged: (v) => notifier.setEnabled(task, v),
          ),
          title: Text(task.taskName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(schedule.describe()),
              Text('下次执行：${_formatTime(task.nextRunAt)}'),
              Text('最近结果：${_statusText(task)}'),
              Text(_deliveryText(task)),
              if (task.quietStart != null)
                Text('静默时段：${task.quietStart} ~ ${task.quietEnd}'),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.receipt_long_outlined),
                tooltip: '执行日志',
                onPressed: () => _openLogs(context, task),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: '编辑',
                onPressed: () => _openEdit(context, ref, existing: task),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '删除',
                onPressed: () => _confirmDelete(context, ref, task),
              ),
            ],
          ),
          onTap: () => _openEdit(context, ref, existing: task),
        );
      },
    );
  }

  Future<void> _openLogs(BuildContext context, ActiveTask task) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ActiveTaskLogPage(task: task)),
    );
  }

  Future<void> _openEdit(BuildContext context, WidgetRef ref,
      {ActiveTask? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveTaskEditPage(existing: existing),
      ),
    );
    await ref.read(activeTasksProvider.notifier).load();
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, ActiveTask task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除定时任务'),
        content: Text('确定删除「${task.taskName}」吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(activeTasksProvider.notifier).remove(task.id!);
    }
  }

  String _deliveryText(ActiveTask task) => switch (task.delivery) {
        'chat' => '投递：仅聊天',
        'notification' => '投递：仅通知',
        _ => '投递：聊天 + 通知',
      };

  String _statusText(ActiveTask task) {
    if (task.lastStatus == null) return '尚未执行';
    final at = task.lastRunAt == null ? '' : '（${_formatTime(task.lastRunAt)}）';
    return switch (task.lastStatus!) {
      'ok' => '成功$at',
      'failed' => '失败$at',
      'skipped' => '跳过$at',
      'missed' => '错过$at',
      _ => '${task.lastStatus}$at',
    };
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.schedule_outlined, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Text('尚未创建定时任务'),
          SizedBox(height: 4),
          Text('点击右下角「新建任务」开始', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

/// 毫秒时间戳 → 「MM-dd HH:mm」本地时间。
String _formatTime(int? millis) {
  if (millis == null) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
