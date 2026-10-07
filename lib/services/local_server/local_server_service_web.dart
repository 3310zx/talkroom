import '../../core/constants.dart';
import '../../domain/models/message.dart';
import '../../domain/repositories/device_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/sync_cursor_repository.dart';

/// Web 平台本地服务器 stub：浏览器沙箱无法监听端口，全部操作明确失败。
///
/// 该类型仅保证 Flutter Web 编译通过；Web 端作为同步客户端，
/// 「本地服务器」入口已在 UI 层隐藏。
class LocalServerService {
  LocalServerService({
    required SettingsRepository settings,
    required DeviceRepository devices,
    required MessageRepository messages,
    required SyncCursorRepository cursors,
    void Function(ChatMessage message)? onMessagePersisted,
  });

  Future<String> getOrCreateServerDeviceId() =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  Future<String> ensurePairCode() =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  Future<String?> getPairCode() =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  Future<Map<String, Object?>> pairInfo() =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  Future<int> probePort({
    int startPort = AppConstants.defaultServerPort,
    int maxAttempts = AppConstants.maxPortProbeAttempts,
  }) =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  Future<List<String>> getLanIpv4Addresses() =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  bool get isRunning => false;

  int get port => 0;

  Future<void> start({int port = AppConstants.defaultServerPort}) =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  Future<void> stop() async {}

  Future<List<ChatMessage>> finalizeLocalMessages() =>
      throw UnsupportedError('Web 平台不支持本地服务器');

  Future<void> broadcastNewMessage(ChatMessage message) async {}
}
