import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/services/local_server/pair_guard.dart';
import 'package:llm_chat_app/services/local_server/sync_conflict.dart';
import 'package:llm_chat_app/services/sync/sync_json.dart';

void main() {
  group('PairGuard', () {
    test('generateCode 生成 6 位数字码', () {
      final code = PairGuard.generateCode();
      expect(code, hasLength(6));
      expect(RegExp(r'^\d{6}$').hasMatch(code), isTrue);
    });

    test('正确配对码通过并清空防猜状态', () {
      final guard = PairGuard(failCount: 2, lockUntil: 0);
      expect(guard.check(expectedCode: '123456', input: '123456'),
          PairCheckResult.ok);
      expect(guard.failCount, 0);
      expect(guard.isLocked, isFalse);
    });

    test('错误配对码累计失败次数', () {
      final guard = PairGuard();
      expect(guard.check(expectedCode: '123456', input: '000000'),
          PairCheckResult.invalid);
      expect(guard.failCount, 1);
    });

    test('连续错误达到阈值后锁定', () {
      var now = 1000000;
      final guard = PairGuard(
        maxFailures: 3,
        lockDurationMs: 60000,
        now: () => DateTime.fromMillisecondsSinceEpoch(now),
      );
      expect(guard.check(expectedCode: '123456', input: '111111'),
          PairCheckResult.invalid);
      expect(guard.check(expectedCode: '123456', input: '222222'),
          PairCheckResult.invalid);
      expect(guard.check(expectedCode: '123456', input: '333333'),
          PairCheckResult.invalid);
      expect(guard.isLocked, isTrue);
      expect(guard.remainingLockMs, greaterThan(0));
      // 锁定期内即使输入正确也返回 locked
      expect(guard.check(expectedCode: '123456', input: '123456'),
          PairCheckResult.locked);
    });

    test('锁定到期后自动解锁', () {
      var now = 1000000;
      final guard = PairGuard(
        maxFailures: 1,
        lockDurationMs: 60000,
        now: () => DateTime.fromMillisecondsSinceEpoch(now),
      );
      guard.check(expectedCode: '123456', input: '000000');
      expect(guard.isLocked, isTrue);
      now += 60001;
      expect(guard.isLocked, isFalse);
      expect(guard.check(expectedCode: '123456', input: '123456'),
          PairCheckResult.ok);
    });
  });

  group('SyncConflict', () {
    test('sortForServerInsert 按客户端时间戳排序', () {
      final sorted = SyncConflict.sortForServerInsert(
        ['a', 'b', 'c'],
        clientTsOf: (s) => s == 'a'
            ? 3
            : s == 'b'
                ? 1
                : 2,
        deviceIdOf: (s) => s,
        deviceTypeOf: (_) => 'client',
      );
      expect(sorted, ['b', 'c', 'a']);
    });

    test('时间戳相同则电脑端(server)优先于手机端(client)', () {
      final sorted = SyncConflict.sortForServerInsert(
        ['phone', 'pc'],
        clientTsOf: (_) => 100,
        deviceIdOf: (s) => s,
        deviceTypeOf: (s) => s == 'pc' ? 'server' : 'client',
      );
      expect(sorted, ['pc', 'phone']);
    });

    test('shouldServerWin：时间戳新的胜', () {
      expect(
        SyncConflict.shouldServerWin(
          incomingUpdatedAt: 200,
          localUpdatedAt: 100,
          incomingPriority: 1,
          localPriority: 0,
          incomingServerId: 1,
          localServerId: 1,
        ),
        isTrue,
      );
      expect(
        SyncConflict.shouldServerWin(
          incomingUpdatedAt: 100,
          localUpdatedAt: 200,
          incomingPriority: 1,
          localPriority: 0,
          incomingServerId: 1,
          localServerId: 1,
        ),
        isFalse,
      );
    });

    test('shouldServerWin：时间戳相同则设备优先级高(电脑)的胜', () {
      expect(
        SyncConflict.shouldServerWin(
          incomingUpdatedAt: 100,
          localUpdatedAt: 100,
          incomingPriority: 0,
          localPriority: 1,
          incomingServerId: 1,
          localServerId: 1,
        ),
        isTrue,
      );
    });

    test('shouldServerWin：仍相同则以 server_id 大者为准', () {
      expect(
        SyncConflict.shouldServerWin(
          incomingUpdatedAt: 100,
          localUpdatedAt: 100,
          incomingPriority: 1,
          localPriority: 1,
          incomingServerId: 5,
          localServerId: 3,
        ),
        isTrue,
      );
    });
  });

  group('SyncJson', () {
    test('ChatMessage 与同步 JSON 往返一致', () {
      final m = ChatMessage(
        id: 7,
        conversationId: 2,
        role: 'assistant',
        content: '你好',
        contentType: 'text',
        status: 'done',
        modelId: 'gpt-4o',
        promptTokens: 12,
        completionTokens: 8,
        errorMessage: null,
        createdAt: 12345,
        deviceId: 'dev-1',
        serverId: 42,
        updatedAt: 67890,
      );
      final json = toSyncJson(m);
      final back = fromSyncJson(json);
      expect(back.conversationId, 2);
      expect(back.role, 'assistant');
      expect(back.content, '你好');
      expect(back.deviceId, 'dev-1');
      expect(back.serverId, 42);
      expect(back.updatedAt, 67890);
      expect(back.createdAt, 12345);
    });

    test('缺字段时使用默认值', () {
      final back = fromSyncJson(<String, Object?>{});
      expect(back.conversationId, 0);
      expect(back.role, 'user');
      expect(back.content, '');
      expect(back.status, 'done');
      expect(back.serverId, isNull);
    });
  });
}
