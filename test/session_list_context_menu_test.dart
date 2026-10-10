import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/application/providers/active_task_scheduler_provider.dart';
import 'package:llm_chat_app/application/providers/conversations_provider.dart';
import 'package:llm_chat_app/application/providers/database_provider.dart';
import 'package:llm_chat_app/application/providers/local_notifications_provider.dart';
import 'package:llm_chat_app/data/database/app_database.dart';
import 'package:llm_chat_app/domain/models/conversation.dart';
import 'package:llm_chat_app/domain/repositories/conversation_repository.dart';
import 'package:llm_chat_app/presentation/home_page.dart';
import 'package:llm_chat_app/services/active_task_scheduler.dart';
import 'package:llm_chat_app/services/llm_client.dart';
import 'package:llm_chat_app/services/local_notifications_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// R14 侧栏会话「长按可编辑」回归测试（L3）。
///
/// 覆盖：长按会话条目弹出操作菜单（置顶/重命名/默认模板/归档/删除会话）、
/// 重命名弹窗输入新标题、删除二次确认后移除会话。
/// 三栏布局（1200dp）下会话列表可见，桌面/移动端手势均触发同一菜单。
void main() {
  group('R14 会话列表长按菜单', () {
    late AppDatabase appDb;
    late Directory tmpDir;

    setUpAll(() async {
      // 必须在真实异步环境（非 testWidgets 的 FakeAsync）中打开 FFI 数据库，
      // 否则 sqflite_common_ffi 的 isolate 消息无法被调度导致挂起。
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmpDir = Directory.systemTemp.createTempSync('llm_chat_r14_test');
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

    /// 建立真实 HomePage 树（1200dp 三栏，会话列表可见）。
    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(appDb),
          // 会话列表用内存 fake，避免 testWidgets FakeAsync 中
          // await 真实数据库（sqflite isolate 消息无法调度导致挂起）。
          conversationsProvider
              .overrideWith((ref) => _FakeConversationsNotifier()),
          localNotificationsServiceProvider
              .overrideWithValue(LocalNotificationsService()),
          activeTaskSchedulerProvider
              .overrideWithValue(_NoopActiveTaskScheduler(appDb)),
        ],
        child: const MaterialApp(home: HomePage()),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 通过内存 fake notifier 新建会话并落定列表。
    Future<void> createConversation(WidgetTester tester) async {
      final element = tester.element(find.byType(HomePage));
      await ProviderScope.containerOf(element)
          .read(conversationsProvider.notifier)
          .create();
      await tester.pump(const Duration(milliseconds: 200));
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

    /// 长按会话列表第一条（按 fake 默认标题「新会话」定位）。
    Future<void> longPressSessionTile(WidgetTester tester) async {
      await tester.longPress(find.text('新会话').first);
      await tester.pumpAndSettle();
    }

    testWidgets('长按会话条目弹出操作菜单，含重命名/删除等编辑操作',
        (tester) async {
      await pumpHome(tester);
      await createConversation(tester);

      await longPressSessionTile(tester);
      // 上下文菜单与三点按钮菜单一致，覆盖常用编辑操作。
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('默认模板'), findsOneWidget);
      expect(find.text('归档'), findsOneWidget);
      expect(find.text('删除会话'), findsOneWidget);

      // 菜单消失后无残留：点击菜单外区域关闭。
      await tester.tapAt(const Offset(1150, 850));
      await tester.pumpAndSettle();
      expect(find.text('删除会话'), findsNothing);

      await disposeHome(tester);
    });

    testWidgets('长按 → 重命名：弹窗输入新标题并保存生效', (tester) async {
      await pumpHome(tester);
      await createConversation(tester);

      await longPressSessionTile(tester);
      await tester.tap(find.text('重命名'));
      await tester.pumpAndSettle();

      expect(find.text('重命名会话'), findsOneWidget);
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogField, '测试会话A');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('测试会话A'), findsOneWidget);

      await disposeHome(tester);
    });

    testWidgets('长按 → 删除：二次确认后移除会话', (tester) async {
      await pumpHome(tester);
      await createConversation(tester);

      await longPressSessionTile(tester);
      await tester.tap(find.text('删除会话'));
      await tester.pumpAndSettle();

      // 二次确认弹窗：取消可保留会话。
      expect(find.text('删除会话'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // 再次进入并确认删除，会话从列表移除。
      await longPressSessionTile(tester);
      await tester.tap(find.text('删除会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) =>
            w is ListTile &&
            w.title is Text &&
            (w.title as Text).data != null &&
            !(w.title as Text).data!.contains('归档')),
        findsNothing,
        reason: '确认删除后会话条目应从列表移除',
      );

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
    _items.insert(0, conversation.copyWith(
      id: _seq,
      title: conversation.title,
      updatedAt: now,
      createdAt: conversation.createdAt == 0 ? now : conversation.createdAt,
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