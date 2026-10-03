// 最小冒烟测试：验证核心数据模型序列化往返（不依赖数据库/Provider，稳定通过）。
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/domain/models/active_task.dart';
import 'package:llm_chat_app/domain/models/active_task_schedule.dart';
import 'package:llm_chat_app/domain/models/api_config.dart';
import 'package:llm_chat_app/domain/models/conversation.dart';
import 'package:llm_chat_app/domain/models/message.dart';

void main() {
  test('ApiConfig toMap/fromMap 序列化往返', () {
    const config = ApiConfig(
      name: '测试',
      baseUrl: 'https://api.example.com/v1',
      apiKeyRef: 'api_key:1',
      modelIds: ['deepseek-chat', 'gpt-4o-mini'],
      createdAt: 1000,
      updatedAt: 2000,
    );
    final restored = ApiConfig.fromMap(config.toMap());
    expect(restored.name, '测试');
    expect(restored.baseUrl, 'https://api.example.com/v1');
    expect(restored.apiKeyRef, 'api_key:1');
    expect(restored.modelIds, ['deepseek-chat', 'gpt-4o-mini']);
    expect(restored.enabled, isTrue);
  });

  test('Conversation toMap/fromMap 序列化往返', () {
    final conversation = Conversation(
      title: '会话A',
      pinned: true,
      lastMessage: '你好',
      updatedAt: 3000,
      createdAt: 1000,
    );
    final restored = Conversation.fromMap(conversation.toMap());
    expect(restored.title, '会话A');
    expect(restored.pinned, isTrue);
    expect(restored.lastMessage, '你好');
  });

  test('ChatMessage toMap/fromMap 序列化往返', () {
    final message = ChatMessage(
      conversationId: 1,
      role: 'assistant',
      content: '回复内容',
      createdAt: 1000,
    );
    final restored = ChatMessage.fromMap(message.toMap());
    expect(restored.conversationId, 1);
    expect(restored.role, 'assistant');
    expect(restored.content, '回复内容');
  });

  test('ActiveTask 序列化往返 + 调度规则解析', () {
    final task = ActiveTask(
      taskName: '每日晨报',
      taskType: 'daily',
      scheduleData: ActiveTaskSchedule(
        taskType: 'daily',
        time: '08:00',
      ).toJson(),
      prompt: '生成今日晨报',
      apiConfigId: 1,
      modelId: 'deepseek-chat',
      delivery: 'both',
      enabled: true,
      nextRunAt: 1234567890,
      createdAt: 1000,
    );
    final restored = ActiveTask.fromMap(task.toMap());
    expect(restored.taskName, '每日晨报');
    expect(restored.enabled, isTrue);
    final schedule = ActiveTaskSchedule.fromJson(
      restored.scheduleData,
      taskType: restored.taskType,
    );
    expect(schedule.describe(), '每天 08:00');
    final next = schedule.computeNextRunAt(DateTime(2026, 10, 2, 7, 0));
    expect(
      DateTime.fromMillisecondsSinceEpoch(next!)
          .toLocal()
          .hour,
      8,
    );
  });
}
