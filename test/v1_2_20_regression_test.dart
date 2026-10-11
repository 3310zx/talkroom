import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/application/providers/conversations_provider.dart';
import 'package:llm_chat_app/application/providers/messages_provider.dart';
import 'package:llm_chat_app/core/utils.dart';
import 'package:llm_chat_app/data/database/app_database.dart';
import 'package:llm_chat_app/domain/models/conversation.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/domain/models/message_search_hit.dart';
import 'package:llm_chat_app/domain/repositories/message_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v1.2.20 回归测试。
///
/// 覆盖：
/// - 问题③：标题/摘要空白脏数据清洗（cleanConversationText /
///   conversationDisplayTitle / conversationDisplaySummary）与
///   ConversationsNotifier.load 惰性清理写回；
/// - 问题②：流式增量节流合并（appendStreamingFragment 按节流周期合并，
///   flushStreaming 同步刷新终态前残余）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('问题③ 标题/摘要清洗', () {
    test('前导换行/全角空格/零宽字符被清洗', () {
      expect(cleanConversationText('\n\n  你好世界  '), '你好世界');
      expect(cleanConversationText('你好\u3000世界'), '你好 世界');
      expect(cleanConversationText('\u200B你好\u200B世界\u200D'), '你好世界');
      expect(cleanConversationText('a\nb\nc'), 'a b c');
    });

    test('空/空白输入返回空串', () {
      expect(cleanConversationText(null), '');
      expect(cleanConversationText(''), '');
      expect(cleanConversationText('   \n\t '), '');
    });

    test('空标题兜底「未命名会话」', () {
      expect(conversationDisplayTitle(''), '未命名会话');
      expect(conversationDisplayTitle('\n  \n'), '未命名会话');
      expect(conversationDisplayTitle('神明失误'), '神明失误');
    });

    test('空摘要兜底「暂无消息」', () {
      expect(conversationDisplaySummary(''), '暂无消息');
      expect(conversationDisplaySummary('\n\t'), '暂无消息');
      expect(conversationDisplaySummary('  正常内容  '), '正常内容');
    });
  });

  group('问题③ ConversationsNotifier 惰性清理', () {
    late AppDatabase appDb;
    late Directory tmpDir;
    late ConversationsNotifier notifier;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmpDir = Directory.systemTemp.createTempSync('llm_chat_v1220_test');
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
      notifier = ConversationsNotifier(appDb.conversationRepository);
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

    test('load 清洗存量脏标题并写回 DB', () async {
      // 构造脏数据：标题以换行开头、摘要为全空白字符。
      final repo = appDb.conversationRepository;
      final id = await repo.insert(Conversation(
        title: '\n\n  旧脏标题',
        lastMessage: '  \n\t ',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));

      await notifier.load();

      expect(notifier.state.length, 1);
      expect(notifier.state.first.title, '旧脏标题');
      expect(notifier.state.first.lastMessage, '');

      // 再次从 DB 读取应已是清洗后的值（惰性清理已写回）。
      final persisted = await repo.getById(id);
      expect(persisted, isNotNull);
      expect(persisted!.title, '旧脏标题');
    });

    test('纯空白标题兜底为「未命名会话」并写回', () async {
      final repo = appDb.conversationRepository;
      await repo.insert(Conversation(
        title: '\u200B  ',
        lastMessage: '有内容',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));

      await notifier.load();

      final dirty = notifier.state.where((c) => c.title == '未命名会话').toList();
      expect(dirty, isNotEmpty);
      expect(notifier.state.every((c) => c.lastMessage == '有内容' ||
          c.lastMessage.isEmpty), isTrue);
    });
  });

  group('问题② 流式增量节流合并', () {
    test('append 片段按节流合并，flushStreaming 同步刷新', () async {
      final notifier = MessagesNotifier(_NoopMessageRepository());
      // 造两条消息：一条目标 + 一条无关。
      final target = ChatMessage(
        id: 1,
        conversationId: 1,
        role: 'assistant',
        content: '',
        status: 'streaming',
        createdAt: 1,
      );
      final other = ChatMessage(
        id: 2,
        conversationId: 1,
        role: 'user',
        content: 'hi',
        status: 'done',
        createdAt: 2,
      );
      notifier.state = [target, other];

      // 60ms 节流窗口内连续 append 两次：state 暂不更新（Timer 未触发）。
      notifier.appendStreamingFragment(1, '你');
      notifier.appendStreamingFragment(1, '好');
      expect(notifier.state.first.content, '');

      // 流式结束：同步 flush 应合并全部 pending 一次到位。
      notifier.flushStreaming();
      expect(notifier.state.first.content, '你好');
      expect(notifier.state.first.status, 'streaming');

      // flush 后再次 flush 无副作用（pending 已清空）。
      notifier.flushStreaming();
      expect(notifier.state.first.content, '你好');

      // 无关消息引用未变（item 缓存 identical 判断依赖此特性）。
      expect(identical(notifier.state[1], other), isTrue);
    });

    test('appendReasoningFragment 同样节流合并', () async {
      final notifier = MessagesNotifier(_NoopMessageRepository());
      final target = ChatMessage(
        id: 1,
        conversationId: 1,
        role: 'assistant',
        content: '正文',
        status: 'streaming',
        createdAt: 1,
      );
      notifier.state = [target];

      notifier.appendReasoningFragment(1, '思考');
      notifier.appendReasoningFragment(1, '过程');
      expect(notifier.state.first.reasoningContent, isNull);

      notifier.flushStreaming();
      expect(notifier.state.first.reasoningContent, '思考过程');
    });
  });
}

/// 流式节流测试专用空仓储：仅构造用，不触发真实 IO。
class _NoopMessageRepository implements MessageRepository {
  @override
  Future<void> delete(int id) async {}

  @override
  Future<void> deleteByConversation(int conversationId) async {}

  @override
  Future<void> deleteFrom(int id) async {}

  @override
  Future<bool> existsByDeviceAndClientTs(String deviceId, int clientTs) async =>
      false;

  @override
  Future<ChatMessage?> findByServerId(int serverId) async => null;

  @override
  Future<ChatMessage?> getById(int id) async => null;

  @override
  Future<int> getMaxServerId() async => 0;

  @override
  Future<int> insert(ChatMessage message) async => 0;

  @override
  Future<List<ChatMessage>> listByConversation(int conversationId) async => [];

  @override
  Future<List<ChatMessage>> listByServerIdAfter({
    required int conversationId,
    required int afterServerId,
    int limit = 500,
  }) async =>
      [];

  @override
  Future<List<ChatMessage>> listByServerIdUpTo({
    required int conversationId,
    required int afterServerId,
    required int toServerId,
  }) async =>
      [];

  @override
  Future<List<ChatMessage>> listPendingUpload(String deviceId) async => [];

  @override
  Future<List<ChatMessage>> listPerformanceStats({int limit = 30}) async => [];

  @override
  Future<List<MessageSearchHit>> searchMessages(
    String keyword, {
    int limit = 100,
  }) async =>
      [];

  @override
  Future<void> update(ChatMessage message) async {}

  @override
  Future<List<ChatMessage>> insertWithServerIds(
      List<ChatMessage> messages) async =>
      [];

  @override
  Future<List<ChatMessage>> finalizeLocalMessages() async => [];

  @override
  Future<int> insertCacheHit(CacheHitRecord record) async => 0;

  @override
  Future<List<CacheHitRecord>> listCacheHits({int limit = 200}) async => [];

  @override
  Future<int> clearCacheHits() async => 0;
}
