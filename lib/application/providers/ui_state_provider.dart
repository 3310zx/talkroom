import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform.dart';
import '../../domain/models/api_config.dart';
import '../../domain/models/conversation.dart';

/// 当前选中会话（三栏/移动端共用）。
final selectedConversationProvider = StateProvider<Conversation?>((ref) => null);

/// 当前选中 API 配置（聊天页顶栏展示模型名/API 名）。
final selectedApiConfigProvider = StateProvider<ApiConfig?>((ref) => null);

/// 移动端底部 Tab 索引（0=聊天，1=设置），供「去添加 API」引导切换。
final mobileTabProvider = StateProvider<int>((ref) => 0);

/// 跨会话搜索跳转目标消息 id（R12，v1.0.15）。
///
/// 全局搜索页命中后写入，ChatPage 监听到非空值时滚动定位到该消息，
/// 定位完成后自动清空，避免重复滚动。
final pendingSearchMessageIdProvider = StateProvider<int?>((ref) => null);

/// 桌面端聊天详情面板显隐（Talkroom macOS 重构：默认隐藏，聊天页「详情」
/// 按钮展开；平板端保持默认展开以维持既有三栏布局，不破坏平板体验）。
final detailPanelVisibleProvider = StateProvider<bool>((ref) {
  return AppPlatform.isMacOS ? false : true;
});
