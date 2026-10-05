import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/database_provider.dart';
import '../../domain/models/active_task.dart';
import '../../domain/models/active_task_log.dart';

/// 主动消息任务执行日志页（R16，v1.0.15）。
///
/// 展示某任务最近 50 条执行记录（成功 / 失败 / 跳过），
/// 每条含执行时间、状态与摘要，便于排障与回溯。
class ActiveTaskLogPage extends ConsumerWidget {
  const ActiveTaskLogPage({super.key, required this.task});

  final ActiveTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repository = ref.watch(appDatabaseProvider).activeTaskRepository;
    return Scaffold(
      appBar: AppBar(title: Text('执行日志 · ${task.taskName}')),
      body: FutureBuilder<List<ActiveTaskLog>>(
        future: repository.listLogsByTask(task.id!),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final logs = snapshot.data ?? const [];
          if (logs.isEmpty) {
            return Center(
              child: Text(
                '暂无执行日志\n任务执行后这里会展示记录',
                textAlign: TextAlign.center,
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              // FutureBuilder 重建以刷新列表。
              await repository.listLogsByTask(task.id!);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final log = logs[index];
                final color = switch (log.status) {
                  'success' => const Color(0xFF2E7D32),
                  'skipped' => const Color(0xFFF9A825),
                  _ => const Color(0xFFC62828),
                };
                return ListTile(
                  leading: Icon(
                    switch (log.status) {
                      'success' => Icons.check_circle_outline,
                      'skipped' => Icons.skip_next_outlined,
                      _ => Icons.error_outline,
                    },
                    color: color,
                  ),
                  title: Text(log.summary, maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${log.statusLabel} · ${_formatTime(log.runAt)}',
                    style: TextStyle(color: color),
                  ),
                  isThreeLine: true,
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.year}年${dt.month.toString().padLeft(2, '0')}月'
        '${dt.day.toString().padLeft(2, '0')}日 '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        ':${dt.second.toString().padLeft(2, '0')}';
  }
}
