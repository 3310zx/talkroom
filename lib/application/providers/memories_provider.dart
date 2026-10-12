import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/memory_item.dart';
import '../../domain/repositories/memory_repository.dart';
import 'database_provider.dart';

/// 当前会话记忆列表（按会话维度加载，置顶优先 + 最近）。
final memoriesProvider =
    StateNotifierProvider<MemoriesNotifier, List<MemoryItem>>(
  (ref) => MemoriesNotifier(ref.watch(appDatabaseProvider).memoryRepository),
);

/// 全部记忆（记忆库管理页使用）。
final allMemoriesProvider = FutureProvider<List<MemoryItem>>(
  (ref) => ref.watch(appDatabaseProvider).memoryRepository.listAll(),
);

/// 指定会话的记忆列表（会话详情面板使用，置顶优先 + 最近）。
final conversationMemoriesProvider =
    FutureProvider.family<List<MemoryItem>, int>(
  (ref, conversationId) =>
      ref.watch(appDatabaseProvider).memoryRepository.listByConversation(conversationId),
);

/// 记忆搜索结果（记忆库管理页搜索框使用）。
final memorySearchProvider = FutureProvider.family<List<MemoryItem>, String>(
  (ref, keyword) =>
      ref.watch(appDatabaseProvider).memoryRepository.search(keyword),
);

class MemoriesNotifier extends StateNotifier<List<MemoryItem>> {
  MemoriesNotifier(this._repository) : super(const []);

  final MemoryRepository _repository;

  /// 公开只读快照（页面 dispose 后仍可读取当前状态）。
  List<MemoryItem> get snapshot => state;

  Future<void> loadForConversation(int conversationId) async {
    state = await _repository.listByConversation(conversationId);
  }

  Future<void> add(MemoryItem item) async {
    final id = await _repository.insert(item);
    state = [...state, item.copyWith(id: id)];
  }

  Future<void> update(MemoryItem item) async {
    await _repository.update(item);
    state = [
      for (final m in state)
        if (m.id == item.id) item else m,
    ];
  }

  Future<void> remove(int id) async {
    await _repository.delete(id);
    state = state.where((m) => m.id != id).toList();
  }

  /// 切换置顶状态。
  Future<void> togglePinned(MemoryItem item) async {
    await update(item.copyWith(pinned: !item.pinned, updatedAt: DateTime.now().millisecondsSinceEpoch));
  }
}
