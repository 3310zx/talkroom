import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers/settings_provider.dart';
import 'core/accessibility.dart';
import 'core/constants.dart';
import 'core/platform.dart';
import 'core/theme.dart';
import 'presentation/home_page.dart';
import 'presentation/menu_commands.dart';

/// 应用根组件：主题（跟随系统/强制浅色/强制深色，取色源 preset/custom/monet）
/// + 首页。莫奈模式通过 [DynamicColorBuilder] 读取系统动态配色；
/// 非 Android 12+ 平台返回 null，自动降级为自定义色/预设色。
///
/// macOS 专属：外层包裹 [PlatformMenuBar] 定制应用菜单栏（应用/文件/编辑/
/// 视图），菜单动作经 [MenuCommandBus] 交给 HomePage 处理；编辑菜单通过
/// Flutter 文本命令通道修复默认 xib 菜单对 Flutter 文本框无效的问题。
class LlmChatApp extends ConsumerStatefulWidget {
  const LlmChatApp({super.key});

  @override
  ConsumerState<LlmChatApp> createState() => _LlmChatAppState();
}

class _LlmChatAppState extends ConsumerState<LlmChatApp> {
  @override
  void initState() {
    super.initState();
    // 读取系统辅助功能偏好（增加对比度/降低透明度），用于 Liquid Glass
    // 弱化时的高对比回退主题；macOS 专属，异步读取不阻塞启动。
    AppAccessibility.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = AppThemeMode.fromValue(
      settings[AppConstants.settingThemeMode],
    );
    final seedMode = AppSeedMode.fromValue(
      settings[AppConstants.settingThemeSeedMode],
    );
    final customSeed = AppTheme.parseHexColor(
      settings[AppConstants.settingThemeCustomSeed],
    );
    final seed =
        (seedMode == AppSeedMode.custom && customSeed != null)
            ? customSeed
            : AppTheme.brandGreen;

    final app = DynamicColorBuilder(
      builder: (dynamicLight, dynamicDark) {
        final useDynamic = seedMode == AppSeedMode.monet &&
            dynamicLight != null &&
            dynamicDark != null;
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: useDynamic
              ? AppTheme.monet(
                  dynamicLight,
                  highContrast: AppAccessibility.increaseContrast,
                )
              : AppTheme.build(
                  seed: seed,
                  highContrast: AppAccessibility.increaseContrast,
                ),
          darkTheme: useDynamic
              ? AppTheme.monet(
                  dynamicDark,
                  brightness: Brightness.dark,
                  highContrast: AppAccessibility.increaseContrast,
                )
              : AppTheme.build(
                  seed: seed,
                  brightness: Brightness.dark,
                  highContrast: AppAccessibility.increaseContrast,
                ),
          themeMode: themeMode.themeMode,
          home: const HomePage(),
        );
      },
    );

    if (!AppPlatform.isMacOS) {
      return app;
    }
    return PlatformMenuBar(
      menus: _buildMenus(),
      child: app,
    );
  }

  List<PlatformMenu> _buildMenus() {
    return [
      PlatformMenu(
        label: AppConstants.appName,
        menus: [
          PlatformMenuItem(
            label: '关于 ${AppConstants.appName}',
            onSelected: () => MenuCommandBus.fire(MenuAction.about),
          ),
          PlatformMenuItem(
            label: '设置…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.comma,
              meta: true,
            ),
            onSelected: () => MenuCommandBus.fire(MenuAction.settings),
          ),
          PlatformMenuItem(
            label: '检查更新…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyU,
              meta: true,
            ),
            onSelected: () => MenuCommandBus.fire(MenuAction.checkUpdate),
          ),
          PlatformMenuItem(
            label: '退出 ${AppConstants.appName}',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyQ,
              meta: true,
            ),
            onSelected: () => exit(0),
          ),
        ],
      ),
      PlatformMenu(
        label: '文件',
        menus: [
          PlatformMenuItem(
            label: '新建会话',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyN,
              meta: true,
            ),
            onSelected: () =>
                MenuCommandBus.fire(MenuAction.newConversation),
          ),
          PlatformMenuItem(
            label: '同步服务器…',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: true,
              shift: true,
            ),
            onSelected: () => MenuCommandBus.fire(MenuAction.openSyncServer),
          ),
        ],
      ),
      PlatformMenu(
        label: '编辑',
        menus: [
          PlatformMenuItem(
            label: '撤销',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: '重做',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ),
          ),
          PlatformMenuItem(
            label: '剪切',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyX,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: '复制',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyC,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: '粘贴',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyV,
              meta: true,
            ),
          ),
          PlatformMenuItem(
            label: '全选',
            shortcut: const SingleActivator(
              LogicalKeyboardKey.keyA,
              meta: true,
            ),
          ),
        ],
      ),
    ];
  }
}
