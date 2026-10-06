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

/// 主题取色源模式（与 [AppThemeMode] 正交：亮暗 vs 取色来源）。
enum AppSeedMode {
  preset('preset', '默认（微信绿）'),
  custom('custom', '自定义取色'),
  monet('monet', '莫奈（壁纸动态）');

  const AppSeedMode(this.value, this.label);

  /// 持久化存储值
  final String value;
  /// 设置页展示名
  final String label;

  static AppSeedMode fromValue(String? value) => AppSeedMode.values
      .where((m) => m.value == value)
      .firstOrNull ??
      AppSeedMode.preset;
}

extension on Iterable<AppSeedMode> {
  AppSeedMode? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

/// 全局主题：微信绿 M3 方案（M3 语义色 token + 组件主题）。
///
/// 深浅色统一走 ColorScheme.fromSeed 生成路线，surface/outline/error 等
/// M3 语义 token 显式补全；界面字体挂载 NotoSansSC；组件（AppBar/按钮/
/// 输入框/列表/卡片/导航）按 M3 规范细化。
abstract final class AppTheme {
  /// 微信品牌绿（M3 seed 色）
  static const Color brandGreen = Color(0xFF07C160);

  /// 会话/聊天浅色背景
  static const Color chatBackground = Color(0xFFEDEDED);

  /// 顶部/底部导航深色（微信深绿灰）
  static const Color navDark = Color(0xFF2E2E2E);

  /// 全局界面字体（与导出 PDF 同族字体）
  static const String fontFamily = 'NotoSansSC';

  /// 预设色板（设置页「主题色」自定义取色用，8-12 个品牌色）
  static const List<Color> presetPalette = <Color>[
    Color(0xFF07C160), // 微信绿
    Color(0xFF4CAF50), // Material 绿
    Color(0xFF2196F3), // 蓝
    Color(0xFF0E7AE6), // 微信蓝
    Color(0xFF8E44AD), // 紫
    Color(0xFFE91E63), // 粉红
    Color(0xFFFF7043), // 橙
    Color(0xFFE74C3C), // 红
    Color(0xFF16A085), // 青
    Color(0xFF34495E), // 深蓝灰
    Color(0xFFF5A623), // 琥珀
    Color(0xFF795548), // 棕
  ];

  /// 解析 HEX 颜色字符串（支持 #RRGGBB / RRGGBB / #AARRGGBB），失败返回 null。
  static Color? parseHexColor(String? hex) {
    if (hex == null) return null;
    var s = hex.trim().replaceAll('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    return v == null ? null : Color(v);
  }

  /// 深色模式主色提亮（保证自定义深色主题对比度）
  static Color _liftForDark(Color c) => Color.lerp(c, Colors.white, 0.30)!;

  static ThemeData get light => build();
  static ThemeData get dark => build(brightness: Brightness.dark);

  /// 按指定 seed 构建主题（preset / custom 模式）。
  static ThemeData build({
    Color seed = brandGreen,
    Brightness brightness = Brightness.light,
  }) =>
      _build(brightness, seed: seed);

  /// 莫奈模式：直接使用系统动态 scheme 构建主题；
  /// [dynamicScheme] 为 null（非 Android 12+）时降级为普通 seed 构建。
  static ThemeData monet(
    ColorScheme? dynamicScheme, {
    Brightness brightness = Brightness.light,
  }) =>
      _build(
        brightness,
        useDynamic: dynamicScheme != null,
        dynamicScheme: dynamicScheme,
      );

  static ThemeData _build(
    Brightness brightness, {
    Color seed = brandGreen,
    bool useDynamic = false,
    ColorScheme? dynamicScheme,
  }) {
    final isDark = brightness == Brightness.dark;

    ColorScheme scheme;
    if (useDynamic && dynamicScheme != null) {
      // 莫奈：原样使用系统动态 scheme，禁止手工覆盖（否则壁纸色被固定值覆盖失效）
      scheme = dynamicScheme;
    } else {
      // M3：以 seed 生成完整 tonal palette，再显式补全/固定关键语义 token。
      final isPresetSeed = seed == brandGreen;
      final base = ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      );
      scheme = base.copyWith(
        // —— 品牌主色随 seed（预设=微信绿，深色保持历史提亮值；
        //    自定义=用户色，深色自动提亮保证对比度） ——
        primary: isPresetSeed
            ? (isDark ? const Color(0xFF5FC95F) : brandGreen)
            : (isDark ? _liftForDark(seed) : seed),
        onPrimary: Colors.white,
        // 预设模式保留历史固定容器色避免视觉漂移；自定义模式随 seed 自动生成
        primaryContainer: isPresetSeed
            ? (isDark ? const Color(0xFF0F3D0F) : const Color(0xFFC9F3C9))
            : base.primaryContainer,
        onPrimaryContainer: isPresetSeed
            ? (isDark ? const Color(0xFFC9F3C9) : const Color(0xFF0E2A0E))
            : base.onPrimaryContainer,
        // —— surface 语义 token（聊天灰底 / 卡片分层） ——
        surface: isDark ? const Color(0xFF111111) : Colors.white,
        onSurface: isDark ? const Color(0xFFE4E4E4) : const Color(0xFF1B1B1B),
        surfaceContainerLowest: isDark ? const Color(0xFF0C0C0C) : Colors.white,
        surfaceContainerLow:
            isDark ? const Color(0xFF171717) : const Color(0xFFF7F7F7),
        surfaceContainer:
            isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F2),
        surfaceContainerHigh:
            isDark ? const Color(0xFF232325) : const Color(0xFFECECEC),
        surfaceContainerHighest:
            isDark ? const Color(0xFF2A2A2C) : const Color(0xFFE4E4E4),
        // —— outline 语义 token（分隔线 / 边框） ——
        outline: isDark ? const Color(0xFF8A8A8E) : const Color(0xFF747474),
        outlineVariant:
            isDark ? const Color(0xFF3A3A3C) : const Color(0xFFDCDCDC),
        // —— error 语义 token ——
        error: isDark ? const Color(0xFFF2B8B5) : const Color(0xFFBA1A1A),
        onError: Colors.white,
        errorContainer: isDark ? const Color(0xFF93000A) : const Color(0xFFFFDAD6),
        onErrorContainer:
            isDark ? const Color(0xFFFFDAD6) : const Color(0xFF410002),
      );
    }

    return _buildThemeData(scheme, isDark: isDark);
  }

  static ThemeData _buildThemeData(ColorScheme scheme, {required bool isDark}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
      // M3 页面转场：统一使用 M3 FadeForwards 预测性转场。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? scheme.surfaceContainer : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        scrolledUnderElevation: 2,
        centerTitle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? scheme.surfaceContainer : Colors.white,
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? scheme.surfaceContainer : Colors.white,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(
          color: isDark ? Colors.white70 : Colors.black54,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: isDark ? Colors.white70 : Colors.black54,
        ),
        indicatorColor: scheme.primary.withValues(alpha: 0.16),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 0.5,
        space: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        selectedColor: isDark ? Colors.white : Colors.black87,
        selectedTileColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.12),
        iconColor: isDark ? Colors.white70 : Colors.black54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        filled: true,
        fillColor:
            isDark ? scheme.surfaceContainerHighest : scheme.surfaceContainerLow,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:
            isDark ? scheme.surfaceContainerHigh : const Color(0xFF323232),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
