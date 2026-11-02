import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/core/constants.dart';
import 'package:llm_chat_app/domain/models/conversation.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/services/context_compressor.dart';
import 'package:llm_chat_app/services/llm_client.dart';

/// 非流式响应假适配器：记录请求体，返回固定摘要文本。
class _FakeSummaryAdapter implements HttpClientAdapter {
  _FakeSummaryAdapter({this.summary = '合并后的摘要'});

  final String summary;
  Map<String, dynamic>? lastBody;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    if (data is Map<String, dynamic>) lastBody = data;
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': summary},
          },
        ],
        'usage': {'prompt_tokens': 10, 'completion_tokens': 5},
      }),
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ChatMessage _msg(int id, String role, String content) => ChatMessage(
      id: id,
      conversationId: 1,
      role: role,
      content: content,
      status: 'done',
      createdAt: id,
    );

void main() {
  group('上下文用量估算（中英混合保守加权）', () {
    test('中文 1 字符 ≈ 1 token', () {
      expect(ContextUsageEstimator.estimateTokens('你好世界'), 4);
    });

    test('英文 4 字符 ≈ 1 token，向上取整', () {
      expect(ContextUsageEstimator.estimateTokens('abcd'), 1);
      expect(ContextUsageEstimator.estimateTokens('abcde'), 2);
    });

    test('中英混合分别计算后相加', () {
      // 2 个中文（2 token）+ 8 个英文（2 token）= 4
      expect(ContextUsageEstimator.estimateTokens('你好abcdefgh'), 4);
    });

    test('空字符串为 0', () {
      expect(ContextUsageEstimator.estimateTokens(''), 0);
    });

    test('消息数组估算包含结构开销', () {
      final tokens = ContextUsageEstimator.estimateMessagesTokens([
        {'role': 'system', 'content': '你是一个助手'},
        {'role': 'user', 'content': '你好'},
      ]);
      // messagesOverhead(3) + 2*(perMessageOverhead(4)) + 8 个中文字符
      expect(tokens, 3 + 8 + 8);
    });

    test('估算消息体内容为空时仅计结构开销', () {
      expect(
        ContextUsageEstimator.estimateMessageTokens({'role': 'user'}),
        ContextUsageEstimator.perMessageOverhead,
      );
    });
  });

  group('压缩触发阈值', () {
    test('默认配置：窗口 64000 · 阈值 70% → 44800 token 触发', () {
      const config = ContextCompressionConfig();
      expect(config.contextWindow, AppConstants.defaultContextWindowTokens);
      expect(config.triggerPercent, AppConstants.defaultContextTriggerPercent);
      expect(config.triggerTokens, 44800);
      expect(config.shouldCompress(44799), isFalse);
      expect(config.shouldCompress(44800), isTrue);
    });

    test('关闭开关后不再触发', () {
      const config = ContextCompressionConfig(enabled: false);
      expect(config.shouldCompress(999999), isFalse);
    });

    test('自定义窗口与阈值生效', () {
      const config = ContextCompressionConfig(
        contextWindow: 10000,
        triggerPercent: 50,
      );
      expect(config.triggerTokens, 5000);
      expect(config.shouldCompress(5000), isTrue);
    });

    test('设置读取：缺省回落默认值，显式 0 关闭，非法值回落', () {
      final defaults = ContextCompressionConfig.fromSettings(const {});
      expect(defaults.enabled, isTrue);
      expect(defaults.contextWindow, 64000);
      expect(defaults.triggerPercent, 70);
      expect(defaults.tailKeepTokens, AppConstants.defaultContextTailKeepTokens);
      expect(defaults.summaryMaxChars, AppConstants.defaultContextSummaryMaxChars);

      final off = ContextCompressionConfig.fromSettings(
          const {AppConstants.settingContextCompressionEnabled: '0'});
      expect(off.enabled, isFalse);

      final customized = ContextCompressionConfig.fromSettings(const {
        AppConstants.settingContextWindowTokens: '128000',
        AppConstants.settingContextTriggerPercent: '60',
        AppConstants.settingContextTailKeepTokens: '16000',
        AppConstants.settingContextSummaryMaxChars: '1000',
      });
      expect(customized.contextWindow, 128000);
      expect(customized.triggerPercent, 60);
      expect(customized.tailKeepTokens, 16000);
      expect(customized.summaryMaxChars, 1000);

      final invalid = ContextCompressionConfig.fromSettings(const {
        AppConstants.settingContextWindowTokens: 'abc',
        AppConstants.settingContextTriggerPercent: '150',
        AppConstants.settingContextTailKeepTokens: '-5',
        AppConstants.settingContextSummaryMaxChars: '0',
      });
      expect(invalid.contextWindow, 64000);
      expect(invalid.triggerPercent, 100); // 超上限按上限收敛
      expect(invalid.tailKeepTokens, AppConstants.defaultContextTailKeepTokens);
      expect(invalid.summaryMaxChars, AppConstants.defaultContextSummaryMaxChars);
    });
  });

  group('分层保留尾部消息', () {
    test('尾部预算内保留最近消息，更早消息进入待压缩区', () {
      final history = [
        _msg(1, 'user', 'a' * 100),
        _msg(2, 'assistant', 'b' * 100),
        _msg(3, 'user', 'c' * 100),
      ];
      final split = ContextCompressor().splitForTail(history, 60);
      // 每条约 100 字符英文字符 ≈ 25 token + 4 结构开销 = 29
      expect(split.tail.length, 2);
      expect(split.older.map((m) => m.id), [1]);
      expect(split.tail.map((m) => m.id), [2, 3]);
    });

    test('至少保留一条消息（预算极小也不清空尾部）', () {
      final history = [_msg(1, 'user', 'x' * 400), _msg(2, 'assistant', 'y' * 400)];
      final split = ContextCompressor().splitForTail(history, 1);
      expect(split.tail.length, 1);
      expect(split.tail.single.id, 2);
      expect(split.older.length, 1);
    });

    test('空历史返回空结果', () {
      final split = ContextCompressor().splitForTail(const [], 1000);
      expect(split.older, isEmpty);
      expect(split.tail, isEmpty);
    });
  });

  group('摘要合并提示词', () {
    test('已有摘要与新内容同时进入提示词，且标注不丢信息', () {
      final prompt = ContextCompressor().buildMergePrompt(
        existingSummary: '用户偏好简洁回答',
        newContent: '用户：帮我写周报\n助手：好的',
        summaryMaxChars: 500,
      );
      expect(prompt, contains('【已有摘要】'));
      expect(prompt, contains('用户偏好简洁回答'));
      expect(prompt, contains('【新增待压缩对话】'));
      expect(prompt, contains('帮我写周报'));
      expect(prompt, contains('不超过 500 字'));
      expect(prompt, contains('待办'));
    });

    test('首次压缩标注暂无已有摘要', () {
      final prompt = ContextCompressor().buildMergePrompt(
        existingSummary: null,
        newContent: '内容',
        summaryMaxChars: 300,
      );
      expect(prompt, contains('本次为首次压缩'));
    });
  });

  group('压缩执行（非流式摘要 + 合并已有摘要）', () {
    test('首次压缩：生成摘要并返回已压缩到的消息 id', () async {
      final adapter = _FakeSummaryAdapter(summary: '这是首次摘要');
      final compressor = ContextCompressor(client: _client(adapter));

      final history = [
        _msg(1, 'user', '第一条'),
        _msg(2, 'assistant', '第二条'),
        _msg(3, 'user', '第三条'),
      ];
      final result = await compressor.compress(
        history: history,
        existingSummary: null,
        config: const ContextCompressionConfig(tailKeepTokens: 5),
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'test-model',
      );

      expect(result, isNotNull);
      expect(result!.summary, '这是首次摘要');
      // 尾部预算 5 只保留最后一条，前两条被压缩
      expect(result.compressedCount, 2);
      expect(result.uptoMessageId, 2);
      expect(result.beforeTokens, greaterThan(0));
      expect(result.afterTokens,
          ContextUsageEstimator.estimateTokens('这是首次摘要'));
      expect(result.savedTokens, greaterThan(0));

      // 请求体是非流式摘要调用，且带 system + user 两条消息
      final body = adapter.lastBody!;
      expect(body['stream'], isFalse);
      final messages = body['messages'] as List<dynamic>;
      expect(messages.length, 2);
      expect((messages.first as Map)['role'], 'system');
      expect(((messages.last as Map)['content'] as String), contains('暂无'));
    });

    test('二次压缩：已有摘要与新内容一起交给模型合并', () async {
      final adapter = _FakeSummaryAdapter(summary: '合并后的新摘要');
      final compressor = ContextCompressor(client: _client(adapter));

      final history = [
        _msg(4, 'user', '新的问题'),
        _msg(5, 'assistant', '新的回答'),
        _msg(6, 'user', '还需要保留'),
      ];
      final result = await compressor.compress(
        history: history,
        existingSummary: '旧摘要：用户喜欢中文回答',
        config: const ContextCompressionConfig(tailKeepTokens: 5),
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'test-model',
      );

      expect(result!.summary, '合并后的新摘要');
      final prompt =
          ((adapter.lastBody!['messages'] as List).last as Map)['content']
              as String;
      expect(prompt, contains('旧摘要：用户喜欢中文回答'));
      expect(prompt, contains('新的问题'));
    });

    test('无待压缩消息时返回 null（不调用模型）', () async {
      final adapter = _FakeSummaryAdapter();
      final compressor = ContextCompressor(client: _client(adapter));
      final result = await compressor.compress(
        history: [_msg(1, 'user', '只有一条')],
        existingSummary: null,
        config: const ContextCompressionConfig(tailKeepTokens: 20000),
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'test-model',
      );
      expect(result, isNull);
      expect(adapter.lastBody, isNull);
    });

    test('摘要超长时按配置字数截断', () async {
      final adapter = _FakeSummaryAdapter(summary: '长' * 50);
      final compressor = ContextCompressor(client: _client(adapter));
      final result = await compressor.compress(
        history: [
          _msg(1, 'user', '一' * 20),
          _msg(2, 'assistant', '二' * 20),
          _msg(3, 'user', '三' * 20),
        ],
        existingSummary: null,
        config: const ContextCompressionConfig(
          tailKeepTokens: 5,
          summaryMaxChars: 10,
        ),
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'test-model',
      );
      expect(result!.summary.length, 11); // 10 字 + 省略号
      expect(result.summary.endsWith('…'), isTrue);
    });

    test('模型返回空摘要时抛出 LlmException（调用方静默降级）', () async {
      final adapter = _FakeSummaryAdapter(summary: '');
      final compressor = ContextCompressor(client: _client(adapter));
      expect(
        () => compressor.compress(
          history: [
            _msg(1, 'user', '一' * 20),
            _msg(2, 'assistant', '二' * 20),
            _msg(3, 'user', '三' * 20),
          ],
          existingSummary: null,
          config: const ContextCompressionConfig(tailKeepTokens: 5),
          baseUrl: 'https://example.com/v1',
          apiKey: 'sk-test',
          model: 'test-model',
        ),
        throwsA(isA<LlmException>()),
      );
    });
  });

  group('请求组装（摘要段注入 + 跳过已压缩消息）', () {
    test('有摘要时只发送摘要之后的未压缩消息', () {
      final conversation = Conversation(
        id: 1,
        title: 't',
        updatedAt: 0,
        createdAt: 0,
        contextSummary: '此前的历史摘要',
        contextSummaryUptoId: 3,
      );
      final all = [
        _msg(1, 'user', '旧一'),
        _msg(2, 'assistant', '旧二'),
        _msg(3, 'user', '旧三'),
        _msg(4, 'user', '新一'),
        _msg(5, 'assistant', '新二'),
      ];
      final upto = conversation.contextSummaryUptoId ?? 0;
      final remaining = all.where((m) => (m.id ?? 0) > upto).toList();
      expect(remaining.map((m) => m.id), [4, 5]);
      expect(conversation.contextSummary, '此前的历史摘要');
    });

    test('老会话无摘要时走全量历史（不丢消息）', () {
      final conversation = Conversation(
        id: 1,
        title: 't',
        updatedAt: 0,
        createdAt: 0,
      );
      final all = [_msg(1, 'user', '旧一'), _msg(2, 'assistant', '旧二')];
      final upto = conversation.contextSummaryUptoId ?? 0;
      final remaining = all.where((m) => (m.id ?? 0) > upto).toList();
      expect(remaining.length, 2);
      expect((conversation.contextSummary ?? '').isEmpty, isTrue);
    });

    test('摘要段标题常量用于请求注入', () {
      expect(AppConstants.contextSummarySectionTitle, '历史对话摘要');
    });
  });

  group('自动压缩失败熔断（v1.2.24）', () {
    test('连续失败计数递增，第 3 次触发熔断', () {
      final breaker = AutoCompressionCircuitBreaker();
      expect(breaker.consecutiveFailures, 0);
      expect(breaker.isOpen, isFalse);

      expect(breaker.recordFailure(), isFalse);
      expect(breaker.consecutiveFailures, 1);
      expect(breaker.allowsAutoCompression, isTrue);

      expect(breaker.recordFailure(), isFalse);
      expect(breaker.consecutiveFailures, 2);
      expect(breaker.allowsAutoCompression, isTrue);

      // 第 3 次失败当次触发熔断，返回 true 用于提示一次。
      expect(breaker.recordFailure(), isTrue);
      expect(breaker.consecutiveFailures, 3);
      expect(breaker.isOpen, isTrue);
      expect(breaker.allowsAutoCompression, isFalse);
    });

    test('熔断后继续失败不再重复提示', () {
      final breaker = AutoCompressionCircuitBreaker();
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure();
      }
      expect(breaker.recordFailure(), isFalse);
      expect(breaker.consecutiveFailures, 4);
    });

    test('手动压缩成功（recordSuccess）清零失败计数并解除熔断', () {
      final breaker = AutoCompressionCircuitBreaker();
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure();
      }
      expect(breaker.isOpen, isTrue);

      breaker.recordSuccess();
      expect(breaker.consecutiveFailures, 0);
      expect(breaker.isOpen, isFalse);
      expect(breaker.allowsAutoCompression, isTrue);
    });

    test('切换会话重置失败计数', () {
      final breaker = AutoCompressionCircuitBreaker();
      breaker.bindConversation(1);
      for (var i = 0; i < 3; i++) {
        breaker.recordFailure();
      }
      expect(breaker.isOpen, isTrue);

      // 切到另一个会话 → 计数清零，自动压缩恢复尝试。
      breaker.bindConversation(2);
      expect(breaker.consecutiveFailures, 0);
      expect(breaker.allowsAutoCompression, isTrue);
    });

    test('同一会话重复绑定不清零', () {
      final breaker = AutoCompressionCircuitBreaker();
      breaker.bindConversation(1);
      breaker.recordFailure();
      breaker.recordFailure();
      breaker.bindConversation(1);
      expect(breaker.consecutiveFailures, 2);
    });

    test('熔断提示为中文且含次数与手动重试指引', () {
      final breaker = AutoCompressionCircuitBreaker();
      expect(breaker.pauseHint, contains('3 次'));
      expect(breaker.pauseHint, contains('暂停自动压缩'));
      expect(breaker.pauseHint, contains('手动重试'));
    });
  });

  group('摘要 prompt 保留用户原话（v1.2.24）', () {
    test('要求保留用户关键指令与偏好原话（简短引用、非全文照抄）', () {
      final prompt = ContextCompressor().buildMergePrompt(
        existingSummary: null,
        newContent: '用户：只改中文文案，别动英文\n助手：好的',
        summaryMaxChars: 400,
      );
      expect(prompt, contains('保留用户的关键指令与偏好原话'));
      expect(prompt, contains('简短引用'));
      expect(prompt, contains('非全文照抄'));
    });

    test('原约束保持不变（不臆造 / 只输出正文 / 字数上限）', () {
      final prompt = ContextCompressor().buildMergePrompt(
        existingSummary: '已有摘要内容',
        newContent: '用户：继续',
        summaryMaxChars: 300,
      );
      expect(prompt, contains('不臆造任何内容'));
      expect(prompt, contains('只输出摘要正文'));
      expect(prompt, contains('不超过 300 字'));
      expect(prompt, contains('已有摘要内容'));
    });
  });
}

LlmClient _client(HttpClientAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return LlmClient(dio: dio);
}
