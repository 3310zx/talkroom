import '../../domain/models/active_task.dart';
import '../../domain/models/active_task_log.dart';
import '../../domain/repositories/active_task_repository.dart';
import '../database/app_database.dart';

/// 主动消息任务仓储的 SQLite 实现。
class ActiveTaskRepositoryImpl implements ActiveTaskRepository {
  ActiveTaskRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<ActiveTask>> getAll() async {
    final rows = await _appDatabase.db.query(
      'active_tasks',
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(ActiveTask.fromMap).toList();
  }

  @override
  Future<ActiveTask?> getById(int id) async {
    final rows = await _appDatabase.db.query(
      'active_tasks',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ActiveTask.fromMap(rows.first);
  }

  @override
  Future<List<ActiveTask>> getDueTasks(int nowMs) async {
    final rows = await _appDatabase.db.query(
      'active_tasks',
      where: 'enabled = 1 AND next_run_at IS NOT NULL AND next_run_at <= ?',
      whereArgs: [nowMs],
      orderBy: 'next_run_at ASC',
    );
    return rows.map(ActiveTask.fromMap).toList();
  }

  @override
  Future<List<ActiveTask>> getMissedTasks(int nowMs) async {
    final rows = await _appDatabase.db.query(
      'active_tasks',
      where: 'enabled = 1 AND next_run_at IS NOT NULL AND next_run_at < ?',
      whereArgs: [nowMs],
      orderBy: 'next_run_at ASC',
    );
    return rows.map(ActiveTask.fromMap).toList();
  }

  @override
  Future<int> insert(ActiveTask task) async {
    return _appDatabase.db.insert('active_tasks', task.toMap()..remove('id'));
  }

  @override
  Future<void> update(ActiveTask task) async {
    await _appDatabase.db.update(
      'active_tasks',
      task.toMap(),
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _appDatabase.db.delete('active_tasks', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> insertLog(ActiveTaskLog log) async {
    await _appDatabase.db.insert('execution_logs', log.toMap()..remove('id'));
  }

  @override
  Future<List<ActiveTaskLog>> listLogsByTask(int taskId, {int limit = 50}) async {
    final rows = await _appDatabase.db.query(
      'execution_logs',
      where: 'task_id = ?',
      whereArgs: [taskId],
      orderBy: 'run_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(ActiveTaskLog.fromMap).toList();
  }
}
