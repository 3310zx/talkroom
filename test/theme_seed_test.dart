import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/core/theme.dart';

/// 主题取色（preset / custom / monet）相关单元测试。
///
/// 覆盖：seedMode 解析与默认回退、自定义 seed 应用、莫奈降级路径、
/// 组件联动参数化（导航栏/列表选中态不残留微信绿）、预设色板有效性。
void main() {
  group('AppSeedMode', () {
    test('fromValue 正确解析合法值', () {
      expect(AppSeedMode.fromValue('preset'), AppSeedMode.preset);
      expect(AppSeedMode.fromValue('custom'), AppSeedMode.custom);
      expect(AppSeedMode.fromValue('monet'), AppSeedMode.monet);
    });

    test('fromValue 未知/空/null 回退默认 preset', () {
      expect(AppSeedMode.fromValue('unknown'), AppSeedMode.preset);
      expect(AppSeedMode.fromValue(''), AppSeedMode.preset);
      expect(AppSeedMode.fromValue(null), AppSeedMode.preset);
    });
  });

  group('AppTheme.parseHexColor', () {
    test('有效 HEX 解析（支持 #RRGGBB / RRGGBB / #AARRGGBB）', () {
      expect(AppTheme.parseHexColor('#07C160'), const Color(0xFF07C160));
      expect(AppTheme.parseHexColor('07C160'), const Color(0xFF07C160));
      expect(AppTheme.parseHexColor('#FF0000'), const Color(0xFFFF0000));
      expect(AppTheme.parseHexColor('#80E91E63'), const Color(0x80E91E63));
      expect(AppTheme.parseHexColor('  #0E7AE6  '), const Color(0xFF0E7AE6));
    });

    test('无效 HEX 返回 null', () {
      expect(AppTheme.parseHexColor(''), isNull);
      expect(AppTheme.parseHexColor(null), isNull);
      expect(AppTheme.parseHexColor('#GGGGGG'), isNull);
      expect(AppTheme.parseHexColor('#12345'), isNull);
      expect(AppTheme.parseHexColor('#1234567'), isNull);
      expect(AppTheme.parseHexColor('#123456789'), isNull);
    });
  });

  group('主题构建', () {
    test('默认 preset 保持微信绿主色', () {
      expect(AppTheme.light.colorScheme.primary, AppTheme.brandGreen);
      expect(AppTheme.dark.colorScheme.primary, const Color(0xFF5FC95F));
    });

    test('自定义 seed 浅色模式 primary 等于 seed', () {
      final t = AppTheme.build(seed: const Color(0xFFE91E63));
      expect(t.colorScheme.primary, const Color(0xFFE91E63));
      expect(t.colorScheme.onPrimary, Colors.white);
    });

    test('自定义 seed 深色模式自动提亮保证对比度', () {
      const seed = Color(0xFFE91E63);
      final t = AppTheme.build(seed: seed, brightness: Brightness.dark);
      expect(t.colorScheme.primary, isNot(equals(seed)));
      expect(
        t.colorScheme.primary.computeLuminance(),
        greaterThan(seed.computeLuminance()),
      );
    });

    test('莫奈降级路径：dynamicScheme 为 null 时回退预设 seed 构建', () {
      final t = AppTheme.monet(null);
      expect(t.colorScheme.primary, AppTheme.brandGreen);
      final dark = AppTheme.monet(null, brightness: Brightness.dark);
      expect(dark.colorScheme.primary, const Color(0xFF5FC95F));
    });

    test('莫奈模式原样使用系统动态 scheme，不被手工固定值覆盖', () {
      final fake = ColorScheme.fromSeed(seedColor: const Color(0xFF8E44AD));
      final t = AppTheme.monet(fake);
      expect(t.colorScheme.primary, fake.primary);
      expect(t.colorScheme.surface, fake.surface);
    });
  });

  group('联动参数化（不残留微信绿）', () {
    test('自定义色下导航栏/列表选中态均由 primary 派生', () {
      final t = AppTheme.build(seed: const Color(0xFFE91E63));
      final nav = t.navigationBarTheme;
      final rail = t.navigationRailTheme;
      final listTile = t.listTileTheme;
      final expectedIndicator = t.colorScheme.primary.withValues(alpha: 0.16);
      expect(nav.indicatorColor, expectedIndicator);
      expect(rail.indicatorColor, expectedIndicator);
      expect(rail.selectedIconTheme?.color, t.colorScheme.primary);
      expect(rail.selectedLabelTextStyle?.color, t.colorScheme.primary);
      expect(
        listTile.selectedTileColor,
        t.colorScheme.primary.withValues(alpha: 0.12),
      );
    });

    test('莫奈模式下组件指示器也跟随动态 primary', () {
      final fake = ColorScheme.fromSeed(seedColor: const Color(0xFF16A085));
      final t = AppTheme.monet(fake);
      expect(
        t.navigationBarTheme.indicatorColor,
        fake.primary.withValues(alpha: 0.16),
      );
    });
  });

  group('预设色板', () {
    test('色板包含 8-12 个完全不透明颜色', () {
      expect(AppTheme.presetPalette.length, inInclusiveRange(8, 12));
      for (final c in AppTheme.presetPalette) {
        expect(c.toARGB32() & 0xFF000000, 0xFF000000,
            reason: '${c.toARGB32().toRadixString(16)} 应不透明');
      }
    });
  });
}
