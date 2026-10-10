import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../core/platform.dart';
import '../services/update_service.dart';
import 'chat/chat_detail_panel.dart';
import 'chat/chat_page.dart';
import 'menu_commands.dart';
import 'session_list/session_list_page.dart';
import 'settings/settings_page.dart';
import 'sync/local_server_page.dart';

/// 首页：M3 自适应导航骨架。
///
/// - 宽屏（>= 840dp，平板/电脑）：左侧 NavigationRail + 双栏布局
///   （会话列表 | 聊天）；聊天区足够宽（>= 1200dp）时再分栏出右侧详情面板；
///   设置页以左侧抽屉（Drawer）呈现。
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
    if (AppPlatform.isMacOS) {
      MenuCommandBus.register(MenuAction.about, _showAboutDialog);
      MenuCommandBus.register(MenuAction.settings, _openSettingsFromMenu);
      MenuCommandBus.register(MenuAction.checkUpdate, _checkUpdateFromMenu);
      MenuCommandBus.register(
          MenuAction.newConversation, _newConversationFromMenu);
      MenuCommandBus.register(MenuAction.openSyncServer, _openSyncServerFromMenu);
    }
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
    // 防重入：已在运行（如本地服务器页手动启动后返回）时不再重复拉起。
    if (service.isRunning) return;
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
      await ref
          .read(settingsProvider.notifier)
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
  void dispose() {
    if (AppPlatform.isMacOS) {
      MenuCommandBus.unregister(MenuAction.about);
      MenuCommandBus.unregister(MenuAction.settings);
      MenuCommandBus.unregister(MenuAction.checkUpdate);
      MenuCommandBus.unregister(MenuAction.newConversation);
      MenuCommandBus.unregister(MenuAction.openSyncServer);
    }
    super.dispose();
  }

  // ── macOS 菜单栏命令响应 ────────────────────────────────────────

  void _showAboutDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关于 LLM Chat'),
        content: Text(
          '版本 ${AppConstants.appVersion}\n\n'
          'AI 聊天客户端（macOS / Android / Web）',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  void _openSettingsFromMenu() {
    final width = MediaQuery.of(context).size.width;
    if (width >= 840) {
      setState(() => _railSettingsSelected = true);
      _wideScaffoldKey.currentState?.openDrawer();
    } else {
      ref.read(mobileTabProvider.notifier).state = 1;
    }
  }

  void _newConversationFromMenu() {
    ref.read(selectedConversationProvider.notifier).state = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已新建会话')));
  }

  void _openSyncServerFromMenu() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LocalServerPage()),
    );
  }

  /// 菜单「检查更新」：与设置页一致走 GitHub Releases API，桌面端按钮跳转
  /// Releases 页（dmg 资产下载）。失败以 SnackBar 提示，不打断当前会话。
  Future<void> _checkUpdateFromMenu() async {
    try {
      final update = await UpdateService().fetchLatestRelease();
      final current = await UpdateService.currentVersion();
      if (UpdateService.compareVersions(update.version, current) > 0) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('发现新版本 ${update.version}'),
            content: SingleChildScrollView(
              child: Text(
                update.body.isEmpty ? '暂无更新说明' : update.body,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  launchUrl(
                    Uri.parse(
                      'https://github.com/3310zx/talkroom/releases/latest',
                    ),
                    mode: LaunchMode.externalApplication,
                  );
                },
                icon: const Icon(Icons.download),
                label: const Text('前往 Releases 页'),
              ),
            ],
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('当前已是最新版本 $current')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('检查更新失败：$e')));
    }
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
  /// 聊天区足够宽（>= 1200dp，v1.2.0 M1）时再分栏出右侧详情面板；
  /// 设置页抽屉化（左侧 Drawer）。
  Widget _buildWide(BuildContext context, BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth;
    // v1.2.0 H3：会话列表列宽对齐 M3 大屏建议（280-360dp）。
    final leftWidth = (maxWidth * 0.20).clamp(280.0, 360.0).toDouble();
    // v1.2.0 M1：详情面板宽度下限提升至 300，避免三栏下聊天区过窄。
    final rightWidth = (maxWidth * 0.22).clamp(300.0, 360.0).toDouble();
    return Scaffold(
      key: _wideScaffoldKey,
      // 设置面板从左侧滑入（覆盖 NavigationRail 之上）；v1.2.0 L1 固定 360dp 对齐 M3。
      drawer: Drawer(
        width: 360,
        child: const SettingsPage(),
      ),
      // M7：抽屉开合同步 NavigationRail 选中态，关闭时自动回到「聊天」。
      onDrawerChanged: (isOpen) {
        if (_railSettingsSelected != isOpen) {
          setState(() => _railSettingsSelected = isOpen);
        }
      },
      body: Row(
        children: [
          // v1.2.0 M2：>=1200dp 使用扩展 rail（extended，图标+文字横排、宽度约 256dp），
          // <1200dp 保持紧凑 rail（labelType.all）；rail 宽度由组件自身自适应，
          // 会话列表 leftWidth 与分割线位置不受影响。
          NavigationRail(
            selectedIndex: _railSettingsSelected ? 1 : 0,
            onDestinationSelected: (index) {
              if (index == 1) {
                // 设置页抽屉化：宽屏下从左侧滑出设置页。
                setState(() => _railSettingsSelected = true);
                _wideScaffoldKey.currentState?.openDrawer();
              } else {
                _wideScaffoldKey.currentState?.closeDrawer();
                ref.read(mobileTabProvider.notifier).state = index;
              }
            },
            extended: maxWidth >= 1200,
            labelType: maxWidth >= 1200
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
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
            // H2：聊天区在 840/1200dp 断点互切时共享同一 GlobalKey 保活 State。
            child: maxWidth >= 1200
                ? Row(
                    children: [
                      Expanded(child: ChatPage(key: _chatKeepAliveKey)),
                      const VerticalDivider(width: 1),
                      SizedBox(
                          width: rightWidth, child: const ChatDetailPanel()),
                    ],
                  )
                : ChatPage(key: _chatKeepAliveKey),
          ),
        ],
      ),
    );
  }
}
