import 'package:flutter_riverpod/flutter_riverpod.dart';

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
