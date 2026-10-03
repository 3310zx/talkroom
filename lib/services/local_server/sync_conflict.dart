/// 双端写冲突裁决（PRD 7.4：时间戳 + 设备优先级「电脑 > 手机」）。
///
/// 服务器在接收手机端批量消息时，按 (客户端时间戳, 设备优先级) 排序后
/// 依次插入，使自增 `server_id` 即权威顺序，客户端以 `server_id` 游标增量拉取。
class SyncConflict {
  /// 设备优先级：server(电脑) > client(手机)。同为 client 时按 deviceId 字典序
  /// 保证稳定排序（避免抖动）。
  static int devicePriority(String deviceType) =>
      deviceType == 'server' ? 0 : 1;

  /// 批量上传消息的服务端插入顺序。
  /// [items] 为 {deviceType, createdAt, deviceId} 的原始顺序，返回按权威顺序排序后的列表。
  static List<T> sortForServerInsert<T>(
    List<T> items, {
    required int Function(T) clientTsOf,
    required String Function(T) deviceIdOf,
    required String Function(T) deviceTypeOf,
  }) {
    final list = List<T>.from(items);
    list.sort((a, b) {
      final ts = clientTsOf(a).compareTo(clientTsOf(b));
      if (ts != 0) return ts;
      final pa = devicePriority(deviceTypeOf(a)).compareTo(devicePriority(deviceTypeOf(b)));
      if (pa != 0) return pa;
      return deviceIdOf(a).compareTo(deviceIdOf(b));
    });
    return list;
  }

  /// 判断 [incoming] 是否应覆盖本地已有消息（冲突裁决）。
  /// 规则：时间戳新的胜；时间戳相同则设备优先级高（电脑 > 手机）的胜；
  /// 仍相同则以服务端 server_id 为准（serverId 大者胜，即服务器顺序靠后的覆盖）。
  static bool shouldServerWin({
    required int incomingUpdatedAt,
    required int localUpdatedAt,
    required int incomingPriority,
    required int localPriority,
    required int incomingServerId,
    required int localServerId,
  }) {
    if (incomingUpdatedAt != localUpdatedAt) {
      return incomingUpdatedAt > localUpdatedAt;
    }
    if (incomingPriority != localPriority) {
      return incomingPriority < localPriority;
    }
    return incomingServerId >= localServerId;
  }
}
