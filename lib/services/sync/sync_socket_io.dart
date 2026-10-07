import 'dart:async';
import 'dart:io';

import 'sync_socket.dart';

/// dart:io WebSocket 实现（移动端 / 桌面端）。
Future<SyncSocketConnection> connectSyncSocket(String url) async {
  final ws = await WebSocket.connect(url);
  return _IoSyncSocket(ws);
}

class _IoSyncSocket implements SyncSocketConnection {
  _IoSyncSocket(this._ws);

  final WebSocket _ws;
  final _controller = StreamController<Object?>.broadcast(sync: true);
  StreamSubscription<dynamic>? _sub;
  bool _closed = false;

  @override
  bool get isOpen => !_closed && _ws.readyState == WebSocket.open;

  @override
  Stream<Object?> get messages {
    _sub ??= _ws.listen(
      (data) {
        if (!_controller.isClosed) _controller.add(data);
      },
      onDone: () {
        if (!_controller.isClosed) _controller.close();
      },
      onError: (Object e, StackTrace st) {
        if (!_controller.isClosed) _controller.addError(e, st);
      },
      cancelOnError: true,
    );
    return _controller.stream;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    try {
      await _ws.close();
    } catch (_) {
      // 已关闭的连接忽略
    }
    if (!_controller.isClosed) await _controller.close();
  }
}
