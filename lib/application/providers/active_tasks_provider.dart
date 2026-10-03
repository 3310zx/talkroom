import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/active_task.dart';
import '../../domain/repositories/active_task_repository.dart';
import 'database_provider.dart';

/// 主动消息任务状态（PRD 2.2：activeTasksProvider）。
///
/// 从数据库 `active_tasks` 表加载任务列表，提供增删改/启停。
final activeTasksProvider =
    StateNotifierProvider<ActiveTasksNotifier, List<ActiveTask>>(
  (ref) => ActiveTasksNotifier(ref.watch(appDatabaseProvider).activeTaskRepository),
);

class ActiveTasksNotifier extends StateNotifier<List<ActiveTask>> {
  ActiveTasksNotifier(this._repository) : super(const []);

  final ActiveTaskRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<int> add(ActiveTask task) async {
    final id = await _repository.insert(task);
    await load();
    return id;
  }

  Future<void> update(ActiveTask task) async {
    await _repository.update(task);
    await load();
  }

  Future<void> remove(int id) async {
    await _repository.delete(id);
    await load();
  }

  Future<void> setEnabled(ActiveTask task, bool enabled) async {
    await _repository.update(task.copyWith(enabled: enabled));
    await load();
  }
}

