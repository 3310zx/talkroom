import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/application/providers/ui_state_provider.dart';
import 'package:llm_chat_app/core/constants.dart';

/// Talkroom macOS 桌面端重构的布局关键逻辑：
/// - 桌面端（macOS）：详情面板默认隐藏（两栏：会话列表+聊天区）；
/// - 平板端（Android/iOS）：详情面板默认展开，保持既有三栏布局不破坏；
/// - 产品名统一为 Talkroom。
void main() {
  test('产品名统一为 Talkroom（不再使用 LLM Chat）', () {
    expect(AppConstants.appName, 'Talkroom');
    expect(AppConstants.appName, isNot(contains('LLM Chat')));
  });

  test('桌面端详情面板默认隐藏（两栏），平板端默认展开（三栏）', () {
    // macOS 桌面端：默认两栏（无详情面板），点击详情按钮才展开。
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final macContainer = ProviderContainer();
    addTearDown(macContainer.dispose);
    expect(macContainer.read(detailPanelVisibleProvider), isFalse,
        reason: 'macOS 桌面端详情面板默认隐藏，保证两栏布局');

    // 平板端（Android）：保持既有三栏布局，详情面板默认展开。
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final tabletContainer = ProviderContainer();
    addTearDown(tabletContainer.dispose);
    expect(tabletContainer.read(detailPanelVisibleProvider), isTrue,
        reason: '平板端详情面板默认展开，不破坏平板布局');
  });
}
