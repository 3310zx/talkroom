import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/api_config.dart';
import '../../domain/models/conversation.dart';

/// 当前选中会话（三栏/移动端共用）。
final selectedConversationProvider = StateProvider<Conversation?>((ref) => null);

/// 当前选中 API 配置（聊天页顶栏展示模型名/API 名）。
final selectedApiConfigProvider = StateProvider<ApiConfig?>((ref) => null);

/// 移动端底部 Tab 索引（0=聊天，1=设置），供「去添加 API」引导切换。
final mobileTabProvider = StateProvider<int>((ref) => 0);
