import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:llm_chat_app/core/constants.dart';
import 'package:llm_chat_app/domain/models/message.dart';
import 'package:llm_chat_app/services/backup/backup_models.dart';
import 'package:llm_chat_app/services/context_assembler.dart';
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

ChatMessage _msg(
  int id,
  String role,
  String content, {
  List<MessageAttachment> attachments = const [],
}) =>
    ChatMessage(
      id: id,
      conversationId: 1,
      role: role,
      content: content,
      status: 'done',
      createdAt: id,
      attachments: attachments,
    );

/// 与 `chat_page._buildMultimodalContent` 完全一致的多模态拼装口径：
/// 无附件时返回纯文本；有附件时返回 text / image_url / file 片段数组。
dynamic _buildContent(String text, List<MessageAttachment> attachments) {
  if (attachments.isEmpty) return text;
  final parts = <Map<String, dynamic>>[];
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) {
    parts.add({'type': 'text', 'text': trimmed});
  }
  for (final att in attachments) {
    if (att.isImage) {
      final data = att.dataBase64;
      if (data != null && data.isNotEmpty) {
        parts.add({
          'type': 'image_url',
          'image_url': {
            'url': 'data:${att.mimeType ?? 'image/jpeg'};base64,$data',
          },
        });
      }
    } else {
      if (att.hasParsedText) {
        final parsed = att.parsedText ?? '';
        final header = '【文件：${att.name} 已解析内容】';
        parts.add({'type': 'text', 'text': '$header\n$parsed'});
        continue;
      }
      final data = att.dataBase64;
      if (data != null && data.isNotEmpty) {
        parts.add({
          'type': 'file',
          'file': {
            'file_name': att.name,
            'file_data':
                'data:${att.mimeType ?? 'application/octet-stream'};base64,$data',
          },
        });
      }
    }
  }
  return parts;
}

List<Map<String, dynamic>> _assembleSimple(
  List<ChatMessage> history, {
  int historyLimit = 20,
  int tokenBudget = 1000000,
  String currentUserText = '本轮问题',
}) {
  return ContextAssembler.assemble(
    history: history,
    historyLimit: historyLimit,
    tokenBudget: tokenBudget,
    currentUserText: currentUserText,
    buildContent: _buildContent,
  ).messages;
}

void main() {
  group('组装层（P1-01 / P2-02 / P2-03 / P2-04 / P3-04）', () {
    test('本轮用户消息已从 history 剔除时，user 段只出现一次（P1-01）', () {
      // 模拟 chat_page：messagesProvider 已把本轮 user 消息放进 state，
      // 组装前按 id 剔除，再作为 currentUserText 传入。
      final history = [
        _msg(1, 'user', '历史问题一'),
        _msg(2, 'assistant', '历史回答一'),
        _msg(3, 'user', '本轮问题'),
      ];
      const currentUserId = 3;
      final filtered =
          history.where((m) => m.id != currentUserId).toList();
      final messages = _assembleSimple(filtered);
      final userTexts = messages
          .where((m) => m['role'] == 'user')
          .map((m) => m['content'])
          .whereType<String>()
          .where((c) => c == '本轮问题')
          .toList();
      expect(userTexts.length, 1, reason: '本轮用户消息只能出现一次');
      // 历史轮次的首个 user 消息仍然保留。
      expect(
        messages.any((m) => m['role'] == 'user' && m['content'] == '历史问题一'),
        isTrue,
      );
    });

    test('未剔除本轮消息（旧缺陷复现路径）会重复注入 2 次', () {
      final history = [
        _msg(1, 'user', '本轮问题'),
      ];
      final messages = _assembleSimple(history);
      final count = messages
          .where((m) => m['role'] == 'user' && m['content'] == '本轮问题')
          .length;
      expect(count, 2, reason: '这正是 v1.2.24 的缺陷，用于固化「必须先剔除」的前提');
    });

    test('keepOriginal（appendCurrentUser=false）不额外追加 user 段', () {
      final history = [
        _msg(1, 'user', '原始问题'),
        _msg(2, 'assistant', '原始回答'),
      ];
      final assembly = ContextAssembler.assemble(
        history: history,
        historyLimit: 20,
        tokenBudget: 1000000,
        currentUserText: '原始问题',
        appendCurrentUser: false,
        userInstruction: '换一种说法',
        buildContent: _buildContent,
      );
      final userMessages =
          assembly.messages.where((m) => m['role'] == 'user').toList();
      expect(userMessages.length, 2, reason: '原始问题 + 变体指令');
      expect(userMessages.first['content'], '原始问题');
      expect(userMessages.last['content'], '换一种说法');
    });

    test('预算不足时跳过超长旧消息，最新消息必达（P2-04）', () {
      final history = <ChatMessage>[
        _msg(1, 'user', '旧' * 6000),
        _msg(2, 'assistant', '答' * 6000),
        _msg(3, 'user', '次新问题'),
        _msg(4, 'assistant', '次新回答'),
      ];
      // 预算只够容纳最近两条 + 本轮。
      final assembly = ContextAssembler.assemble(
        history: history,
        historyLimit: 20,
        tokenBudget: 200,
        currentUserText: '最新问题',
        buildContent: _buildContent,
      );
      final contents =
          assembly.messages.map((m) => m['content']).whereType<String>().toList();
      expect(contents.contains('次新回答'), isTrue, reason: '最新的历史消息不能被丢弃');
      expect(contents.contains('次新问题'), isTrue);
      expect(contents.contains('最新问题'), isTrue);
      expect(assembly.historyDropped, greaterThan(0));
    });

    test('历史只取尾部 20 条，且条数与组装结果一致（P2-03）', () {
      final history = List.generate(
        30,
        (i) => _msg(i + 1, i.isEven ? 'user' : 'assistant', '第 ${i + 1} 条'),
      );
      final assembly = ContextAssembler.assemble(
        history: history,
        historyLimit: 20,
        tokenBudget: 1000000,
        currentUserText: '本轮问题',
        buildContent: _buildContent,
      );
      expect(assembly.historyIncluded, 20);
      expect(assembly.messages.length, 21, reason: '20 条历史 + 本轮 user');
      expect(assembly.messages.first['content'], '第 11 条');
    });

    test('摘要游标之前的消息不进入请求', () {
      final history = List.generate(
        6,
        (i) => _msg(i + 1, i.isEven ? 'user' : 'assistant', '消息${i + 1}'),
      );
      final assembly = ContextAssembler.assemble(
        history: history,
        summaryUptoId: 4,
        historyLimit: 20,
        tokenBudget: 1000000,
        currentUserText: '本轮问题',
        contextSummary: '早前聊了需求',
        buildContent: _buildContent,
      );
      final contents =
          assembly.messages.map((m) => m['content']).whereType<String>().toList();
      expect(contents.contains('消息5'), isTrue);
      expect(contents.contains('消息4'), isFalse);
      expect(contents.contains('消息1'), isFalse);
      expect(
        assembly.messages.any(
            (m) => m['role'] == 'system' && (m['content'] as String).contains('早前聊了需求')),
        isTrue,
      );
    });

    test('system 段顺序固定：全局 → 系统 → 记忆 → 摘要（P2-02 / P3-04）', () {
      final assembly = ContextAssembler.assemble(
        globalPrompt: '全局提示',
        systemPrompt: '会话提示',
        memoryLines: const ['- 用户偏好中文'],
        contextSummary: '历史摘要',
        history: [_msg(1, 'user', '历史问题'), _msg(2, 'assistant', '历史回答')],
        historyLimit: 20,
        tokenBudget: 1000000,
        currentUserText: '本轮问题',
        buildContent: _buildContent,
      );
      final systems = assembly.messages
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'] as String)
          .toList();
      expect(systems.length, 4);
      expect(systems[0], '全局提示');
      expect(systems[1], '会话提示');
      expect(systems[2], contains('用户偏好中文'));
      expect(systems[3], contains('历史摘要'));
    });

    test('估算口径与组装结果一致，不存在漂移（P2-03）', () {
      final history = List.generate(
        8,
        (i) => _msg(i + 1, i.isEven ? 'user' : 'assistant', '内容' * (i + 1)),
      );
      final assembly = ContextAssembler.assemble(
        globalPrompt: '全局提示',
        systemPrompt: '会话提示',
        contextSummary: '摘要内容',
        history: history,
        historyLimit: 3,
        tokenBudget: 1000000,
        currentUserText: '本轮问题',
        buildContent: _buildContent,
      );
      var recomputed = ContextUsageEstimator.messagesOverhead;
      for (final m in assembly.messages) {
        recomputed +=
            ContextTokenEstimator.contentTokens(m['content']) +
                ContextUsageEstimator.perMessageOverhead;
      }
      expect(assembly.estimateTokens, recomputed);
      expect(assembly.messages.length, lessThanOrEqualTo(3 + 4 + 1));
    });
  });

  group('附件计入预算（P2-01）', () {
    test('解析文本计入历史消息 token', () {
      final parsed = 'x' * 8000;
      final withAttachment = _msg(
        1,
        'user',
        '看下这份文档',
        attachments: [
          MessageAttachment(
            type: 'file',
            name: 'long.txt',
            parsedText: parsed,
            parsedCharCount: parsed.length,
            parseStatus: 'done',
          ),
        ],
      );
      final plain = _msg(1, 'user', '看下这份文档');
      final withTokens = ContextTokenEstimator.messageTokens(
          withAttachment, _buildContent);
      final plainTokens =
          ContextTokenEstimator.messageTokens(plain, _buildContent);
      expect(withTokens - plainTokens, greaterThan(1500),
          reason: '8000 字符附件正文必须计入预算，而不是只算一句提问');
    });

    test('图片按固定 token 计入，base64 长度不影响估算', () {
      final attachment = MessageAttachment(
        type: 'image',
        name: 'a.png',
        dataBase64: 'A' * 100000,
        mimeType: 'image/png',
      );
      final tokens = ContextTokenEstimator.messageTokens(
        _msg(1, 'user', '看图', attachments: [attachment]),
        _buildContent,
      );
      expect(
        tokens,
        ContextTokenEstimator.contentTokens(
              _buildContent('看图', [attachment]),
            ) +
            ContextUsageEstimator.perMessageOverhead,
      );
      final imagePart = ContextTokenEstimator.contentTokens([
        {'type': 'image_url', 'image_url': {'url': 'x'}},
      ]);
      expect(imagePart, ContextTokenEstimator.imageTokens);
    });

    test('附件消息进入组装后估算同步放大', () {
      final parsed = 'y' * 4000;
      final history = [
        _msg(1, 'user', '长文档', attachments: [
          MessageAttachment(
            type: 'file',
            name: 'doc.txt',
            parsedText: parsed,
            parsedCharCount: parsed.length,
            parseStatus: 'done',
          ),
        ]),
        _msg(2, 'assistant', '收到'),
      ];
      final withAttachment = ContextAssembler.assemble(
        history: history,
        historyLimit: 20,
        tokenBudget: 1000000,
        currentUserText: '继续',
        buildContent: _buildContent,
      );
      final withoutAttachment = ContextAssembler.assemble(
        history: [_msg(1, 'user', '长文档'), _msg(2, 'assistant', '收到')],
        historyLimit: 20,
        tokenBudget: 1000000,
        currentUserText: '继续',
        buildContent: _buildContent,
      );
      expect(withAttachment.estimateTokens,
          greaterThan(withoutAttachment.estimateTokens + 900));
    });
  });

  group('压缩互斥与乐观锁（P2-05 / P2-06）', () {
    test('压缩进行中再次 tryStart 返回失败（自动与手动互斥）', () {
      final gate = CompressionGate();
      expect(gate.isBusy, isFalse);
      expect(gate.tryStart(), isTrue);
      expect(gate.isBusy, isTrue);
      expect(gate.tryStart(), isFalse, reason: '第二次抢闸必须失败，避免双倍计费');
      gate.finish();
      expect(gate.isBusy, isFalse);
      expect(gate.tryStart(), isTrue);
    });

    test('清除摘要后，进行中的压缩结果被判为过期（P2-06）', () {
      final gate = CompressionGate();
      gate.tryStart();
      final startedEpoch = gate.epoch;
      expect(gate.isStale(startedEpoch), isFalse);
      gate.invalidate();
      expect(gate.isStale(startedEpoch), isTrue,
          reason: '摘要已被清除，压缩结果不得写回（否则摘要复生）');
      gate.finish();
    });

    test('压缩结束（finish）不改变乐观锁版本', () {
      final gate = CompressionGate();
      gate.tryStart();
      final startedEpoch = gate.epoch;
      gate.finish();
      expect(gate.isStale(startedEpoch), isFalse);
    });
  });

  group('摘要生成（P3-02 / P3-03）', () {
    final config = ContextCompressionConfig(
      enabled: true,
      contextWindow: 64000,
      triggerPercent: 70,
      tailKeepTokens: 5,
      summaryMaxChars: 5,
    );

    ContextCompressor compressor(HttpClientAdapter adapter) {
      final dio = Dio()..httpClientAdapter = adapter;
      return ContextCompressor(client: LlmClient(dio: dio));
    }

    test('超长摘要按 runes 截断，不产生孤立代理项（P3-02）', () async {
      final adapter = _FakeSummaryAdapter(summary: '😀😀😀😀😀😀😀😀😀😀');
      final result = await compressor(adapter).compress(
        history: [
          _msg(1, 'user', '一' * 20),
          _msg(2, 'assistant', '二' * 20),
          _msg(3, 'user', '三' * 20),
        ],
        existingSummary: null,
        config: config,
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'test-model',
      );
      expect(result, isNotNull);
      final summary = result!.summary;
      expect(summary.endsWith('…'), isTrue);
      expect(summary.contains('\uFFFD'), isFalse, reason: '不能把 emoji 切成 U+FFFD');
      // 5 个完整 emoji + 省略号
      expect(summary.runes.length, 6);
    });

    test('摘要请求固定低温度，不沿用会话高温（P3-03）', () async {
      final adapter = _FakeSummaryAdapter();
      await compressor(adapter).compress(
        history: [
          _msg(1, 'user', '一' * 20),
          _msg(2, 'assistant', '二' * 20),
          _msg(3, 'user', '三' * 20),
        ],
        existingSummary: null,
        config: config,
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-test',
        model: 'test-model',
      );
      expect(adapter.lastBody?['temperature'],
          AppConstants.contextSummaryTemperature);
      expect(AppConstants.contextSummaryTemperature, lessThanOrEqualTo(0.3));
    });
  });

  group('请求预算与窗口口径（P2-08 / P3-07）', () {
    test('requestTokenBudget 取窗口的 90%', () {
      final config = ContextCompressionConfig(
        enabled: true,
        contextWindow: 64000,
        triggerPercent: 70,
        tailKeepTokens: 8000,
        summaryMaxChars: 400,
      );
      expect(config.requestTokenBudget, 57600);
    });

    test('尾部预算不小于窗口阈值时，splitForTail 无待压缩消息（P3-07 提示依据）', () {
      final config = ContextCompressionConfig(
        enabled: true,
        contextWindow: 100,
        triggerPercent: 70,
        tailKeepTokens: 200,
        summaryMaxChars: 400,
      );
      final split = ContextCompressor().splitForTail(
        List.generate(6, (i) => _msg(i + 1, i.isEven ? 'user' : 'assistant', '内容')),
        config.tailKeepTokens,
      );
      expect(split.older, isEmpty);
      expect(split.tail, isNotEmpty);
    });
  });

  group('备份往返（P2-07）', () {
    BackupConversation conversation({
      String? summary,
      int? uptoId,
      int? summaryUpdatedAt,
    }) =>
        BackupConversation(
          refId: 7,
          title: '长会话',
          lastMessage: '最后一条',
          updatedAt: 200,
          createdAt: 100,
          contextSummary: summary,
          contextSummaryUptoId: uptoId,
          contextSummaryUpdatedAt: summaryUpdatedAt,
          messages: [
            BackupMessage(
              refId: 101,
              role: 'user',
              content: '第一问',
              createdAt: 101,
            ),
            BackupMessage(
              refId: 102,
              role: 'assistant',
              content: '第一答',
              createdAt: 102,
            ),
            BackupMessage(
              refId: 103,
              role: 'user',
              content: '第二问',
              createdAt: 103,
            ),
          ],
        );

    test('导出包含摘要三列，导入后完整还原', () {
      final exported = conversation(
        summary: '用户在做 talkroom 修复',
        uptoId: 102,
        summaryUpdatedAt: 300,
      ).toJson();
      expect(exported['context_summary'], '用户在做 talkroom 修复');
      expect(exported['context_summary_upto_id'], 102);
      expect(exported['context_summary_updated_at'], 300);

      final restored = BackupConversation.fromJson(exported);
      expect(restored.contextSummary, '用户在做 talkroom 修复');
      expect(restored.contextSummaryUptoId, 102);
      expect(restored.contextSummaryUpdatedAt, 300);
      expect(restored.messages.length, 3);
    });

    test('消息 ref_id 往返保留，供导入时重映射摘要游标', () {
      final exported = conversation(summary: '摘要', uptoId: 102).toJson();
      final messages = (exported['messages'] as List).cast<Map<String, dynamic>>();
      expect(messages.map((m) => m['ref_id']).toList(), [101, 102, 103]);
      final restored = BackupConversation.fromJson(exported);
      final refIds = restored.messages.map((m) => m.refId).toList();
      expect(refIds, [101, 102, 103]);
      // 游标 102 对应的消息可在导入后定位到最后一条 refId <= 102 的消息。
      final mapped = restored.messages
          .where((m) => (m.refId ?? 0) <= restored.contextSummaryUptoId!)
          .toList();
      expect(mapped.length, 2);
    });

    test('旧备份缺摘要字段时按未压缩处理（向后兼容）', () {
      final legacy = {
        'ref_id': 7,
        'title': '旧会话',
        'last_message': 'x',
        'updated_at': 200,
        'created_at': 100,
        'messages': <Map<String, dynamic>>[],
      };
      final restored = BackupConversation.fromJson(legacy);
      expect(restored.contextSummary, isNull);
      expect(restored.contextSummaryUptoId, isNull);
      expect(restored.contextSummaryUpdatedAt, isNull);
    });

    test('摘要为空串同样归一为 null（不写入空摘要）', () {
      final restored = BackupConversation.fromJson({
        'ref_id': 7,
        'title': '会话',
        'updated_at': 200,
        'created_at': 100,
        'context_summary': '   ',
        'context_summary_upto_id': 3,
        'messages': <Map<String, dynamic>>[],
      });
      expect(restored.contextSummary, isNull);
    });
  });
}
