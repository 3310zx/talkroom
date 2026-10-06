import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/providers/active_task_scheduler_provider.dart';
import '../application/providers/active_tasks_provider.dart';
import '../application/providers/api_configs_provider.dart';
import '../application/providers/conversations_provider.dart';
import '../application/providers/local_server_provider.dart';
import '../application/providers/messages_provider.dart';
import '../application/providers/settings_provider.dart';
import '../application/providers/sync_provider.dart';
import '../application/providers/ui_state_provider.dart';
import '../core/constants.dart';
import 'chat/chat_detail_panel.dart';
import 'chat/chat_page.dart';
import 'session_list/session_list_page.dart';
import 'settings/settings_page.dart';

/// 首页：M3 自适应导航骨架。
///
/// - 宽屏（>= 840dp，平板/电脑）：左侧 NavigationRail + 双栏布局
///   （会话列表 | 聊天）；聊天区足够宽（>= 1100dp）时再分栏出右侧详情面板；
///   设置页以右侧抽屉（Drawer）呈现。
/// - 窄屏（手机）：底部 NavigationBar 单栏 + IndexedStack 多 Tab（聊天/设置）。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  /// 宽屏 Scaffold key：用于打开设置抽屉。
  final GlobalKey<ScaffoldState> _wideScaffoldKey = GlobalKey<ScaffoldState>();

  /// H2：聊天区保活 key。宽屏（840/1100dp 断点切换、双栏/三栏互切）与窄屏
  /// 底部 Tab 之间共享同一 GlobalKey，Flutter 会复用 ChatPage 的 Element/State，
  /// 从而保留草稿、附件、滚动位置与生成中上下文。
  final GlobalKey _chatKeepAliveKey = GlobalKey();

  /// M7：宽屏 NavigationRail 选中态跟随设置抽屉开合。
  bool _railSettingsSelected = false;

  @override
  void initState() {
    super.initState();
    Future<void>(() async {
      try {
        await ref.read(apiConfigsProvider.notifier).load();
        await ref.read(conversationsProvider.notifier).load();
        await ref.read(settingsProvider.notifier).load();
        // 主动消息：加载任务并启动调度器（含启动补跑检查）
        await ref.read(activeTasksProvider.notifier).load();
        ref.read(activeTaskSchedulerProvider).start();
        // P1 局域网同步：按设置自动拉起本地服务器（电脑端）与同步引擎（客户端）
        await _maybeAutoStartServer();
        await _maybeStartSyncEngine();
        // 启动行为：按设置定位会话（回到退出时对话 / 保持新建状态）
        await _applyStartupBehavior();
      } catch (e, st) {
        // M1：启动链任一步失败不再中断后续流程，仅记录日志避免静默。
        debugPrint('HomePage startup chain failed: $e\n$st');
      }
    });
  }

  /// 启动行为：'last' 时自动选中最近使用的会话并加载消息；否则保持新建状态。
  Future<void> _applyStartupBehavior() async {
    final settings = ref.read(settingsProvider);
    if (settings[AppConstants.settingStartupBehavior] !=
        AppConstants.startupBehaviorLast) {
      return;
    }
    final conversations = ref.read(conversationsProvider);
    if (conversations.isEmpty) return;
    // 仓储已按最近更新时间倒序，列表首项即最近使用的会话。
    final last = conversations.first;
    ref.read(selectedConversationProvider.notifier).state = last;
    await ref.read(messagesProvider.notifier).loadForConversation(last.id!);
  }

  /// 电脑端：开启「自动启动」时，从上次使用端口（默认 8787）探测顺延并拉起服务器。
  Future<void> _maybeAutoStartServer() async {
    final settings = ref.read(settingsProvider);
    if (settings[AppConstants.settingServerAutoStart] != '1') return;
    final service = ref.read(localServerServiceProvider);
    try {
      final lastPort =
          int.tryParse(settings[AppConstants.settingServerLastPort] ?? '') ??
              AppConstants.defaultServerPort;
      final port = await service.probePort(startPort: lastPort);
      await service.start(port: port);
      final ips = await service.getLanIpv4Addresses();
      final info = await service.pairInfo();
      final code = info['pair_code_set'] == true
          ? await service.getPairCode()
          : await service.ensurePairCode();
      await ref.read(settingsProvider.notifier)
          .set(AppConstants.settingServerLastPort, '$port');
      ref.read(localServerStatusProvider.notifier).state = LocalServerState(
        port: port,
        lanIps: ips,
        startedAt: DateTime.now(),
        pairCode: code,
        serverDeviceId: info['server_device_id'] as String?,
        pairedDevices: info['paired_devices'] as int? ?? 0,
        pairLocked: info['pair_locked'] == true,
        pairRemainingLockMs: info['pair_remaining_lock_ms'] as int? ?? 0,
      );
    } catch (_) {
      // 自动拉起失败不影响主流程，用户可在设置页手动启动
    }
  }

  /// 客户端：已启用同步时恢复会话（WebSocket 实时 + 增量拉取）。
  Future<void> _maybeStartSyncEngine() async {
    final settings = ref.read(settingsProvider);
    if (settings[AppConstants.settingSyncEnabled] != '1') return;
    final engine = ref.read(syncEngineProvider);
    await engine.startIfEnabled();
    ref.read(syncStatusProvider.notifier).setEnabled(true);
    ref.read(syncStatusProvider.notifier).setConnected(engine.isConnected);
  }

  @override
  Widget build(BuildContext context) {
    final mobileTab = ref.watch(mobileTabProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        if (wide) {
          return _buildWide(context, constraints);
        }
        // 窄屏（手机）：底部 NavigationBar 单栏 + IndexedStack 多 Tab。
        return Scaffold(
          body: IndexedStack(
            index: mobileTab,
            children: [
              ChatPage(key: _chatKeepAliveKey),
              const SettingsPage(),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: mobileTab,
            onDestinationSelected: (index) =>
                ref.read(mobileTabProvider.notifier).state = index,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: '聊天',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }

  /// 宽屏（>= 840dp）：NavigationRail + 双栏布局（会话列表 | 聊天）。
  /// 聊天区足够宽时再分栏出右侧详情面板；设置页抽屉化（右侧 Drawer）。
  Widget _buildWide(BuildContext context, BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth;
    final leftWidth = (maxWidth * 0.20).clamp(240.0, 320.0).toDouble();
    final rightWidth = (maxWidth * 0.22).clamp(260.0, 360.0).toDouble();
    return Scaffold(
      key: _wideScaffoldKey,
      endDrawer: Drawer(
        width: (maxWidth * 0.36).clamp(320.0, 440.0),
        child: const SettingsPage(),
      ),
      // M7：抽屉开合同步 NavigationRail 选中态，关闭时自动回到「聊天」。
      onEndDrawerChanged: (isOpen) {
        if (_railSettingsSelected != isOpen) {
          setState(() => _railSettingsSelected = isOpen);
        }
      },
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _railSettingsSelected ? 1 : 0,
            onDestinationSelected: (index) {
              if (index == 1) {
                // 设置页抽屉化：宽屏下从右侧滑出设置页。
                setState(() => _railSettingsSelected = true);
                _wideScaffoldKey.currentState?.openEndDrawer();
              } else {
                _wideScaffoldKey.currentState?.closeEndDrawer();
                ref.read(mobileTabProvider.notifier).state = index;
              }
            },
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: Text('聊天'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          SizedBox(width: leftWidth, child: const SessionListPage()),
          const VerticalDivider(width: 1),
          Expanded(
            // H2：聊天区在 840/1100dp 断点互切时共享同一 GlobalKey 保活 State。
            child: maxWidth >= 1100
                ? Row(
                    children: [
                      Expanded(child: ChatPage(key: _chatKeepAliveKey)),
                      const VerticalDivider(width: 1),
                      SizedBox(width: rightWidth, child: const ChatDetailPanel()),
                    ],
                  )
                : ChatPage(key: _chatKeepAliveKey),
          ),
        ],
      ),
    );
  }
}
