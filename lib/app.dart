import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers/settings_provider.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'presentation/home_page.dart';

/// 应用根组件：主题（跟随系统/强制浅色/强制深色，取色源 preset/custom/monet）
/// + 首页。莫奈模式通过 [DynamicColorBuilder] 读取系统动态配色；
/// 非 Android 12+ 平台返回 null，自动降级为自定义色/预设色。
class LlmChatApp extends ConsumerWidget {
  const LlmChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    return DynamicColorBuilder(
      builder: (dynamicLight, dynamicDark) {
        final useDynamic = seedMode == AppSeedMode.monet &&
            dynamicLight != null &&
            dynamicDark != null;
        return MaterialApp(
          title: 'LLM Chat',
          debugShowCheckedModeBanner: false,
          theme: useDynamic
              ? AppTheme.monet(dynamicLight)
              : AppTheme.build(seed: seed),
          darkTheme: useDynamic
              ? AppTheme.monet(dynamicDark, brightness: Brightness.dark)
              : AppTheme.build(seed: seed, brightness: Brightness.dark),
          themeMode: themeMode.themeMode,
          home: const HomePage(),
        );
      },
    );
  }
}

