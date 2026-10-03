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

  /// 从数据库加载全部配置。
  Future<void> load() async {
    state = await _repository.getAll();
  }

  /// 新增配置；[apiKey] 写入安全存储，数据库仅存引用键。
  ///
  /// 先 insert 拿到真实 id，再以 `api_key:<id>` 为引用键写入安全存储并回填，
  /// 避免占位引用键与实际密钥错位。本地免密钥服务（如 Ollama）允许
  /// [apiKey] 为空：仅落库、不写安全存储。
  Future<void> add(ApiConfig config, String apiKey) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _repository.insert(
      config.copyWith(createdAt: now, updatedAt: now),
    );
    final refKey = ApiKeyStore.refKeyFor(id);
    if (apiKey.isNotEmpty) {
      await ApiKeyStore.write(refKey, apiKey);
    }
    await _repository.update(
      config.copyWith(id: id, apiKeyRef: refKey, createdAt: now, updatedAt: now),
    );
    await load();
  }

  /// 更新配置；[apiKey] 非空时同时更新安全存储。
  Future<void> update(ApiConfig config, {String? apiKey}) async {
    if (apiKey != null && apiKey.isNotEmpty) {
      await ApiKeyStore.write(config.apiKeyRef, apiKey);
    }
    await _repository.update(config.copyWith(updatedAt: DateTime.now().millisecondsSinceEpoch));
    await load();
  }

  /// 删除配置（同时清理安全存储中的密钥）。
  Future<void> remove(ApiConfig config) async {
    await _repository.delete(config.id!);
    await ApiKeyStore.delete(config.apiKeyRef);
    await load();
  }
}
