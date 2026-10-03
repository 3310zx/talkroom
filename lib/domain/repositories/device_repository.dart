import '../models/sync_device.dart';

/// 已配对设备仓储接口（PRD 第 7 章 `devices` 表）。
abstract class DeviceRepository {
  Future<SyncDevice?> findByDeviceId(String deviceId);
  Future<int> insert(SyncDevice device);
  Future<void> update(SyncDevice device);

  /// 已信任（配对成功）设备列表，按配对时间升序
  Future<List<SyncDevice>> listTrusted();

  /// 移除设备（踢出白名单，需重新配对）
  Future<void> removeByDeviceId(String deviceId);

  /// 更新设备最后活跃时间
  Future<void> touch(String deviceId, int now);
}
