import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/secure_storage/api_key_store.dart';
import '../../domain/models/api_config.dart';
import '../../domain/repositories/api_config_repository.dart';
import 'database_provider.dart';

/// API 配置列表状态（PRD 2.2：apiConfigsProvider）。
final apiConfigsProvider =
    StateNotifierProvider<ApiConfigsNotifier, List<ApiConfig>>(
  (ref) => ApiConfigsNotifier(ref.watch(appDatabaseProvider).apiConfigRepository),
);

class ApiConfigsNotifier extends StateNotifier<List<ApiConfig>> {
  ApiConfigsNotifier(this._repository) : super(const []);

  final ApiConfigRepository _repository;

  /// 是否已成功从数据库完成至少一次加载。
  ///
  /// 用于区分「确实没有配置」与「尚未加载/加载失败」，避免首页空态
  /// 把后两者误显示为「尚未添加 API 配置」。
  bool _loaded = false;
  bool get loaded => _loaded;

  /// 从数据库加载全部配置。
  ///
  /// 失败时保留当前状态并记录日志：既避免异常中断 HomePage 的启动链
  /// （会话/设置/主动消息等后续加载），也避免 UI 长期停留在错误空态。
  Future<void> load() async {
    try {
      state = await _repository.getAll();
      _loaded = true;
    } catch (e, st) {
      debugPrint('ApiConfigsNotifier.load failed: $e\n$st');
    }
  }

  /// 新增配置；[apiKey] 写入安全存储，数据库仅存引用键。
  ///
  /// 先 insert 拿到真实 id，再以 `api_key:<id>` 为引用键写入安全存储并回填，
  /// 避免占位引用键与实际密钥错位。本地免密钥服务（如 Ollama）允许
  /// [apiKey] 为空：仅落库、不写安全存储。
  ///
  /// M2：全程 try/catch，任一步失败即执行事务补偿 —— 回滚已插入的数据库记录
  /// 与已写入的密钥，绝不留下"有记录无密钥 / 有密钥无记录"的半成品。
  Future<void> add(ApiConfig config, String apiKey) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    var insertedId = -1;
    var keyWritten = false;
    try {
      insertedId = await _repository.insert(
        config.copyWith(createdAt: now, updatedAt: now),
      );
      final refKey = ApiKeyStore.refKeyFor(insertedId);
      if (apiKey.isNotEmpty) {
        await ApiKeyStore.write(refKey, apiKey);
        keyWritten = true;
      }
      await _repository.update(
        config.copyWith(
            id: insertedId, apiKeyRef: refKey, createdAt: now, updatedAt: now),
      );
      await load();
    } catch (e, st) {
      debugPrint('ApiConfigsNotifier.add failed: $e\n$st');
      await _rollbackInsert(insertedId, keyWritten);
      rethrow;
    }
  }

  /// M2：新增配置失败时的事务补偿 —— 删除已插入的记录与已写入的密钥。
  Future<void> _rollbackInsert(int id, bool keyWritten) async {
    if (id < 0) return;
    try {
      if (keyWritten) {
        await ApiKeyStore.delete(ApiKeyStore.refKeyFor(id));
      }
      await _repository.delete(id);
      await load();
    } catch (e, st) {
      debugPrint('ApiConfigsNotifier rollback failed: $e\n$st');
    }
  }

  /// 更新配置；[apiKey] 非空时同时更新安全存储。
  ///
  /// M2：写入新密钥前先缓存旧值，若数据库更新失败则尽力恢复旧密钥，
  /// 避免安全存储与数据库指向不一致；失败统一记录并向上抛出。
  Future<void> update(ApiConfig config, {String? apiKey}) async {
    final hadKeyWrite = apiKey != null && apiKey.isNotEmpty;
    var previousKey = '';
    try {
      if (hadKeyWrite) {
        previousKey = await ApiKeyStore.read(config.apiKeyRef) ?? '';
        await ApiKeyStore.write(config.apiKeyRef, apiKey);
      }
      await _repository.update(
        config.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch),
      );
      await load();
    } catch (e, st) {
      debugPrint('ApiConfigsNotifier.update failed: $e\n$st');
      if (hadKeyWrite) {
        try {
          if (previousKey.isEmpty) {
            await ApiKeyStore.delete(config.apiKeyRef);
          } else {
            await ApiKeyStore.write(config.apiKeyRef, previousKey);
          }
        } catch (rollbackErr, rollbackSt) {
          debugPrint(
              'ApiConfigsNotifier.update rollback failed: $rollbackErr\n$rollbackSt');
        }
      }
      rethrow;
    }
  }

  /// 删除配置（同时清理安全存储中的密钥）。
  ///
  /// M2：先删数据库记录、再删密钥，避免"记录在但密钥已丢"；密钥清理失败
  /// 重试一次，仍失败仅记录（孤儿密钥无业务影响），不会中断删除流程。
  Future<void> remove(ApiConfig config) async {
    try {
      await _repository.delete(config.id!);
      try {
        await ApiKeyStore.delete(config.apiKeyRef);
      } catch (keyErr, keySt) {
        debugPrint(
            'ApiConfigsNotifier.remove key delete failed: $keyErr\n$keySt');
        try {
          await ApiKeyStore.delete(config.apiKeyRef);
        } catch (_) {}
      }
      await load();
    } catch (e, st) {
      debugPrint('ApiConfigsNotifier.remove failed: $e\n$st');
      rethrow;
    }
  }

  /// R22：切换服务商收藏标记。收藏项在列表顶部展示（仓储按
  /// favorite DESC, updated_at DESC 排序），便于快速切换。
  Future<void> toggleFavorite(ApiConfig config) async {
    try {
      await _repository.update(
        config.copyWith(favorite: !config.favorite),
      );
      await load();
    } catch (e, st) {
      debugPrint('ApiConfigsNotifier.toggleFavorite failed: $e\n$st');
      rethrow;
    }
  }
}
