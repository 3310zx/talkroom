import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../domain/models/message.dart';
import '../../domain/models/sync_cursor.dart';
import '../../domain/models/sync_device.dart';
import '../../domain/repositories/device_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/sync_cursor_repository.dart';
import '../sync/sync_json.dart';
import 'pair_guard.dart';
import 'sync_conflict.dart';

/// 局域网本地服务器（PRD 第 7 章，电脑端权威源）。
///
/// 提供：
/// - GET  /health        健康检查
/// - GET  /v1/info       服务器信息（局域网 IP / server device id / 配对状态）
/// - POST /v1/pair       设备配对（6 位配对码 + 防猜锁定，成功加入白名单）
/// - POST /v1/sync       增量同步（基于各会话 server_id 游标）
/// - POST /v1/messages   手机端批量上传新消息（服务端裁决冲突并分配 server_id）
/// - WS   /v1/ws         实时推送通道（新消息 / 主动消息即时广播给在线客户端）
class LocalServerService {
  LocalServerService({
    required SettingsRepository settings,
    required DeviceRepository devices,
    required MessageRepository messages,
    required SyncCursorRepository cursors,
    void Function(ChatMessage message)? onMessagePersisted,
  })  : _settings = settings,
        _devices = devices,
        _messages = messages,
        _cursors = cursors,
        _onMessagePersisted = onMessagePersisted;

  final SettingsRepository _settings;
  final DeviceRepository _devices;
  final MessageRepository _messages;
  final SyncCursorRepository _cursors;
  final void Function(ChatMessage message)? _onMessagePersisted;

  HttpServer? _httpServer;
  final _wsClients = <WebSocket>{};
  final _pairGuard = PairGuard();
  bool _stopping = false;
  Timer? _finalizeTimer;

  /// 电脑端（权威源）设备 id；首次调用时生成并持久化。
  Future<String> getOrCreateServerDeviceId() async {
    final existing = await _settings.getValue(AppConstants.settingServerDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = const Uuid().v4();
    await _settings.setValue(AppConstants.settingServerDeviceId, id);
    return id;
  }

  /// 生成/重新生成一次性 6 位配对码（同时清空防猜状态）。
  Future<String> ensurePairCode() async {
    final code = PairGuard.generateCode();
    await _settings.setValue(AppConstants.settingServerPairCode, code);
    await _settings.setValue(AppConstants.settingServerPairFailCount, '0');
    await _settings.setValue(AppConstants.settingServerPairLockUntil, '0');
    _pairGuard.reset();
    return code;
  }

  Future<String?> getPairCode() =>
      _settings.getValue(AppConstants.settingServerPairCode);

  Future<Map<String, Object?>> pairInfo() async {
    final code = await getPairCode();
    final failCount =
        await _settings.getInt(AppConstants.settingServerPairFailCount, 0);
    final lockUntil =
        await _settings.getInt(AppConstants.settingServerPairLockUntil, 0);
    final guard = PairGuard(failCount: failCount, lockUntil: lockUntil);
    final locked = guard.isLocked;
    return {
      'server_device_id': await getOrCreateServerDeviceId(),
      'pair_code_set': code != null && code.isNotEmpty,
      'pair_locked': locked,
      'pair_remaining_lock_ms': locked ? guard.remainingLockMs : 0,
      'paired_devices': (await _devices.listTrusted()).length,
    };
  }

  /// 端口探测：从 [startPort] 开始尝试绑定，找到空闲端口返回。
  Future<int> probePort({
    int startPort = AppConstants.defaultServerPort,
    int maxAttempts = AppConstants.maxPortProbeAttempts,
  }) async {
    for (var i = 0; i < maxAttempts; i++) {
      final port = startPort + i;
      final ok = await _isPortAvailable(port);
      if (ok) return port;
    }
    throw StateError('端口 $startPort~${startPort + maxAttempts - 1} 均被占用，无法启动本地服务器。');
  }

  Future<bool> _isPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      return true;
    } on SocketException {
      return false;
    } finally {
      await socket?.close();
    }
  }

  /// 获取本机局域网 IPv4 地址列表（用于展示，供客户端连接）。
  Future<List<String>> getLanIpv4Addresses() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip == '127.0.0.1' || ip.startsWith('169.254.')) continue;
          result.add(ip);
        }
      }
    } on SocketException {
      // 某些平台无权限枚举网卡时返回空列表，调用方需提示用户。
    }
    return result.toSet().toList();
  }

  bool get isRunning => _httpServer != null;

  int get port => _httpServer?.port ?? 0;

  /// 启动服务器（HTTP + WebSocket 同一端口）。
  Future<void> start({int port = AppConstants.defaultServerPort}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _httpServer = server;
    _stopping = false;
    server.listen(_onRequest);
    await getOrCreateServerDeviceId();
    // 同步周期兜底：电脑端新消息落库后由本定时器固化 server_id 并广播，
    // 保证不依赖 UI 操作也能被手机端增量拉取 / 实时推送。
    _finalizeTimer?.cancel();
    _finalizeTimer = Timer.periodic(
      const Duration(seconds: AppConstants.serverFinalizeIntervalSeconds),
      (_) async {
        try {
          await finalizeLocalMessages();
        } catch (_) {
          // 单次固化失败不影响服务器运行，下个周期重试
        }
      },
    );
  }

  Future<void> stop() async {
    _stopping = true;
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
    for (final ws in List<WebSocket>.from(_wsClients)) {
      await ws.close(WebSocketStatus.normalClosure);
    }
    _wsClients.clear();
    await _httpServer?.close(force: true);
    _httpServer = null;
  }

  Future<void> _onRequest(HttpRequest req) async {
    // WebSocket 通道先行接管
    if (req.uri.path == '/v1/ws' && req.method == 'GET') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        _registerWs(ws);
      } catch (_) {
        // 升级失败直接关闭即可
      }
      return;
    }

    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));

    try {
      final shelfReq = Request(
        req.method,
        req.uri,
        body: req,
        headers: headers,
      );
      final res = await _handler(shelfReq);
      req.response.statusCode = res.statusCode;
      res.headers.forEach((k, v) {
        req.response.headers.set(k, v);
      });
      req.response.write(await res.readAsString());
      await req.response.close();
    } catch (e) {
      if (!_stopping) {
        req.response.statusCode = HttpStatus.internalServerError;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode({'error': 'internal_error', 'detail': '$e'}));
        await req.response.close();
      }
    }
  }

  late final _handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  late final Router _router = Router()
    ..get('/health', _healthHandler)
    ..get('/v1/info', _infoHandler)
    ..post('/v1/pair', _pairHandler)
    ..post('/v1/sync', _syncHandler)
    ..post('/v1/messages', _messagesHandler);

  Response _healthHandler(Request request) {
    return Response.ok(
      '{"status":"ok","service":"llm_chat_local_server"}',
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _infoHandler(Request request) async {
    final info = await pairInfo();
    final ips = await getLanIpv4Addresses();
    return _jsonResponse({
      'status': 'ok',
      'service': 'llm_chat_local_server',
      'lan_ips': ips,
      ...info,
    });
  }

  // ---- 配对 ----

  Future<Response> _pairHandler(Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error('bad_request', 'JSON 解析失败', 400);

    final code = await getPairCode();
    final failCount = await _settings.getInt(AppConstants.settingServerPairFailCount, 0);
    final lockUntil = await _settings.getInt(AppConstants.settingServerPairLockUntil, 0);
    final guard = PairGuard(failCount: failCount, lockUntil: lockUntil);
    final result = guard.check(expectedCode: code, input: body['pair_code'] as String? ?? '');
    // 持久化防猜状态
    await _settings.setValue(AppConstants.settingServerPairFailCount, '${guard.failCount}');
    await _settings.setValue(AppConstants.settingServerPairLockUntil, '${guard.lockUntil}');

    if (result == PairCheckResult.locked) {
      return _error('pair_locked', '尝试次数过多，配对码已锁定，请 10 分钟后重试或重新生成配对码。', 429);
    }
    if (result != PairCheckResult.ok) {
      final remaining = guard.isLocked
          ? guard.remainingLockMs
          : AppConstants.pairMaxFailures - guard.failCount;
      return _error('pair_invalid', '配对码错误，剩余 $remaining 次机会。', 401);
    }

    // 配对成功：一次性配对码即失效
    await _settings.setValue(AppConstants.settingServerPairCode, '');

    final deviceName = (body['device_name'] as String? ?? '手机').trim();
    final deviceType = body['device_type'] as String? ?? 'client';
    final now = DateTime.now().millisecondsSinceEpoch;
    final device = SyncDevice(
      deviceId: const Uuid().v4(),
      deviceName: deviceName.isEmpty ? '手机' : deviceName,
      deviceType: deviceType == 'server' ? 'server' : 'client',
      token: const Uuid().v4().replaceAll('-', ''),
      isTrusted: true,
      lastSeenAt: now,
      createdAt: now,
    );
    await _devices.insert(device);
    return _jsonResponse({
      'ok': true,
      'device_id': device.deviceId,
      'device_token': device.token,
      'server_device_id': await getOrCreateServerDeviceId(),
    });
  }

  // ---- 同步 ----

  Future<Response> _syncHandler(Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error('bad_request', 'JSON 解析失败', 400);
    final device = await _authenticate(body);
    if (device == null) return _error('unauthorized', '设备未授权，请重新配对。', 401);
    await _devices.touch(device.deviceId, DateTime.now().millisecondsSinceEpoch);

    final cursors = <int, int>{};
    final rawCursors = body['cursors'];
    if (rawCursors is Map) {
      rawCursors.forEach((k, v) {
        final convId = int.tryParse('$k');
        final cursor = int.tryParse('$v');
        if (convId != null && cursor != null) cursors[convId] = cursor;
      });
    }

    final messagesOut = <Map<String, Object?>>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in cursors.entries) {
      final after = entry.value;
      final batch = await _messages.listByServerIdAfter(
        conversationId: entry.key,
        afterServerId: after,
        limit: AppConstants.syncBatchLimit,
      );
      var lastServerId = after;
      for (final m in batch) {
        messagesOut.add(toSyncJson(m));
        if ((m.serverId ?? 0) > lastServerId) lastServerId = m.serverId ?? 0;
      }
      await _cursors.setCursor(SyncCursor(
        deviceId: device.deviceId,
        conversationId: entry.key,
        lastSyncedMsgId: lastServerId,
        updatedAt: now,
      ));
    }

    return _jsonResponse({
      'ok': true,
      'messages': messagesOut,
      'server_time': now,
    });
  }

  // ---- 手机端批量上传 ----

  Future<Response> _messagesHandler(Request request) async {
    final body = await _readJson(request);
    if (body == null) return _error('bad_request', 'JSON 解析失败', 400);
    final device = await _authenticate(body);
    if (device == null) return _error('unauthorized', '设备未授权，请重新配对。', 401);
    await _devices.touch(device.deviceId, DateTime.now().millisecondsSinceEpoch);

    final raw = body['messages'];
    if (raw is! List) return _error('bad_request', 'messages 必须为数组', 400);

    // 先做幂等过滤：同设备同客户端时间戳的已存在消息跳过
    final incoming = <ChatMessage>[];
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in raw) {
      if (item is! Map) continue;
      final m = fromSyncJson(item.cast<String, Object?>());
      if (m.createdAt <= 0) continue;
      final dup = await _messages.existsByDeviceAndClientTs(device.deviceId, m.createdAt);
      if (dup) continue;
      // 服务端统一使用白名单设备的 device_id，避免伪造
      incoming.add(m.copyWith(deviceId: device.deviceId, updatedAt: now));
    }

    if (incoming.isEmpty) {
      return _jsonResponse({'ok': true, 'accepted': 0, 'assigned': const []});
    }

    // 冲突裁决：时间戳升序；相同时电脑(server)优先（手机端全为 client，按 deviceId 稳定排序）
    final ordered = SyncConflict.sortForServerInsert(
      incoming,
      clientTsOf: (m) => m.createdAt,
      deviceIdOf: (m) => m.deviceId ?? '',
      deviceTypeOf: (m) => 'client',
    );

    final inserted = await _messages.insertWithServerIds(ordered);
    final assigned = inserted
        .map((m) => {
              'client_ts': m.createdAt,
              'server_id': m.serverId,
            })
        .toList();

    for (final m in inserted) {
      _onMessagePersisted?.call(m);
      await _broadcast({'type': 'message', 'message': toSyncJson(m)});
    }

    return _jsonResponse({
      'ok': true,
      'accepted': inserted.length,
      'assigned': assigned,
    });
  }

  // ---- 电脑端本地消息：分配 server_id 供增量同步 ----

  /// 为电脑端本地产生的待同步消息分配 server_id（权威库落库）。
  /// 调用时机：电脑端新消息落库后 / 同步周期内兜底调用。
  Future<List<ChatMessage>> finalizeLocalMessages() async {
    final finalized = await _messages.finalizeLocalMessages();
    for (final m in finalized) {
      _onMessagePersisted?.call(m);
      await _broadcast({'type': 'message', 'message': toSyncJson(m)});
    }
    return finalized;
  }

  /// 主动向所有在线客户端推送消息（主动消息完成后可调用）。
  Future<void> broadcastNewMessage(ChatMessage message) async {
    await _broadcast({'type': 'message', 'message': toSyncJson(message)});
  }

  // ---- WebSocket ----

  void _registerWs(WebSocket ws) {
    _wsClients.add(ws);
    ws.listen(
      (_) {
        // 客户端通常不发上行数据；忽略内容
      },
      onDone: () => _wsClients.remove(ws),
      onError: (_) => _wsClients.remove(ws),
      cancelOnError: true,
    );
  }

  Future<void> _broadcast(Map<String, Object?> payload) async {
    final text = jsonEncode(payload);
    for (final ws in List<WebSocket>.from(_wsClients)) {
      if (ws.readyState == WebSocket.open) {
        ws.add(text);
      } else {
        _wsClients.remove(ws);
      }
    }
  }

  // ---- 辅助 ----

  Future<Map<String, dynamic>?> _readJson(Request request) async {
    try {
      final text = await request.readAsString();
      if (text.isEmpty) return {};
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<SyncDevice?> _authenticate(Map<String, dynamic> body) async {
    final deviceId = body['device_id'] as String?;
    final token = body['device_token'] as String?;
    if (deviceId == null || token == null) return null;
    final device = await _devices.findByDeviceId(deviceId);
    if (device == null || !device.isTrusted || device.token != token) return null;
    return device;
  }

  Response _jsonResponse(Map<String, Object?> data) {
    return Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _error(String code, String message, int status) {
    return Response(
      status,
      body: jsonEncode({'error': code, 'message': message}),
      headers: {'content-type': 'application/json'},
    );
  }
}
