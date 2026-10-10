import '../../domain/models/api_config.dart';
import '../../domain/repositories/api_config_repository.dart';
import '../database/app_database.dart';

/// API 配置仓储的 SQLite 实现。
class ApiConfigRepositoryImpl implements ApiConfigRepository {
  ApiConfigRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<ApiConfig>> getAll() async {
    // R22：收藏项置顶（favorite DESC），其余按更新时间倒序。
    final rows = await _appDatabase.db.query(
      'api_configs',
      orderBy: 'favorite DESC, updated_at DESC',
    );
    return rows.map(ApiConfig.fromMap).toList();
  }

  @override
  Future<ApiConfig?> getById(int id) async {
    final rows = await _appDatabase.db.query(
      'api_configs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ApiConfig.fromMap(rows.first);
  }

  @override
  Future<int> insert(ApiConfig config) async {
    return _appDatabase.db.insert('api_configs', config.toMap()..remove('id'));
  }

  @override
  Future<void> update(ApiConfig config) async {
    await _appDatabase.db.update(
      'api_configs',
      config.toMap(),
      where: 'id = ?',
      whereArgs: [config.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _appDatabase.db.delete('api_configs', where: 'id = ?', whereArgs: [id]);
  }
}
