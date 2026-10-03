import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/active_task_scheduler.dart';
import '../../services/llm_client.dart';
import 'active_tasks_provider.dart';
import 'conversations_provider.dart';
import 'database_provider.dart';
import 'local_notifications_provider.dart';
import 'messages_provider.dart';
import 'ui_state_provider.dart';

/// 主动消息调度器（应用运行期间 Timer 调度 + 启动补跑）。
///
/// 构造时注册「点击通知跳转会话」回调；任务执行后自动刷新任务列表与会话列表。
final activeTaskSchedulerProvider = Provider<ActiveTaskScheduler>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final notifications = ref.watch(localNotificationsServiceProvider);

  notifications.setOnOpenConversation((conversationId) async {
    final conv = await db.conversationRepository.getById(conversationId);
    if (conv == null) return;
    ref.read(selectedConversationProvider.notifier).state = conv;
    ref.read(mobileTabProvider.notifier).state = 0; // 窄屏切到聊天 Tab
    await ref.read(messagesProvider.notifier).loadForConversation(conversationId);
  });

  return ActiveTaskScheduler(
    activeTaskRepository: db.activeTaskRepository,
    apiConfigRepository: db.apiConfigRepository,
    conversationRepository: db.conversationRepository,
    messageRepository: db.messageRepository,
    settingsRepository: db.settingsRepository,
    notifications: notifications,
    llmClient: LlmClient(),
    onTasksChanged: () => ref.read(activeTasksProvider.notifier).load(),
    onConversationsChanged: () =>
        ref.read(conversationsProvider.notifier).load(),
  );
});
