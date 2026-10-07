import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

import 'sync_socket.dart';

/// 浏览器原生 WebSocket 实现（Flutter Web，基于 package:web）。
Future<SyncSocketConnection> connectSyncSocket(String url) {
  final ws = web.WebSocket(url);
  final conn = _WebSyncSocket(ws);
  return conn._open.then((_) => conn);
}

class _WebSyncSocket implements SyncSocketConnection {
  _WebSyncSocket(this._ws) {
    web.EventStreamProviders.openEvent.forTarget(_ws).listen((_) {
      if (!_openCompleter.isCompleted) _openCompleter.complete();
    });
    web.EventStreamProviders.errorEvent.forTarget(_ws).listen((_) {
      if (!_openCompleter.isCompleted) {
        _openCompleter.completeError(StateError('WebSocket 连接失败'));
      }
    });
    web.EventStreamProviders.messageEvent.forTarget(_ws).listen((e) {
      if (_controller.isClosed) return;
      final data = e.data;
      if (data is JSString) {
        _controller.add(data.toDart);
      } else if (data != null) {
        // 二进制帧：同步协议为 JSON 文本，忽略非文本数据
        _controller.add(data.toString());
      }
    });
    web.EventStreamProviders.closeEvent.forTarget(_ws).listen((_) {
      if (!_controller.isClosed) _controller.close();
    });
  }

  final web.WebSocket _ws;
  final _openCompleter = Completer<void>();
  final _controller = StreamController<Object?>.broadcast(sync: true);

  Future<void> get _open => _openCompleter.future;

  @override
  bool get isOpen => _ws.readyState == web.WebSocket.OPEN;

  @override
  Stream<Object?> get messages => _controller.stream;

  @override
  Future<void> close() async {
    try {
      _ws.close();
    } catch (_) {
      // 已关闭的连接忽略
    }
    if (!_controller.isClosed) await _controller.close();
  }
}
