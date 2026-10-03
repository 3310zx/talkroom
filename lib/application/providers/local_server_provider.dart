import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/sync_device.dart';
import '../../services/local_server/local_server_service.dart';
import 'database_provider.dart';

/// 本地服务器服务实例（PRD 第 7 章，电脑端权威源）。
final localServerServiceProvider = Provider<LocalServerService>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    return LocalServerService(
      settings: db.settingsRepository,
      devices: db.deviceRepository,
      messages: db.messageRepository,
      cursors: db.syncCursorRepository,
    );
  },
);

/// 已配对设备列表（服务器管理页展示用）。
final localServerDevicesProvider =
    FutureProvider<List<SyncDevice>>((ref) async {
  return ref.watch(appDatabaseProvider).deviceRepository.listTrusted();
});

/// 本地服务器运行状态：null=未启动。
final localServerStatusProvider =
    StateProvider<LocalServerState?>((ref) => null);

class LocalServerState {
  const LocalServerState({
    required this.port,
    required this.lanIps,
    this.startedAt,
    this.pairCode,
    this.serverDeviceId,
    this.pairedDevices = 0,
    this.pairLocked = false,
    this.pairRemainingLockMs = 0,
  });

  final int port;
  final List<String> lanIps;
  final DateTime? startedAt;

  /// 当前配对码（为空表示尚未生成）
  final String? pairCode;

  /// 电脑端（权威源）设备 id
  final String? serverDeviceId;
  final int pairedDevices;
  final bool pairLocked;
  final int pairRemainingLockMs;

  LocalServerState copyWith({
    int? port,
    List<String>? lanIps,
    DateTime? startedAt,
    String? pairCode,
    String? serverDeviceId,
    int? pairedDevices,
    bool? pairLocked,
    int? pairRemainingLockMs,
  }) {
    return LocalServerState(
      port: port ?? this.port,
      lanIps: lanIps ?? this.lanIps,
      startedAt: startedAt ?? this.startedAt,
      pairCode: pairCode ?? this.pairCode,
      serverDeviceId: serverDeviceId ?? this.serverDeviceId,
      pairedDevices: pairedDevices ?? this.pairedDevices,
      pairLocked: pairLocked ?? this.pairLocked,
      pairRemainingLockMs: pairRemainingLockMs ?? this.pairRemainingLockMs,
    );
  }
}
