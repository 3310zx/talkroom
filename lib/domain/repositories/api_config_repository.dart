import '../models/api_config.dart';

/// API 配置仓储接口（数据层由 SQLite 实现）。
abstract class ApiConfigRepository {
  Future<List<ApiConfig>> getAll();
  Future<ApiConfig?> getById(int id);
  Future<int> insert(ApiConfig config);
  Future<void> update(ApiConfig config);
  Future<void> delete(int id);
}
