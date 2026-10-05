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
      onConflict: (count, summary) {
        notifier.setConflict(count, summary);
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
    this.pendingConflicts = 0,
    this.lastConflictText,
  });

  final bool enabled;
  final String host;
  final int port;
  final bool connected;
  final int? lastSyncAtMs;
  final String? lastError;

  /// 最近一次同步中检测到的双端写冲突条数（R15，v1.0.15）。
  final int pendingConflicts;

  /// 冲突提示文本（R15，v1.0.15）：如「检测到 2 条双端修改冲突，已按电脑优先合并」。
  final String? lastConflictText;

  SyncState copyWith({
    bool? enabled,
    String? host,
    int? port,
    bool? connected,
    int? lastSyncAtMs,
    String? lastError,
    int? pendingConflicts,
    String? lastConflictText,
  }) {
    return SyncState(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      connected: connected ?? this.connected,
      lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
      lastError: lastError ?? this.lastError,
      pendingConflicts: pendingConflicts ?? this.pendingConflicts,
      lastConflictText: lastConflictText ?? this.lastConflictText,
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

  /// R15：记录双端写冲突提示（数量 + 摘要），供设置页/连接页醒目展示。
  void setConflict(int count, String summary) {
    state = state.copyWith(
      pendingConflicts: count,
      lastConflictText: summary,
    );
  }
}
