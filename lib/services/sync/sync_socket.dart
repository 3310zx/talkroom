import 'sync_socket_io.dart'
    if (dart.library.html) 'sync_socket_web.dart' as impl;

/// 跨平台 WebSocket 客户端连接（局域网同步实时通道）。
///
/// - IO 平台：dart:io WebSocket（Android / iOS / 桌面端）；
/// - Web 平台：浏览器原生 WebSocket（dart:html）。
Future<SyncSocketConnection> connectSyncSocket(String url) =>
    impl.connectSyncSocket(url);

/// WebSocket 连接抽象：统一 listen / close 语义，屏蔽平台差异。
abstract class SyncSocketConnection {
  bool get isOpen;

  Stream<Object?> get messages;

  Future<void> close();
}
