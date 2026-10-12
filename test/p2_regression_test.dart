import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:llm_chat_app/data/database/app_database.dart';
import 'package:llm_chat_app/data/repositories/memory_repository_impl.dart';
import 'package:llm_chat_app/data/repositories/message_repository_impl.dart';
import 'package:llm_chat_app/domain/models/memory_item.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/presentation/widgets/message_bubble.dart';
import 'package:llm_chat_app/services/active_task_scheduler.dart';

/// 构造一个 version 10 的旧版内存库：messages 表缺失 duration_ms 列
/// （模拟 v1.2.16 性能图表上线前的老库），其余表仅建占位结构。
Future<Database> _openV10Db() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false, version: 10),
  );
  await db.execute('''
    CREATE TABLE messages (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      conversation_id INTEGER NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL,
      content_type TEXT NOT NULL DEFAULT 'text', status TEXT NOT NULL DEFAULT 'done',
      model_id TEXT, prompt_tokens INTEGER, completion_tokens INTEGER,
      error_message TEXT, created_at INTEGER NOT NULL, attachments TEXT,
      reasoning_content TEXT, reasoning_duration_ms INTEGER,
      reasoning_tokens INTEGER, cached_tokens INTEGER,
      device_id TEXT, server_id TEXT, updated_at INTEGER NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE api_configs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, base_url TEXT NOT NULL, api_key_ref TEXT NOT NULL,
      model_ids TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      favorite INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )''');
  return db;
}

/// 构造 v11 结构的内存库（含 memories 迁移所需前置表），再迁移到 v12。
Future<Database> _openV12Db() async {
  final db = await _openV10Db();
  await AppDatabase.runMigrations(db, 10, 12);
  return db;
}

void main() {
  group('P2-06 memory_summary 复合游标', () {
    test('新格式 createdAt:id 解析正确', () {
      final c = parseMemorySummaryCursor('1700000000000:42');
      expect(c.createdAt, 1700000000000);
      expect(c.id, 42);
    });

    test('老游标（纯数字）兼容：id 视为 0', () {
      final c = parseMemorySummaryCursor('1700000000000');
      expect(c.createdAt, 1700000000000);
      expect(c.id, 0);
    });

    test('空 / 非法游标回退到起点', () {
      expect(parseMemorySummaryCursor(''), (createdAt: 0, id: 0));
      expect(parseMemorySummaryCursor('abc'), (createdAt: 0, id: 0));
    });

    test('序列化往返一致', () {
      expect(formatMemorySummaryCursor(1700000000000, 42),
          '1700000000000:42');
      expect(formatMemorySummaryCursor(1700000000000, null),
          '1700000000000:0');
    });
  });

  group('P2-08 记忆文本重叠判定', () {
    test('短文本（<10 字）仅包含/相等才判重，不做 Jaccard', () {
      // 字符集合重合率高达 66%（你好/您好），但短文本不允许 Jaccard 判重。
      expect(memoryOverlap('你好', '您好'), isFalse);
      expect(memoryOverlap('好的', '好的'), isTrue);
      expect(memoryOverlap('今天天气不错', '今天天气不错'), isTrue);
      expect(memoryOverlap('今天天气不错', '天气'), isTrue); // 包含关系
    });

    test('长文本按 Jaccard 30% 判定重叠', () {
      expect(memoryOverlap('深度学习模型训练技巧总结', '深度学习模型训练技巧总结'),
          isTrue);
      expect(memoryOverlap('深度学习模型训练技巧总结', '深度学习模型部署实践指南'),
          isTrue);
      expect(memoryOverlap('深度学习的数学基础教材', '前端框架 Vue 的快速上手教程'),
          isFalse);
    });

    test('空文本不判重', () {
      expect(memoryOverlap('', '内容'), isFalse);
      expect(memoryOverlap('内容', '  '), isFalse);
    });
  });

  group('P2-09 超长消息截断', () {
    test('单条超长消息截断到预算，不丢弃、不卡死', () {
      final huge = ChatMessage(
        id: 1,
        conversationId: 1,
        role: 'user',
        content: '长' * 20000, // 20000 字 >> 8000 预算
        createdAt: 1,
        updatedAt: 1,
      );
      final picked = truncateMemorySummaryCandidates(
        [huge],
        maxMessages: 50,
        maxChars: 8000,
      );
      expect(picked, hasLength(1));
      expect(picked.single.content.length, 8000);
    });

    test('预算不足时按序截断并停止追加', () {
      final msgs = [
        ChatMessage(
          id: 1,
          conversationId: 1,
          role: 'user',
          content: '甲' * 6000,
          createdAt: 1,
          updatedAt: 1,
        ),
        ChatMessage(
          id: 2,
          conversationId: 1,
          role: 'user',
          content: '乙' * 6000,
          createdAt: 2,
          updatedAt: 2,
        ),
      ];
      final picked = truncateMemorySummaryCandidates(
        msgs,
        maxMessages: 50,
        maxChars: 8000,
      );
      // 第一条占满预算，第二条截断剩余 2000 字，全部纳入，游标可推进。
      expect(picked, hasLength(2));
      expect(picked[0].content.length, 6000);
      expect(picked[1].content.length, 2000);
    });

    test('空内容消息跳过，游标仍推进到非空消息', () {
      final msgs = [
        ChatMessage(
          id: 1,
          conversationId: 1,
          role: 'user',
          content: '   ',
          createdAt: 1,
          updatedAt: 1,
        ),
        ChatMessage(
          id: 2,
          conversationId: 1,
          role: 'user',
          content: '有效内容',
          createdAt: 2,
          updatedAt: 2,
        ),
      ];
      final picked = truncateMemorySummaryCandidates(msgs);
      expect(picked, hasLength(1));
      expect(picked.single.id, 2);
      expect(picked.single.content, '有效内容');
    });
  });

  group('记忆库 CRUD（P2-12）', () {
    late Database db;
    late MemoryRepositoryImpl repo;

    setUp(() async {
      db = await _openV12Db();
      repo = MemoryRepositoryImpl(AppDatabase.forTesting(db));
    });

    tearDown(() async {
      await db.close();
    });

    test('insert / listByConversation / listAll / search 闭环', () async {
      final id1 = await repo.insert(MemoryItem(
        conversationId: 7,
        content: '第一条记忆：会议结论',
        kind: 'manual',
        sourceMessageId: 101,
        createdAt: 1,
        updatedAt: 1,
      ));
      await repo.insert(MemoryItem(
        conversationId: 7,
        content: '第二条记忆：待办事项',
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 2,
        updatedAt: 2,
      ));
      await repo.insert(MemoryItem(
        conversationId: 8,
        content: '另一会话的记忆',
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 3,
        updatedAt: 3,
      ));

      final conv7 = await repo.listByConversation(7);
      expect(conv7, hasLength(2));
      expect(conv7.first.content, '第二条记忆：待办事项'); // 更新时间倒序

      final all = await repo.listAll();
      expect(all, hasLength(3));

      final hit = await repo.search('会议');
      expect(hit, hasLength(1));
      expect(hit.single.id, id1);

      expect(await repo.search('  '), isEmpty); // 空关键词返回空
    });

    test('update / delete / deleteByConversation', () async {
      final id = await repo.insert(MemoryItem(
        conversationId: 9,
        content: '原文',
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 1,
        updatedAt: 1,
      ));
      await repo.update(MemoryItem(
        id: id,
        conversationId: 9,
        content: '更新后的内容',
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 1,
        updatedAt: 2,
      ));
      var rows = await repo.listByConversation(9);
      expect(rows.single.content, '更新后的内容');

      await repo.delete(id);
      expect(await repo.listByConversation(9), isEmpty);

      await repo.insert(MemoryItem(
        conversationId: 10,
        content: 'a',
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 1,
        updatedAt: 1,
      ));
      await repo.insert(MemoryItem(
        conversationId: 10,
        content: 'b',
        kind: 'auto',
        sourceMessageId: null,
        createdAt: 2,
        updatedAt: 2,
      ));
      await repo.deleteByConversation(10);
      expect(await repo.listByConversation(10), isEmpty);
    });

    test('lastAutoSummaryAt 仅统计 auto 类型', () async {
      expect(await repo.lastAutoSummaryAt(11), isNull);
      await repo.insert(MemoryItem(
        conversationId: 11,
        content: '手动',
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 1,
        updatedAt: 1,
      ));
      expect(await repo.lastAutoSummaryAt(11), isNull);
      await repo.insert(MemoryItem(
        conversationId: 11,
        content: '自动整理',
        kind: 'auto',
        sourceMessageId: null,
        createdAt: 2,
        updatedAt: 200,
      ));
      expect(await repo.lastAutoSummaryAt(11), 200);
    });

    test('注入边界：超长内容与空内容不崩溃、可检索', () async {
      final long = '超长记忆' * 3000; // 12000 字
      final id = await repo.insert(MemoryItem(
        conversationId: 12,
        content: long,
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 1,
        updatedAt: 1,
      ));
      expect(id, greaterThan(0));
      expect((await repo.listByConversation(12)).single.content.length, 12000);

      await repo.insert(MemoryItem(
        conversationId: 12,
        content: '',
        kind: 'manual',
        sourceMessageId: null,
        createdAt: 2,
        updatedAt: 2,
      ));
      expect(await repo.listByConversation(12), hasLength(2));
      expect(await repo.search('超长记忆'), hasLength(1));
    });
  });

  group('v10 -> v12 迁移链（memories 表）', () {
    test('升级后含 duration_ms 列、memories 表与索引，且旧数据保留', () async {
      final db = await _openV10Db();
      try {
        await db.insert('messages', {
          'conversation_id': 1,
          'role': 'user',
          'content': '迁移前的旧消息',
          'status': 'done',
          'created_at': 100,
          'updated_at': 100,
        });
        await AppDatabase.runMigrations(db, 10, 12);

        final msgCols = await db.rawQuery('PRAGMA table_info(messages)');
        expect(msgCols.map((c) => c['name']), contains('duration_ms'));

        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='memories'");
        expect(tables, hasLength(1));

        final idx = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_memories_conv'");
        expect(idx, hasLength(1));

        final kept = await db.rawQuery(
            "SELECT content FROM messages WHERE created_at = 100");
        expect(kept.single['content'], '迁移前的旧消息');

        // 迁移后可直接写入并读取 memories（对齐 _onCreate schema）。
        await db.insert('memories', {
          'conversation_id': 1,
          'content': '迁移后新建的记忆',
          'kind': 'manual',
          'source_message_id': null,
          'pinned': 0,
          'created_at': 200,
          'updated_at': 200,
        });
        final mem = await db.rawQuery('SELECT content FROM memories');
        expect(mem.single['content'], '迁移后新建的记忆');
      } finally {
        await db.close();
      }
    });

    test('迁移链幂等：重复执行不重复建表、不报错', () async {
      final db = await _openV10Db();
      try {
        await AppDatabase.runMigrations(db, 10, 12);
        await AppDatabase.runMigrations(db, 10, 12);

        final tables = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='memories'");
        expect(tables, hasLength(1));
        final idx = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_memories_conv'");
        expect(idx, hasLength(1));
      } finally {
        await db.close();
      }
    });
  });

  group('P2-04 _MessageActionBar 显隐规则', () {
    Widget wrap(Widget child) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('done 消息完整显示复制/点赞/不喜欢/分享/更多', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        isUser: false,
        content: '完成的消息',
        status: 'done',
      )));
      expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.byIcon(Icons.thumb_down_outlined), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    });

    testWidgets('streaming 消息工具栏完全隐藏', (tester) async {
      await tester.pumpWidget(wrap(const MessageBubble(
        isUser: false,
        content: '',
        status: 'streaming',
      )));
      expect(find.byIcon(Icons.copy_outlined), findsNothing);
      expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
      expect(find.byIcon(Icons.thumb_down_outlined), findsNothing);
      expect(find.byIcon(Icons.share_outlined), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('error / stopped 仅保留更多入口', (tester) async {
      for (final status in ['error', 'stopped']) {
        await tester.pumpWidget(wrap(MessageBubble(
          isUser: false,
          content: '失败消息',
          status: status,
          onRetry: () {},
        )));
        expect(find.byIcon(Icons.copy_outlined), findsNothing,
            reason: '$status 不应显示复制');
        expect(find.byIcon(Icons.thumb_up_outlined), findsNothing,
            reason: '$status 不应显示点赞');
        expect(find.byIcon(Icons.share_outlined), findsNothing,
            reason: '$status 不应显示分享');
        expect(find.byIcon(Icons.more_horiz), findsOneWidget,
            reason: '$status 应保留更多入口');
      }
    });

    testWidgets('error 更多菜单仅含重试，不出现变体/保存/编辑', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(wrap(MessageBubble(
        isUser: false,
        content: '失败消息',
        status: 'error',
        onRetry: () {},
        onVariantReply: (_) {},
        onSaveToMemory: () {},
        onEdit: () {},
        onDelete: () {},
      )));
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      // 气泡内的「重试」按钮 + 菜单中的「重试」各一处。
      expect(find.text('重试'), findsNWidgets(2));
      expect(find.text('变体回复'), findsNothing);
      expect(find.text('保存到记忆库'), findsNothing);
      expect(find.text('编辑'), findsNothing);
    });
  });

  group('变体保留/删除两分支消息序列（P2-12/P1-01）', () {
    late Database db;
    late MessageRepositoryImpl repo;

    setUp(() async {
      db = await _openV12Db();
      repo = MessageRepositoryImpl(AppDatabase.forTesting(db));
    });

    tearDown(() async {
      await db.close();
    });

    /// 种子会话：[提问一, 回答一, 提问二, 回答二]，返回各消息 id。
    Future<List<int>> seed() async {
      final ids = <int>[];
      final rows = [
        ('user', '提问一', 1),
        ('assistant', '回答一', 2),
        ('user', '提问二', 3),
        ('assistant', '回答二', 4),
      ];
      for (final r in rows) {
        ids.add(await repo.insert(ChatMessage(
          conversationId: 1,
          role: r.$1,
          content: r.$2,
          createdAt: r.$3,
          updatedAt: r.$3,
        )));
      }
      return ids;
    }

    /// 复刻 _sendWithVariant / _retry 的「anchor 前最近 user」查找逻辑。
    Future<int?> findPreviousUserStart(int anchorId) async {
      final msgs = await repo.listByConversation(1);
      final anchorIndex = msgs.indexWhere((m) => m.id == anchorId);
      for (var i = anchorIndex - 1; i >= 0; i--) {
        if (msgs[i].role == 'user') return msgs[i].id;
      }
      return null;
    }

    test('删除分支：删除原用户消息及其后全部，序列收敛到其之前', () async {
      final ids = await seed();
      final anchorId = ids.last; // 回答二
      final userStart = await findPreviousUserStart(anchorId); // 提问二
      expect(userStart, isNotNull);

      await repo.deleteFrom(userStart!);
      final rest = await repo.listByConversation(1);
      expect(rest.map((m) => m.content), ['提问一', '回答一']);
    });

    test('保留分支：不删除原消息，新回复追加到末尾且原序列完整', () async {
      await seed();
      final newId = await repo.insert(ChatMessage(
        conversationId: 1,
        role: 'assistant',
        content: '变体新回复',
        createdAt: 5,
        updatedAt: 5,
      ));
      final msgs = await repo.listByConversation(1);
      expect(
        msgs.map((m) => m.content).toList(),
        ['提问一', '回答一', '提问二', '回答二', '变体新回复'],
      );
      expect(msgs.last.id, newId);
    });

    test('P1-01 重试语义：删失败回复及其前用户消息后重发，无重复提问', () async {
      final ids = await seed();
      final failedId = ids.last;
      // 回答二变为失败终态（error），作为重试锚点。
      await repo.update((await repo.listByConversation(1))
          .last
          .copyWith(status: 'error'));

      final userStart = await findPreviousUserStart(failedId);
      await repo.deleteFrom(userStart!);
      final rest = await repo.listByConversation(1);
      expect(rest.map((m) => m.content), ['提问一', '回答一']);

      // 重发原文（模拟 _retry 落库用户消息），会话中提问二仅此一条。
      await repo.insert(ChatMessage(
        conversationId: 1,
        role: 'user',
        content: '提问二',
        createdAt: 6,
        updatedAt: 6,
      ));
      final after = await repo.listByConversation(1);
      expect(
        after.map((m) => m.content).toList(),
        ['提问一', '回答一', '提问二'],
      );
      expect(after.where((m) => m.role == 'user' && m.content == '提问二'),
          hasLength(1));
    });
  });
}
