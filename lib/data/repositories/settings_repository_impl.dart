import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/settings_repository.dart';
import '../database/app_database.dart';

/// 设置仓储的 SQLite 实现（PRD 6.1 `settings` 表 key-value）。
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<String?> getValue(String key) async {
    final rows = await _appDatabase.db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  @override
  Future<void> setValue(String key, String value) async {
    await _appDatabase.db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<Map<String, String>> getAll() async {
    final rows = await _appDatabase.db.query('settings');
    return {
      for (final row in rows) row['key'] as String: row['value'] as String,
    };
  }

  @override
  Future<void> remove(String key) async {
    await _appDatabase.db.delete('settings', where: 'key = ?', whereArgs: [key]);
  }

  @override
  Future<double> getDouble(String key, double fallback) async {
    final raw = await getValue(key);
    if (raw == null) return fallback;
    return double.tryParse(raw) ?? fallback;
  }

  @override
  Future<int> getInt(String key, int fallback) async {
    final raw = await getValue(key);
    if (raw == null) return fallback;
    return int.tryParse(raw) ?? fallback;
  }
}
