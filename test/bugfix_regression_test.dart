import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/application/providers/api_configs_provider.dart';
import 'package:llm_chat_app/application/providers/database_provider.dart';
import 'package:llm_chat_app/application/providers/ui_state_provider.dart';
import 'package:llm_chat_app/data/database/app_database.dart';
import 'package:llm_chat_app/domain/models/api_config.dart';
import 'package:llm_chat_app/domain/models/conversation.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/domain/repositories/api_config_repository.dart';
import 'package:llm_chat_app/presentation/chat/chat_detail_panel.dart';
import 'package:llm_chat_app/presentation/chat/chat_page.dart';
import 'package:llm_chat_app/services/conversation_exporter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v1.1.1 Bug 修复回归测试。
///
/// 覆盖：
/// - H1/H2：断点切换（840/1100dp）ChatPage State 保活、dispose 安全；
/// - M2：API 配置事务补偿（密钥写失败回滚数据库记录 / 恢复旧密钥）；
/// - M3：附件大小预检（20MB 上限拒绝超限附件）；
/// - M6：会话导出分卷（3000 条 / 30MB 临界、单条超限单独成卷不丢弃）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── M3：附件大小预检 ─────────────────────────────────────────────
  group('M3 附件超限拒绝', () {
    test('20MB 及以内允许通过', () {
      expect(ChatPage.checkAttachmentSize(1024), isNull);
      expect(ChatPage.checkAttachmentSize(ChatPage.kMaxAttachmentBytes), isNull);
    });

    test('0 与非法负值不拦截', () {
      expect(ChatPage.checkAttachmentSize(0), isNull);
      expect(ChatPage.checkAttachmentSize(-1), isNull);
    });

    test('超过 20MB 拒绝并返回用户可见提示', () {
      final message =
          ChatPage.checkAttachmentSize(ChatPage.kMaxAttachmentBytes + 1);
      expect(message, isNotNull);
      expect(message, contains('20MB'));
      expect(message, contains('已拒绝'));
    });
  });

  // ── M6：导出分卷 ─────────────────────────────────────────────────
  group('M6 导出 3000 条 / 30MB 分卷', () {
    ChatMessage buildMessage(int id, String content) => ChatMessage(
          id: id,
          conversationId: 1,
          role: 'user',
          content: content,
          createdAt: id,
        );

    test('3000 条以内且字符未超限时单卷', () {
      final messages =
          List.generate(3000, (i) => buildMessage(i, '你好'));
      final chunks = ConversationExporter.chunkMessages(messages);
      expect(chunks.length, 1);
      expect(chunks.single.length, 3000);
    });

    test('超过 3000 条按消息数拆卷，每卷不超过上限', () {
      final messages = List.generate(3001, (i) => buildMessage(i, '你好'));
      final chunks = ConversationExporter.chunkMessages(messages);
      expect(chunks.length, 2);
      expect(chunks[0].length, ConversationExporter.kMaxMessages);
      expect(chunks[1].length, 1);
      expect(chunks.every((c) => c.length <= ConversationExporter.kMaxMessages),
          isTrue);
    });

    test('3000 条以内但总字符超 30MB 时按字符拆卷', () {
      final longBody = '长文本内容'.padRight(20 * 1024, 'x'); // 每条约 20KB
      final messages = List.generate(3000, (i) => buildMessage(i, longBody));
      final totalChars = messages.fold<int>(
          0, (sum, m) => sum + m.content.length);
      expect(totalChars, greaterThan(ConversationExporter.kMaxTotalChars));
      final chunks = ConversationExporter.chunkMessages(messages);
      expect(chunks.length, greaterThan(1));
      // 每卷字符上限：除“单条超限”例外外不应超过 30MB
      for (final chunk in chunks) {
        final chars = chunk.fold<int>(0, (sum, m) => sum + m.content.length);
        expect(chars <= ConversationExporter.kMaxTotalChars || chunk.length == 1,
            isTrue,
            reason: '每卷字符数应不超过 30MB（单条超限例外）');
      }
      // 消息无丢失
      final totalCount =
          chunks.fold<int>(0, (sum, c) => sum + c.length);
      expect(totalCount, 3000);
    });

    test('单条消息自身超 30MB 时单独成卷不丢弃', () {
      final huge = buildMessage(0, 'x' * (ConversationExporter.kMaxTotalChars + 1));
      final normal = buildMessage(1, '正常消息');
      final chunks = ConversationExporter.chunkMessages([huge, normal]);
      expect(chunks.length, 2);
      expect(chunks[0].single.content.length,
          greaterThan(ConversationExporter.kMaxTotalChars));
      expect(chunks[1].single.content, '正常消息');
    });
  });

  // ── M2：事务补偿 ─────────────────────────────────────────────────
  group('M2 API 配置事务补偿', () {
    const secureChannel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

    late _FakeApiConfigRepository fake;
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      fake = _FakeApiConfigRepository();
      messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(secureChannel, null);
    });

    test('add 时密钥写入失败回滚数据库记录', () async {
      messenger.setMockMethodCallHandler(secureChannel, (call) async {
        if (call.method == 'write') {
          throw PlatformException(code: 'write_failed', message: 'injected');
        }
        if (call.method == 'delete') return null;
        if (call.method == 'read') return null;
        return null;
      });
      final notifier = ApiConfigsNotifier(fake);
      final config = ApiConfig(
        name: 'ollama',
        baseUrl: 'http://localhost:11434/v1',
        apiKeyRef: 'placeholder',
        modelIds: const ['llama3'],
        createdAt: 1,
        updatedAt: 1,
      );
      await expectLater(
        notifier.add(config, 'secret-key'),
        throwsA(isA<PlatformException>()),
      );
      // 已插入的记录应被事务补偿删除，不留下半成品。
      expect(fake.deletedIds, contains(1));
    });

    test('update 密钥写入失败恢复旧密钥', () async {
      var firstWrite = true;
      final written = <String?>[];
      messenger.setMockMethodCallHandler(secureChannel, (call) async {
        if (call.method == 'read') return 'old-secret';
        if (call.method == 'write') {
          final value = (call.arguments as Map)['value'] as String?;
          if (firstWrite) {
            firstWrite = false;
            throw PlatformException(code: 'write_failed', message: 'injected');
          }
          written.add(value);
          return null;
        }
        if (call.method == 'delete') return null;
        return null;
      });
      final notifier = ApiConfigsNotifier(fake);
      final config = ApiConfig(
        id: 1,
        name: 'remote',
        baseUrl: 'https://api.example.com/v1',
        apiKeyRef: 'api_key:1',
        modelIds: const ['gpt-4o'],
        createdAt: 1,
        updatedAt: 1,
      );
      await expectLater(
        notifier.update(config, apiKey: 'new-secret'),
        throwsA(isA<PlatformException>()),
      );
      // 失败后应尽力把安全存储恢复为旧密钥。
      expect(written, ['old-secret']);
    });

    test('remove 删除记录后密钥清理失败不影响数据库删除结果', () async {
      messenger.setMockMethodCallHandler(secureChannel, (call) async {
        if (call.method == 'delete') {
          throw PlatformException(code: 'delete_failed', message: 'injected');
        }
        return null;
      });
      final notifier = ApiConfigsNotifier(fake);
      final config = ApiConfig(
        id: 7,
        name: 'remote',
        baseUrl: 'https://api.example.com/v1',
        apiKeyRef: 'api_key:7',
        modelIds: const ['gpt-4o'],
        createdAt: 1,
        updatedAt: 1,
      );
      await notifier.remove(config);
      expect(fake.deletedIds, contains(7));
    });
  });

  // ── H1/H2：断点切换保活 ─────────────────────────────────────────
  group('H1/H2 宽屏断点切换 ChatPage 保活', () {
    late AppDatabase appDb;
    late Directory tmpDir;

    setUpAll(() async {
      // 必须在真实异步环境（非 testWidgets 的 FakeAsync）中打开 FFI 数据库，
      // 否则 sqflite_common_ffi 的 isolate 消息无法被调度导致挂起。
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmpDir = Directory.systemTemp.createTempSync('llm_chat_test');
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

    testWidgets('840/1100dp 断点切换不重建 State，dispose 安全', (tester) async {
      final keepAliveKey = GlobalKey();

      Widget buildAt(double width) => ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(appDb),
            ],
            child: MaterialApp(
              home: SizedBox(
                width: width,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 840;
                    if (wide) {
                      // 宽屏：左侧 NavigationRail + 聊天区（模拟 HomePage 布局）
                      return Row(
                        children: [
                          const SizedBox(
                            width: 72,
                            child: ColoredBox(
                              color: Colors.black12,
                              child: Center(child: Text('rail')),
                            ),
                          ),
                          Expanded(child: ChatPage(key: keepAliveKey)),
                        ],
                      );
                    }
                    // 窄屏：单栏（模拟 IndexedStack Tab）
                    return ChatPage(key: keepAliveKey);
                  },
                ),
              ),
            ),
          );

      // 窄屏 400dp
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(buildAt(400));
      await tester.pump(const Duration(milliseconds: 300));
      final narrowState = tester.state<State<ChatPage>>(find.byType(ChatPage));
      expect(narrowState, isNotNull);

      // 宽屏 900dp（>= 840 断点）
      tester.view.physicalSize = const Size(900, 800);
      await tester.pumpWidget(buildAt(900));
      await tester.pump(const Duration(milliseconds: 300));
      final wide840State =
          tester.state<State<ChatPage>>(find.byType(ChatPage));
      expect(identical(narrowState, wide840State), isTrue,
          reason: '跨 840dp 断点切换应保活 ChatPage State');

      // 超宽 1200dp（>= 1100 断点，右侧详情面板）
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpWidget(buildAt(1200));
      await tester.pump(const Duration(milliseconds: 300));
      final wide1100State =
          tester.state<State<ChatPage>>(find.byType(ChatPage));
      expect(identical(narrowState, wide1100State), isTrue,
          reason: '跨 1100dp 断点切换应保活 ChatPage State');

      // 回到窄屏，State 仍然保持（IndexedStack 场景）
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(buildAt(400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(identical(narrowState,
          tester.state<State<ChatPage>>(find.byType(ChatPage))),
          isTrue);
    });
  });

  // ── v1.1.2：发送前模型多模态预检 ──────────────────────────────
  group('v1.1.2 模型多模态预检', () {
    const imageAtt = MessageAttachment(
      type: 'image',
      name: 'a.jpg',
      mimeType: 'image/jpeg',
      sizeBytes: 1024,
      dataBase64: 'AAAA',
    );
    const fileAtt = MessageAttachment(
      type: 'file',
      name: 'a.txt',
      mimeType: 'text/plain',
      sizeBytes: 1024,
      dataBase64: 'AAAA',
    );

    test('无附件返回 null', () {
      expect(
          ChatPage.checkAttachmentModelSupport('gpt-4o', const []), isNull);
    });

    test('已知纯文本模型 + 图片 -> 提示不支持图片', () {
      final msg =
          ChatPage.checkAttachmentModelSupport('deepseek-chat', [imageAtt]);
      expect(msg, isNotNull);
      expect(msg, contains('不支持图片'));
    });

    test('已知纯文本模型 + 文件 -> 提示不支持文件', () {
      final msg =
          ChatPage.checkAttachmentModelSupport('gpt-3.5-turbo', [fileAtt]);
      expect(msg, isNotNull);
      expect(msg, contains('不支持文件'));
    });

    test('已知纯文本模型 + 图片与文件混合 -> 优先提示图片', () {
      final msg = ChatPage.checkAttachmentModelSupport(
          'deepseek-chat', [fileAtt, imageAtt]);
      expect(msg, isNotNull);
      expect(msg, contains('不支持图片'));
    });

    test('多模态模型 + 附件不拦截', () {
      expect(
          ChatPage.checkAttachmentModelSupport('gpt-4o', [imageAtt]), isNull);
      expect(ChatPage.checkAttachmentModelSupport('qwen-vl-plus', [fileAtt]),
          isNull);
    });

    test('未知模型 + 附件不打扰（由 400 兜底）', () {
      expect(ChatPage.checkAttachmentModelSupport('my-custom-llm', [imageAtt]),
          isNull);
    });
  });

  // ── v1.1.2：详情面板按钮（去掉重复设置入口）────────────────────
  group('v1.1.2 详情面板按钮', () {
    late AppDatabase appDb;
    late Directory tmpDir;

    setUpAll(() async {
      // 真实异步环境打开 FFI 数据库，避免 FakeAsync 下 sqflite isolate 挂起。
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmpDir = Directory.systemTemp.createTempSync('llm_chat_detail_test');
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

    testWidgets('未选会话时不渲染「编辑会话参数」，也无「设置」按钮', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(appDb)],
        child: const MaterialApp(home: ChatDetailPanel()),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('编辑会话参数'), findsNothing);
      expect(find.text('设置'), findsNothing);
    });

    testWidgets('选中会话时显示「编辑会话参数」，且无重复「设置」按钮', (tester) async {
      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(appDb),
      ]);
      addTearDown(container.dispose);
      container.read(selectedConversationProvider.notifier).state =
          const Conversation(
        id: 1,
        title: '测试会话',
        updatedAt: 1,
        createdAt: 1,
      );
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatDetailPanel()),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      // 按钮位于详情 ListView 底部，懒加载需滚动到可见后再断言。
      await tester.scrollUntilVisible(
        find.text('编辑会话参数'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('编辑会话参数'), findsOneWidget);
      expect(find.text('设置'), findsNothing);
    });
  });
}

/// 内存版 ApiConfigRepository，记录 insert/delete 调用供断言。
class _FakeApiConfigRepository implements ApiConfigRepository {
  final List<ApiConfig> _rows = [];
  final List<int> deletedIds = [];
  int _nextId = 1;

  @override
  Future<List<ApiConfig>> getAll() async => List.of(_rows);

  @override
  Future<ApiConfig?> getById(int id) async {
    for (final row in _rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  @override
  Future<int> insert(ApiConfig config) async {
    _rows.add(config.copyWith(id: _nextId));
    return _nextId++;
  }

  @override
  Future<void> update(ApiConfig config) async {
    final index = _rows.indexWhere((r) => r.id == config.id);
    if (index >= 0) _rows[index] = config;
  }

  @override
  Future<void> delete(int id) async {
    deletedIds.add(id);
    _rows.removeWhere((r) => r.id == id);
  }
}
