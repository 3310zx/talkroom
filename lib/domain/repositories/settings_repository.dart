/// 全局/会话参数设置仓储接口（PRD 6.1 `settings` 表，key-value）。
///
/// 当前 M0 骨架使用 SQLite `settings` 表实现；PRD 2.3 提到 Hive 作为轻量缓存，
/// 已在本项目初始化（lib/main.dart），可作为 P1 的替代/叠加方案。
abstract class SettingsRepository {
  Future<String?> getValue(String key);
  Future<void> setValue(String key, String value);
  Future<Map<String, String>> getAll();
  Future<void> remove(String key);

  /// 便捷读取数值型参数
  Future<double> getDouble(String key, double fallback);
  Future<int> getInt(String key, int fallback);
}
