import 'package:flutter/material.dart';

/// 主题模式：跟随系统 / 强制浅色 / 强制深色（持久化到 settings 表）。
enum AppThemeMode {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色');

  const AppThemeMode(this.value, this.label);

  /// 持久化存储值
  final String value;
  /// 设置页展示名
  final String label;

  /// MaterialApp 使用的 themeMode。
  ThemeMode get themeMode => switch (this) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      };

  static AppThemeMode fromValue(String? value) => AppThemeMode.values
      .where((m) => m.value == value)
      .firstOrNull ??
      AppThemeMode.system;
}

extension on Iterable<AppThemeMode> {
  AppThemeMode? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

/// 全局主题：仿微信风格（绿 + 浅灰底），但保留差异化（无社交入口/不复用官方图标）。
abstract final class AppTheme {
  /// 微信品牌绿
  static const Color brandGreen = Color(0xFF07C160);

  /// 会话/聊天浅色背景
  static const Color chatBackground = Color(0xFFEDEDED);

  /// 顶部/底部导航深色（微信深绿灰）
  static const Color navDark = Color(0xFF2E2E2E);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: brandGreen,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF111111) : chatBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0.5,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        indicatorColor: brandGreen.withValues(alpha: 0.15),
      ),
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF2A2A2C) : const Color(0xFFE5E5E5),
        thickness: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        selectedColor:
            isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEDEDED),
        selectedTileColor:
            isDark ? const Color(0xFF2C2C2E) : const Color(0xFFEDEDED),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F2),
      ),
    );
  }
}
