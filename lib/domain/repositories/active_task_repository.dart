import '../models/active_task.dart';
import '../models/active_task_log.dart';

/// 主动消息任务仓储接口（PRD 5.1 定时任务配置持久化）。
abstract class ActiveTaskRepository {
  /// 全部任务（按创建时间升序）。
  Future<List<ActiveTask>> getAll();

  Future<ActiveTask?> getById(int id);

  /// 到点应执行的任务：enabled=1 且 next_run_at <= [nowMs]。
  Future<List<ActiveTask>> getDueTasks(int nowMs);

  /// 错过的任务：enabled=1 且 next_run_at < [nowMs]（启动补跑用）。
  Future<List<ActiveTask>> getMissedTasks(int nowMs);

  Future<int> insert(ActiveTask task);
  Future<void> update(ActiveTask task);
  Future<void> delete(int id);

  /// 写入任务执行日志（R16，v1.0.15）。
  Future<void> insertLog(ActiveTaskLog log);

  /// 查询某任务最近 [limit] 条执行日志（按时间倒序）。
  Future<List<ActiveTaskLog>> listLogsByTask(int taskId, {int limit = 50});
}
