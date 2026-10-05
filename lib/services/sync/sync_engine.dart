import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../domain/models/message.dart';
import '../../domain/models/sync_cursor.dart';
import '../../domain/repositories/conversation_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/sync_cursor_repository.dart';
import 'sync_json.dart';

/// 客户端同步引擎（PRD 第 7 章）。
///
/// - 电脑端（权威源，[isServerRole]=true）：只拉取手机端新消息并刷新本地缓存；
///   本地新消息通过 LocalServerService.finalizeLocalMessages 分配 server_id。
/// - 手机端（[isServerRole]=false）：拉增量落本地缓存；本机新消息写入本地队列，
///   联网后按 server_id 增量补拉；前台 WebSocket 实时 + 后台轮询兜底。
class SyncEngine {
  SyncEngine({
    required SettingsRepository settings,
    required MessageRepository messages,
    required ConversationRepository conversations,
    required SyncCursorRepository cursors,
    required this.isServerRole,
    void Function(ChatMessage message)? onRemoteMessage,
    void Function(bool connected)? onConnectionChanged,
    void Function(DateTime time)? onSynced,
    void Function(int count, String summary)? onConflict,
  })  : _settings = settings,
        _messages = messages,
        _conversations = conversations,
        _cursors = cursors,
        _onRemoteMessage = onRemoteMessage,
        _onConnectionChanged = onConnectionChanged,
        _onSynced = onSynced,
        _onConflict = onConflict;

  final SettingsRepository _settings;
  final MessageRepository _messages;
  final ConversationRepository _conversations;
  final SyncCursorRepository _cursors;

  /// 电脑端（server 角色）：本地库即权威源
  final bool isServerRole;

  final void Function(ChatMessage message)? _onRemoteMessage;
  final void Function(bool connected)? _onConnectionChanged;
  final void Function(DateTime time)? _onSynced;
  final void Function(int count, String summary)? _onConflict;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 30),
  ));

  WebSocket? _ws;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _syncing = false;

  String _host = '';
  int _port = 0;
  String _deviceId = '';
  String _token = '';

  bool get isConnected => _ws != null && _ws!.readyState == WebSocket.open;

  /// 读取持久化配置，若启用同步则启动引擎。
  Future<void> startIfEnabled() async {
    final enabled = await _settings.getValue(AppConstants.settingSyncEnabled);
    if (enabled != '1') {
      await _drain();
      return;
    }
    _host = await _settings.getValue(AppConstants.settingSyncHost) ?? '';
    _port = await _settings.getInt(AppConstants.settingSyncPort, 0);
    _deviceId = await _settings.getValue('sync_device_id') ?? '';
    _token = await _settings.getValue(AppConstants.settingSyncToken) ?? '';
    if (_host.isEmpty || _port <= 0 || _deviceId.isEmpty) {
      await _drain();
      return;
    }
    await _startLoop();
  }

  Future<void> _startLoop() async {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => syncOnce());
    await syncOnce();
    _connectWs();
  }

  Future<void> _drain() async {
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    await _ws?.close(WebSocketStatus.normalClosure);
    _ws = null;
    _setConnected(false);
  }

  /// 停止引擎（解除连接与定时器）。
  Future<void> stop() async {
    _disposed = true;
    await _drain();
  }

  // ---- 配对 ----

  /// 向服务器发起配对，成功后持久化连接配置并启动引擎。
  /// 返回 (success, message)。
  Future<(bool, String)> pair({
    required String host,
    required int port,
    required String pairCode,
    required String deviceName,
  }) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        'http://$host:$port/v1/pair',
        data: {
          'device_name': deviceName,
          'device_type': 'client',
          'pair_code': pairCode,
        },
      );
      final data = resp.data;
      if (data == null || data['ok'] != true) {
        return (false, data?['message'] as String? ?? '配对失败');
      }
      final deviceId = data['device_id'] as String? ?? '';
      final token = data['device_token'] as String? ?? '';
      final serverDeviceId = data['server_device_id'] as String? ?? '';
      if (deviceId.isEmpty || token.isEmpty) return (false, '服务器返回数据不完整');

      await _settings.setValue(AppConstants.settingSyncHost, host);
      await _settings.setValue(AppConstants.settingSyncPort, '$port');
      await _settings.setValue('sync_device_id', deviceId);
      await _settings.setValue(AppConstants.settingSyncToken, token);
      await _settings.setValue(AppConstants.settingServerDeviceId, serverDeviceId);
      await _settings.setValue(AppConstants.settingSyncEnabled, '1');

      _host = host;
      _port = port;
      _deviceId = deviceId;
      _token = token;
      _disposed = false;
      await _startLoop();
      return (true, '配对成功');
    } on DioException catch (e) {
      final data = e.response?.data;
      String? msg;
      if (data is Map) {
        msg = data['message'] as String?;
      }
      return (false, msg ?? '无法连接服务器：${e.message}');
    } catch (e) {
      return (false, '配对失败：$e');
    }
  }

  // ---- 同步 ----

  /// 单轮同步：拉取增量并合并到本地；手机端同时上传待同步队列。
  Future<void> syncOnce() async {
    if (_syncing) return;
    _syncing = true;
    try {
      if (!isServerRole) {
        await _uploadPending();
      }
      await _pullIncremental();
      // 电脑端：把本地新消息固化 server_id，供手机端增量拉取
      if (isServerRole) {
        // 由 LocalServerService.finalizeLocalMessages 负责（权威库直接落库）
        // 此处仅拉取，避免双写。
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _pullIncremental() async {
    if (_host.isEmpty || _port <= 0) return;
    final conversations = await _conversations.getAll();
    if (conversations.isEmpty) return;

    final cursors = <String, int>{};
    for (final c in conversations) {
      final cur = await _cursors.getCursor(_deviceId, c.id ?? 0);
      cursors['${c.id}'] = cur?.lastSyncedMsgId ?? 0;
    }

    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        'http://$_host:$_port/v1/sync',
        data: {
          'device_id': _deviceId,
          'device_token': _token,
          'cursors': cursors,
        },
      );
      final data = resp.data;
      if (data == null || data['ok'] != true) return;
      final rawMessages = data['messages'];
      if (rawMessages is List && rawMessages.isNotEmpty) {
        final messages = rawMessages
            .whereType<Map>()
            .map((e) => fromSyncJson(e.cast<String, Object?>()))
            .toList();
        await _mergeMessages(messages);
      }
      final syncedAt = DateTime.now();
      await _settings.setValue(
          AppConstants.settingSyncLastSyncAt, '${syncedAt.millisecondsSinceEpoch}');
      _onSynced?.call(syncedAt);
      _setConnected(true);
    } on DioException {
      _setConnected(false);
    } catch (_) {
      _setConnected(false);
    }
  }

  Future<void> _uploadPending() async {
    if (_host.isEmpty || _port <= 0) return;
    final pending = await _messages.listPendingUpload(_deviceId);
    if (pending.isEmpty) return;

    final payload = pending.map((m) {
      final json = toSyncJson(m)..remove('server_id')..remove('updated_at');
      return json;
    }).toList();

    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        'http://$_host:$_port/v1/messages',
        data: {'device_id': _deviceId, 'device_token': _token, 'messages': payload},
      );
      final data = resp.data;
      if (data == null || data['ok'] != true) return;
      final assigned = data['assigned'];
      if (assigned is List) {
        for (final item in assigned) {
          if (item is! Map) continue;
          final clientTs = item['client_ts'] as int?;
          final serverId = item['server_id'] as int?;
          if (clientTs == null || serverId == null) continue;
          final local = pending.where((m) => m.createdAt == clientTs).firstOrNull;
          if (local == null || local.id == null) continue;
          final now = DateTime.now().millisecondsSinceEpoch;
          await _messages.update(
            local.copyWith(serverId: serverId, updatedAt: now),
          );
        }
      }
    } on DioException {
      // 离线：保留本地队列，下轮重试
    }
  }

  /// 合并服务器增量消息到本地缓存（幂等：按 server_id 去重）。
  Future<void> _mergeMessages(List<ChatMessage> remote) async {
    final maxByConv = <int, int>{};
    var conflictCount = 0;
    for (final m in remote) {
      final existing = m.serverId == null ? null : await _messages.findByServerId(m.serverId!);
      if (existing != null) {
        final contentChanged = existing.content != m.content ||
            existing.contentType != m.contentType;
        // 服务器为权威源：保留本地自增 id，其余字段以服务器为准
        final merged = existing.copyWith(
          role: m.role,
          content: m.content,
          contentType: m.contentType,
          status: m.status,
          modelId: m.modelId,
          promptTokens: m.promptTokens,
          completionTokens: m.completionTokens,
          errorMessage: m.errorMessage,
          deviceId: m.deviceId,
          serverId: m.serverId,
          updatedAt: m.updatedAt,
        );
        await _messages.update(merged);
        if (contentChanged) conflictCount++;
      } else {
        await _messages.insert(m);
      }
      final conv = m.conversationId;
      final sid = m.serverId ?? 0;
      if (sid > (maxByConv[conv] ?? 0)) maxByConv[conv] = sid;
    }
    if (maxByConv.isNotEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final e in maxByConv.entries) {
        await _cursors.setCursor(SyncCursor(
          deviceId: _deviceId,
          conversationId: e.key,
          lastSyncedMsgId: e.value,
          updatedAt: now,
        ));
      }
    }
    if (conflictCount > 0) {
      _onConflict?.call(
          conflictCount, '检测到 $conflictCount 条消息内容冲突，已以服务器版本为准');
    }
    for (final m in remote) {
      _onRemoteMessage?.call(m);
    }
  }

  // ---- WebSocket ----

  void _connectWs() {
    _reconnectTimer?.cancel();
    if (_disposed || _host.isEmpty) return;
    try {
      WebSocket.connect('ws://$_host:$_port/v1/ws').then((ws) {
        if (_disposed) {
          ws.close();
          return;
        }
        _ws = ws;
        _setConnected(true);
        ws.listen(
          (raw) {
            _handleWsMessage(raw);
          },
          onDone: () {
            _ws = null;
            _setConnected(false);
            _scheduleReconnect();
          },
          onError: (_) {
            _ws = null;
            _setConnected(false);
            _scheduleReconnect();
          },
          cancelOnError: true,
        );
      }).catchError((_) {
        _setConnected(false);
        _scheduleReconnect();
      });
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (!_disposed) _connectWs();
    });
  }

  void _handleWsMessage(Object? raw) {
    if (raw is! String) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;
      if (data['type'] == 'message') {
        final msg = fromSyncJson((data['message'] as Map).cast<String, Object?>());
        // 收到推送的单条消息：异步合并（server_id 去重 + 更新游标）
        unawaited(_mergeMessages([msg]));
      }
    } catch (_) {
      // 忽略畸形帧
    }
  }

  void _setConnected(bool connected) {
    _onConnectionChanged?.call(connected);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
