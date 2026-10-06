import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/application/providers/active_task_scheduler_provider.dart';
import 'package:llm_chat_app/application/providers/database_provider.dart';
import 'package:llm_chat_app/application/providers/local_notifications_provider.dart';
import 'package:llm_chat_app/data/database/app_database.dart';
import 'package:llm_chat_app/presentation/chat/chat_detail_panel.dart';
import 'package:llm_chat_app/presentation/chat/chat_page.dart';
import 'package:llm_chat_app/presentation/home_page.dart';
import 'package:llm_chat_app/presentation/session_list/session_list_page.dart';
import 'package:llm_chat_app/services/active_task_scheduler.dart';
import 'package:llm_chat_app/services/llm_client.dart';
import 'package:llm_chat_app/services/local_notifications_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

/// v1.2.0 平板端布局优化回归测试（L3）。
///
/// 覆盖断点边界：839/840/899/900/1099/1100/1200，以及宽窄切换时
/// ChatPage 的状态保活。pump 真实 HomePage，验证 H1 断点统一、
/// M1 三栏阈值 1200、M2 extended rail、H3/L1 尺寸与 L2 空态文案。
void main() {
  group('v1.2.0 断点边界', () {
    late AppDatabase appDb;
    late Directory tmpDir;

    setUpAll(() async {
      // 必须在真实异步环境（非 testWidgets 的 FakeAsync）中打开 FFI 数据库，
      // 否则 sqflite_common_ffi 的 isolate 消息无法被调度导致挂起。
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmpDir = Directory.systemTemp.createTempSync('llm_chat_v120_test');
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

    /// 建立真实 HomePage 树（含 FFI 数据库与通知服务 override）。
    Future<void> pumpHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(appDb),
          localNotificationsServiceProvider
              .overrideWithValue(LocalNotificationsService()),
          activeTaskSchedulerProvider
              .overrideWithValue(_NoopActiveTaskScheduler(appDb)),
        ],
        child: const MaterialApp(home: HomePage()),
      ));
      // 等待启动链（配置/会话/设置/主动消息加载）完成并落定一帧。
      await tester.pump(const Duration(milliseconds: 400));
    }

    /// 停止主动消息调度器并卸载树（必须在测试体末尾调用，否则残留周期
    /// Timer 会导致 flutter_test 报「A Timer is still pending」）。
    Future<void> disposeHome(WidgetTester tester) async {
      final element = tester.element(find.byType(HomePage));
      ProviderScope.containerOf(element)
          .read(activeTaskSchedulerProvider)
          .stop();
      // 推进时钟让 FakeAsync 中的一次性延迟/异步收尾执行完毕。
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 31));
    }

    /// 仅改变逻辑宽度并重排一帧（复用同一棵树，不重建 HomePage State）。
    Future<void> setWidth(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 900);
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('H1：839dp 窄屏 NavigationBar，840dp 起宽屏 NavigationRail',
        (tester) async {
      await pumpHome(tester);
      await setWidth(tester, 839);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);

      await setWidth(tester, 840);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await disposeHome(tester);
    });

    testWidgets('H1：840-899dp 平板竖屏不再出现双会话入口（会话抽屉仅 <840 挂载）',
        (tester) async {
      await pumpHome(tester);
      // 839dp：窄屏，ChatPage AppBar 提供会话抽屉入口（menu 按钮）。
      await setWidth(tester, 839);
      expect(find.byIcon(Icons.menu), findsOneWidget);

      // 840/899/900/1099/1100/1200：均不出现抽屉入口，左侧会话列表已承担入口。
      for (final width in [840, 899, 900, 1099, 1100, 1200]) {
        await setWidth(tester, width.toDouble());
        expect(find.byIcon(Icons.menu), findsNothing,
            reason: '$width dp 不应出现会话抽屉入口（双入口）');
      }

      await disposeHome(tester);
    });

    testWidgets('M1：三栏阈值 1200dp，1099/1100 双栏、1200 三栏',
        (tester) async {
      await pumpHome(tester);
      await setWidth(tester, 1099);
      expect(find.byType(ChatDetailPanel), findsNothing);

      await setWidth(tester, 1100);
      expect(find.byType(ChatDetailPanel), findsNothing,
          reason: '1100dp 仍为双栏（阈值已提升至 1200）');

      await setWidth(tester, 1200);
      expect(find.byType(ChatDetailPanel), findsOneWidget,
          reason: '1200dp 进入三栏（会话列表 | 聊天 | 详情面板）');

      await disposeHome(tester);
    });

    testWidgets('M2：1200dp 起 NavigationRail 切换 extended，1100dp 保持紧凑',
        (tester) async {
      await pumpHome(tester);
      await setWidth(tester, 1100);
      expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          isNot(equals(true)),
          reason: '1100dp 使用紧凑 rail');

      await setWidth(tester, 1200);
      expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          isTrue,
          reason: '1200dp 使用 extended rail');

      await disposeHome(tester);
    });

    testWidgets('H3/L1：会话列表列宽 280-360dp 区间、设置抽屉固定 360dp',
        (tester) async {
      await pumpHome(tester);
      // 1200dp：leftWidth = 1200*0.2=240，被 clamp 到下限 280。
      await setWidth(tester, 1200);
      final listSizedBox = tester.widget<SizedBox>(find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.width == 280 &&
            w.child is SessionListPage,
      ));
      expect(listSizedBox.width, 280,
          reason: '1200dp 下会话列表列宽应为 clamp 下限 280');

      // 打开设置抽屉，Drawer 宽度固定 360。
      await tester.tap(find.text('设置'));
      await tester.pump(const Duration(milliseconds: 500));
      final drawer = tester.widget<Drawer>(find.byType(Drawer));
      expect(drawer.width, 360, reason: 'L1：设置抽屉固定 360dp');

      await disposeHome(tester);
    });

    testWidgets('L2：三栏未选中态详情面板空态文案不重复引导', (tester) async {
      await pumpHome(tester);
      await setWidth(tester, 1200);
      expect(find.textContaining('暂无选中会话'), findsOneWidget);
      expect(find.textContaining('选择左侧会话后展示详情'), findsNothing);

      await disposeHome(tester);
    });

    testWidgets('L3：全断点序列（839→840→899→900→1099→1100→1200→839）'
        '切换 ChatPage State 保活', (tester) async {
      final widths = [839.0, 840.0, 899.0, 900.0, 1099.0, 1100.0, 1200.0, 839.0];
      await pumpHome(tester);
      await setWidth(tester, widths.first);
      final initial = tester.state<State<ChatPage>>(find.byType(ChatPage));
      expect(initial, isNotNull);

      for (final width in widths.skip(1)) {
        await setWidth(tester, width);
        final current = tester.state<State<ChatPage>>(find.byType(ChatPage));
        expect(identical(initial, current), isTrue,
            reason: '跨 $width dp 断点切换应保活 ChatPage State');
      }

      await disposeHome(tester);
    });
  });
}
