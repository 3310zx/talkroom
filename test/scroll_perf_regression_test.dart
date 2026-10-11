import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/application/providers/active_task_scheduler_provider.dart';
import 'package:llm_chat_app/application/providers/conversations_provider.dart';
import 'package:llm_chat_app/application/providers/database_provider.dart';
import 'package:llm_chat_app/application/providers/local_notifications_provider.dart';
import 'package:llm_chat_app/application/providers/messages_provider.dart';
import 'package:llm_chat_app/data/database/app_database.dart';
import 'package:llm_chat_app/domain/models/conversation.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/domain/models/message_search_hit.dart';
import 'package:llm_chat_app/domain/repositories/conversation_repository.dart';
import 'package:llm_chat_app/domain/repositories/message_repository.dart';
import 'package:llm_chat_app/presentation/home_page.dart';
import 'package:llm_chat_app/presentation/session_list/session_list_page.dart';
import 'package:llm_chat_app/presentation/chat/chat_page.dart';
import 'package:llm_chat_app/presentation/widgets/message_bubble.dart';
import 'package:llm_chat_app/services/active_task_scheduler.dart';
import 'package:llm_chat_app/services/llm_client.dart';
import 'package:llm_chat_app/services/local_notifications_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v1.2.19 滑动性能回归测试。
///
/// 覆盖性能重构的关键不变量：
/// 1. 会话列表 / 消息列表均为懒加载（ListView.builder → SliverChildBuilderDelegate），
///    长列表不会一次性构建全部条目；
/// 2. 列表条目包裹 RepaintBoundary，滚动时隔离重绘，避免整列表连带 paint；
/// 3. MessageBubble 为无状态组件，流式增量更新期间列表仍可正常渲染（功能不变）。
void main() {
  group('v1.2.19 滑动性能回归', () {
    late AppDatabase appDb;
    late Directory tmpDir;

    setUpAll(() async {
      // 必须在真实异步环境（非 testWidgets 的 FakeAsync）中打开 FFI 数据库，
      // 否则 sqflite_common_ffi 的 isolate 消息无法被调度导致挂起。
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmpDir = Directory.systemTemp.createTempSync('llm_chat_perf_test');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
        if (call.method == 'getApplicationSupportDirectory') {
          return tmpDir.path;
        }
        return null;
      });
      appDb = AppDatabase.instance;
      await appDb.open();
    });

    tearDownAll(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'), null);
      try {
        await appDb.db.close();
      } catch (_) {}
      try {
        tmpDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    /// 建立真实 HomePage 树（1200dp 三栏，会话列表 + 聊天区可见）。
    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(appDb),
          conversationsProvider
              .overrideWith((ref) => _FakeConversationsNotifier()),
          messagesProvider
              .overrideWith((ref) => _FakeMessagesNotifier()),
          localNotificationsServiceProvider
              .overrideWithValue(LocalNotificationsService()),
          activeTaskSchedulerProvider
              .overrideWithValue(_NoopActiveTaskScheduler(appDb)),
        ],
        child: const MaterialApp(home: HomePage()),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 批量创建会话并落定列表。
    Future<void> createConversations(WidgetTester tester, int count) async {
      final element = tester.element(find.byType(HomePage));
      final notifier = ProviderScope.containerOf(element)
          .read(conversationsProvider.notifier);
      for (var i = 0; i < count; i++) {
        await notifier.create();
      }
      await tester.pump(const Duration(milliseconds: 200));
    }

    /// 预置指定会话的消息并触发加载（写入 fake 仓储，load 时可见）。
    Future<void> seedMessages(WidgetTester tester, int conversationId,
        int count) async {
      final element = tester.element(find.byType(HomePage));
      final notifier = ProviderScope.containerOf(element)
          .read(messagesProvider.notifier) as _FakeMessagesNotifier;
      final messages = [
        for (var i = 0; i < count; i++)
          ChatMessage(
            id: i,
            conversationId: conversationId,
            role: i.isEven ? 'user' : 'assistant',
            content: '性能回归消息 $i${'x' * (i % 5 * 10)}',
            createdAt: i,
          ),
      ];
      notifier.repo.seed(conversationId, messages);
      await notifier.loadForConversation(conversationId);
      await tester.pump(const Duration(milliseconds: 100));
    }

    /// 停止主动消息调度器并卸载树（避免残留周期 Timer）。
    Future<void> disposeHome(WidgetTester tester) async {
      final element = tester.element(find.byType(HomePage));
      ProviderScope.containerOf(element)
          .read(activeTaskSchedulerProvider)
          .stop();
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    }

    /// 检查目标 widget 的祖先链中是否存在 RepaintBoundary。
    bool hasRepaintBoundaryAncestor(Element element) {
      var found = false;
      element.visitAncestorElements((ancestor) {
        if (ancestor.widget is RepaintBoundary) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    }

    testWidgets('会话列表懒加载且条目包 RepaintBoundary', (tester) async {
      await pumpHome(tester);
      await createConversations(tester, 40);

      final sessionList = find.byType(SessionListPage);
      final listViewFinder =
          find.descendant(of: sessionList, matching: find.byType(ListView));
      expect(listViewFinder, findsWidgets);
      final listView =
          tester.widget<ListView>(listViewFinder.first);
      expect(listView.childrenDelegate, isA<SliverChildBuilderDelegate>(),
          reason: '会话列表必须使用 ListView.builder 懒加载，禁止一次性构建全部条目');

      // 懒加载生效：40 条会话不应全部被构建为 ListTile。
      final tileFinder = find.descendant(
          of: sessionList, matching: find.byType(ListTile));
      expect(tileFinder.evaluate().length, lessThan(40),
          reason: '长列表滚动窗口外条目不应被构建');

      // 每个可见条目祖先链都应有 RepaintBoundary（滚动隔离重绘）。
      for (final element in tileFinder.evaluate()) {
        expect(hasRepaintBoundaryAncestor(element), isTrue,
            reason: '会话条目缺少 RepaintBoundary');
      }

      await disposeHome(tester);
    });

    testWidgets('消息列表懒加载、条目包 RepaintBoundary，流式更新期间可正常渲染',
        (tester) async {
      await pumpHome(tester);
      await createConversations(tester, 1);

      // 预置 60 条消息并触发加载（fake notifier 直接持有内存列表）。
      final homeElement = tester.element(find.byType(HomePage));
      final convNotifier = ProviderScope.containerOf(homeElement)
          .read(conversationsProvider.notifier);
      final conversations = convNotifier.state;
      expect(conversations, isNotEmpty);
      final convId = conversations.first.id!;
      await seedMessages(tester, convId, 60);

      // 选中会话：点击会话条目进入消息视图（ChatPage 加载消息）。
      await tester.tap(find.descendant(
          of: find.byType(SessionListPage),
          matching: find.text('新会话').first));
      await tester.pump(const Duration(milliseconds: 300));

      final chat = find.byType(ChatPage);
      expect(chat, findsOneWidget);
      final messageListFinder =
          find.descendant(of: chat, matching: find.byType(ListView));
      expect(messageListFinder, findsWidgets);
      final messageList =
          tester.widget<ListView>(messageListFinder.first);
      expect(messageList.childrenDelegate, isA<SliverChildBuilderDelegate>(),
          reason: '消息列表必须使用 ListView.builder 懒加载');

      final bubbleFinder = find.byType(MessageBubble);
      expect(bubbleFinder, findsWidgets);
      expect(bubbleFinder.evaluate().length, lessThan(60),
          reason: '消息长列表不应一次性构建全部气泡');
      for (final element in bubbleFinder.evaluate()) {
        expect(hasRepaintBoundaryAncestor(element), isTrue,
            reason: '消息条目缺少 RepaintBoundary');
      }

      // MessageBubble 无状态：流式增量更新只重建变化条目对应的 Widget。
      final bubbleWidget =
          tester.widget<MessageBubble>(bubbleFinder.first);
      expect(bubbleWidget, isA<StatelessWidget>(),
          reason: '消息气泡必须为无状态组件，避免滚动/更新时携带可变状态');

      // 流式增量模拟：多次 appendStreamingFragment 后列表仍正常渲染且无异常。
      final messagesNotifier = ProviderScope.containerOf(homeElement)
          .read(messagesProvider.notifier);
      for (var i = 0; i < 5; i++) {
        messagesNotifier.appendStreamingFragment(0, ' 增量$i');
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(MessageBubble), findsWidgets,
          reason: '流式更新期间消息列表应保持可渲染');
      // 功能不变：流式增量内容应完整追加到目标消息。
      final streamed =
          messagesNotifier.state.firstWhere((m) => m.id == 0);
      expect(streamed.content, contains('增量4'),
          reason: '流式增量内容应完整追加，功能保持不变');

      await disposeHome(tester);
    });
  });
}

/// 测试专用调度器：start() 不启动周期 Timer，避免测试结束时残留 Timer。
class _NoopActiveTaskScheduler extends ActiveTaskScheduler {
  _NoopActiveTaskScheduler(AppDatabase db)
      : super(
          activeTaskRepository: db.activeTaskRepository,
          apiConfigRepository: db.apiConfigRepository,
          conversationRepository: db.conversationRepository,
          messageRepository: db.messageRepository,
          settingsRepository: db.settingsRepository,
          notifications: LocalNotificationsService(),
          llmClient: LlmClient(),
          onTasksChanged: () async {},
          onConversationsChanged: () async {},
        );

  @override
  void start() {
    // 测试中不启动周期调度。
  }
}

/// 内存版会话 Notifier：替代真实数据库，避免 testWidgets FakeAsync
/// 下 await sqflite isolate 导致挂起；仅覆盖测试路径用到的操作。
class _FakeConversationsNotifier extends ConversationsNotifier {
  _FakeConversationsNotifier() : super(_FakeConversationRepository());
}

/// 内存版会话仓储：支撑 _FakeConversationsNotifier。
class _FakeConversationRepository implements ConversationRepository {
  final List<Conversation> _items = [];
  int _seq = 0;

  @override
  Future<List<Conversation>> getAll() async => List.of(_items);

  @override
  Future<Conversation?> getById(int id) async {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<int> insert(Conversation conversation) async {
    _seq++;
    final now = DateTime.now().millisecondsSinceEpoch;
    _items.insert(
        0,
        conversation.copyWith(
          id: _seq,
          title: conversation.title,
          updatedAt: now,
          createdAt: conversation.createdAt == 0
              ? now
              : conversation.createdAt,
        ));
    return _seq;
  }

  @override
  Future<void> update(Conversation conversation) async {
    final index = _items.indexWhere((item) => item.id == conversation.id);
    if (index >= 0) {
      _items[index] = conversation;
    }
  }

  @override
  Future<void> delete(int id) async {
    _items.removeWhere((item) => item.id == id);
  }
}

/// 内存版消息 Notifier：消息不落库，直接在内存维护，供性能回归断言使用。
class _FakeMessagesNotifier extends MessagesNotifier {
  _FakeMessagesNotifier() : this._(_FakeMessageRepository());

  _FakeMessagesNotifier._(this.repo) : super(repo);

  final _FakeMessageRepository repo;
}

/// 内存版消息仓储：支撑 _FakeMessagesNotifier；未用方法返回安全默认值。
class _FakeMessageRepository implements MessageRepository {
  final Map<int, List<ChatMessage>> _byConversation = {};
  int _seq = 0;

  /// 测试预置：写入指定会话的消息，供 loadForConversation 返回。
  void seed(int conversationId, List<ChatMessage> messages) {
    _byConversation[conversationId] = messages;
  }

  @override
  Future<List<ChatMessage>> listByConversation(int conversationId) async =>
      List.of(_byConversation[conversationId] ?? const []);

  @override
  Future<List<MessageSearchHit>> searchMessages(
    String keyword, {
    int limit = 100,
  }) async =>
      const [];

  @override
  Future<List<ChatMessage>> listPerformanceStats({int limit = 30}) async =>
      const [];

  @override
  Future<ChatMessage?> getById(int id) async => null;

  @override
  Future<int> insert(ChatMessage message) async {
    _seq++;
    _byConversation.putIfAbsent(message.conversationId, () => []);
    _byConversation[message.conversationId]!.add(message.copyWith(id: _seq));
    return _seq;
  }

  @override
  Future<void> update(ChatMessage message) async {}

  @override
  Future<void> deleteByConversation(int conversationId) async {}

  @override
  Future<void> delete(int id) async {}

  @override
  Future<void> deleteFrom(int id) async {}

  @override
  Future<List<ChatMessage>> listByServerIdAfter({
    required int conversationId,
    required int afterServerId,
    int limit = 500,
  }) async =>
      const [];

  @override
  Future<int> getMaxServerId() async => 0;

  @override
  Future<ChatMessage?> findByServerId(int serverId) async => null;

  @override
  Future<List<ChatMessage>> listPendingUpload(String deviceId) async =>
      const [];

  @override
  Future<bool> existsByDeviceAndClientTs(
      String deviceId, int clientTs) async =>
      false;

  @override
  Future<List<ChatMessage>> listByServerIdUpTo({
    required int conversationId,
    required int afterServerId,
    required int toServerId,
  }) async =>
      const [];

  @override
  Future<List<ChatMessage>> insertWithServerIds(
          List<ChatMessage> messages) async =>
      messages;

  @override
  Future<List<ChatMessage>> finalizeLocalMessages() async => const [];

  @override
  Future<int> insertCacheHit(CacheHitRecord record) async => -1;

  @override
  Future<List<CacheHitRecord>> listCacheHits({int limit = 200}) async =>
      const [];

  @override
  Future<int> clearCacheHits() async => 0;
}
