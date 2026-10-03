import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/sync/sync_engine.dart';
import 'database_provider.dart';

/// 客户端同步引擎实例。
/// 电脑端（桌面平台）作为权威源（isServerRole=true），手机端（移动平台）为 false。
final syncEngineProvider = Provider<SyncEngine>(
  (ref) {
    final db = ref.watch(appDatabaseProvider);
    final notifier = ref.read(syncStatusProvider.notifier);
    return SyncEngine(
      settings: db.settingsRepository,
      messages: db.messageRepository,
      conversations: db.conversationRepository,
      cursors: db.syncCursorRepository,
      isServerRole: Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isFuchsia,
      onRemoteMessage: (_) {
        // 消息已合并入库；UI 通过消息查询自动刷新
      },
      onConnectionChanged: (connected) {
        notifier.setConnected(connected);
      },
      onSynced: (time) {
        notifier.setLastSyncAt(time.millisecondsSinceEpoch);
      },
    );
  },
);

/// 局域网同步状态（设置页「局域网同步」入口与连接配置页共用）。
class SyncState {
  const SyncState({
    this.enabled = false,
    this.host = '',
    this.port = 0,
    this.connected = false,
    this.lastSyncAtMs,
    this.lastError,
  });

  final bool enabled;
  final String host;
  final int port;
  final bool connected;
  final int? lastSyncAtMs;
  final String? lastError;

  SyncState copyWith({
    bool? enabled,
    String? host,
    int? port,
    bool? connected,
    int? lastSyncAtMs,
    String? lastError,
  }) {
    return SyncState(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      connected: connected ?? this.connected,
      lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
      lastError: lastError ?? this.lastError,
    );
  }
}

final syncStatusProvider =
    StateNotifierProvider<SyncStatusNotifier, SyncState>(
  (ref) => SyncStatusNotifier(),
);

class SyncStatusNotifier extends StateNotifier<SyncState> {
  SyncStatusNotifier() : super(const SyncState());

  void setConnected(bool connected) {
    state = state.copyWith(connected: connected);
  }

  void setLastSyncAt(int ms) {
    state = state.copyWith(lastSyncAtMs: ms);
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(enabled: enabled);
  }

  void setError(String? error) {
    state = state.copyWith(lastError: error);
  }
}
