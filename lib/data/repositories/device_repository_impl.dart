import '../../domain/models/sync_device.dart';
import '../../domain/repositories/device_repository.dart';
import '../database/app_database.dart';

/// 设备仓储的 SQLite 实现。
class DeviceRepositoryImpl implements DeviceRepository {
  DeviceRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<SyncDevice?> findByDeviceId(String deviceId) async {
    final rows = await _appDatabase.db.query(
      'devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SyncDevice.fromMap(rows.first);
  }

  @override
  Future<int> insert(SyncDevice device) async {
    return _appDatabase.db.insert('devices', device.toMap()..remove('id'));
  }

  @override
  Future<void> update(SyncDevice device) async {
    await _appDatabase.db.update(
      'devices',
      device.toMap(),
      where: 'device_id = ?',
      whereArgs: [device.deviceId],
    );
  }

  @override
  Future<List<SyncDevice>> listTrusted() async {
    final rows = await _appDatabase.db.query(
      'devices',
      where: 'is_trusted = 1',
      orderBy: 'created_at ASC',
    );
    return rows.map(SyncDevice.fromMap).toList();
  }

  @override
  Future<void> removeByDeviceId(String deviceId) async {
    await _appDatabase.db.delete(
      'devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }

  @override
  Future<void> touch(String deviceId, int now) async {
    await _appDatabase.db.update(
      'devices',
      {'last_seen_at': now},
      where: 'device_id = ?',
      whereArgs: [deviceId],
    );
  }
}
