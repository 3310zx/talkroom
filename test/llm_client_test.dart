import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/services/llm_client.dart';

/// 可控的 SSE 响应假适配器：记录实际请求 URL，按给定 body 流式返回。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final String body;
  String? lastUrl;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUrl = options.uri.toString();
    return ResponseBody.fromString(
      body,
      200,
      headers: {'content-type': ['text/event-stream']},
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<String> _runStream(
  String body,
  String baseUrl, {
  List<String>? deltas,
}) async {
  final dio = Dio()..httpClientAdapter = _FakeAdapter(body);
  final client = LlmClient(dio: dio);
  final result = await client.chatStream(
    baseUrl: baseUrl,
    apiKey: 'sk-test',
    model: 'deepseek-ai/DeepSeek-V4-Flash',
    messages: const [{'role': 'user', 'content': '你好'}],
    onDelta: (delta) => deltas?.add(delta),
  );
  return result.content;
}

void main() {
  group('LlmClient.chatStream SSE 解析与空回复兜底', () {
    test('正常流式：多 data 行 + [DONE] 增量拼接', () async {
      final content = await _runStream(
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
        'data: [DONE]\n\n',
        'https://api.siliconflow.cn/v1',
      );
      expect(content, '你好');
    });

    test('推理模型：delta.reasoning_content 被累加展示而非静默丢弃', () async {
      final content = await _runStream(
        'data: {"choices":[{"delta":{"reasoning_content":"思考中"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"结论"}}]}\n\n'
        'data: [DONE]\n\n',
        'https://api.siliconflow.cn/v1',
      );
      expect(content, '思考中结论');
    });

    test('流正常结束但零内容：抛 parse 异常（界面将显示错误而非静默空回复）', () async {
      expect(
        () => _runStream('data: [DONE]\n\n', 'https://api.siliconflow.cn/v1'),
        throwsA(isA<LlmException>().having(
          (e) => e.type,
          'type',
          LlmErrorType.parse,
        )),
      );
    });

    test('响应不是 SSE（网关错误 JSON 无 data: 行）：抛"响应格式异常"', () async {
      expect(
        () => _runStream(
          '{"error":{"message":"model not exist"}}',
          'https://api.siliconflow.cn/v1',
        ),
        throwsA(isA<LlmException>().having(
          (e) => e.message,
          'message',
          contains('响应格式异常'),
        )),
      );
    });

    test('baseUrl 带尾部斜杠：请求 URL 不产生双斜杠', () async {
      final dio = Dio()..httpClientAdapter = _FakeAdapter(
        'data: {"choices":[{"delta":{"content":"hi"}}]}\n\n'
        'data: [DONE]\n\n',
      );
      final client = LlmClient(dio: dio);
      await client.chatStream(
        baseUrl: 'https://api.siliconflow.cn/v1/',
        apiKey: 'sk-test',
        model: 'deepseek-ai/DeepSeek-V4-Flash',
        messages: const [{'role': 'user', 'content': '你好'}],
        onDelta: (_) {},
      );
      final adapter = dio.httpClientAdapter as _FakeAdapter;
      expect(adapter.lastUrl, 'https://api.siliconflow.cn/v1/chat/completions');
    });
  });
}
