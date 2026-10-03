import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/providers/settings_provider.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'presentation/home_page.dart';

/// 应用根组件：主题（跟随系统/强制浅色/强制深色）+ 首页。
class LlmChatApp extends ConsumerWidget {
  const LlmChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final themeMode = AppThemeMode.fromValue(
      settings[AppConstants.settingThemeMode],
    );
    return MaterialApp(
      title: 'LLM Chat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode.themeMode,
      home: const HomePage(),
    );
  }
}

