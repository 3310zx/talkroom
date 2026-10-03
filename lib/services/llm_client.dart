import 'dart:convert';

import 'package:dio/dio.dart';

/// LLM 错误分类（对应 PRD 第 9 章「API 调用失败处理规范」）。
enum LlmErrorType {
  /// 用户主动停止生成（CancelToken）
  cancelled,

  /// 网络/超时/连接类错误
  network,

  /// API Key 无效、无权限
  auth,

  /// 模型不存在 / 接口路径错误
  model,

  /// 请求过于频繁
  rateLimit,

  /// 服务端返回错误（5xx / 其他非 2xx）
  server,

  /// 响应数据格式异常
  parse,
}

/// LLM 调用异常：携带中文可读提示，可直接展示给用户。
class LlmException implements Exception {
  const LlmException(this.type, this.message);

  final LlmErrorType type;
  final String message;

  bool get isCancelled => type == LlmErrorType.cancelled;

  @override
  String toString() => message;
}

/// 一次完整流式对话的最终结果。
class LlmStreamResult {
  const LlmStreamResult({
    required this.content,
    this.promptTokens,
    this.completionTokens,
  });

  final String content;
  final int? promptTokens;
  final int? completionTokens;
}

/// LLM 客户端（OpenAI 兼容 `/chat/completions`，SSE 流式）。
class LlmClient {
  LlmClient({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 发起流式对话请求。
  ///
  /// [baseUrl] 形如 `https://api.openai.com/v1`；[messages] 为 OpenAI 格式
  /// `{'role': 'system'|'user'|'assistant', 'content': '...'}` 列表。
  /// 每个增量内容通过 [onDelta] 回调实时返回；传入 [cancelToken] 可中断生成
  /// （中断后将抛出 `LlmException(type: cancelled)`）。
  /// [temperature] / [maxTokens] / [topP] 为可选参数透传。
  Future<LlmStreamResult> chatStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    required void Function(String delta) onDelta,
    CancelToken? cancelToken,
    double? temperature,
    int? maxTokens,
    double? topP,
  }) async {
    final buffer = StringBuffer();
    int? promptTokens;
    int? completionTokens;

    final Response<ResponseBody> response;
    try {
      response = await _dio.post<ResponseBody>(
        _joinUrl(baseUrl, '/chat/completions'),
        data: {
          'model': model,
          'messages': messages,
          'stream': true,
          if (temperature != null) 'temperature': temperature,
          if (maxTokens != null) 'max_tokens': maxTokens,
          if (topP != null) 'top_p': topP,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'text/event-stream',
          },
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _classifyError(e);
    }

    if (response.data == null) {
      throw const LlmException(LlmErrorType.parse, '响应为空，请稍后重试');
    }

    try {
      final byteStream = response.data!.stream;
      var done = false;
      // 记录是否收到过 data: 行 / 是否收到过有效内容增量，用于区分
      // "模型未返回内容"与"响应根本不是 SSE（网关错误页/错误 JSON）"。
      var receivedDataLine = false;
      var receivedContent = false;

      void handleLine(String line) {
        if (done) return;
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) return;
        receivedDataLine = true;
        final payload = trimmed.substring(5).trim();
        if (payload.isEmpty) return;
        if (payload == '[DONE]') {
          done = true;
          return;
        }

        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) return;
        final choices = decoded['choices'];
        if (choices is! List || choices.isEmpty) return;
        final first = choices.first;
        if (first is! Map<String, dynamic>) return;
        final delta = first['delta'];
        if (delta is Map<String, dynamic>) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            buffer.write(content);
            onDelta(content);
            receivedContent = true;
          } else {
            // 推理模型（如 DeepSeek-R1 系）流式响应中正文阶段前 delta.content
            // 可能为空，思考过程放在 delta.reasoning_content；将其作为回复内容
            // 累加展示，避免界面误判为"无回复"。
            final reasoning = delta['reasoning_content'];
            if (reasoning is String && reasoning.isNotEmpty) {
              buffer.write(reasoning);
              onDelta(reasoning);
              receivedContent = true;
            }
          }
        }
        final usage = decoded['usage'];
        if (usage is Map<String, dynamic>) {
          promptTokens ??= usage['prompt_tokens'] as int?;
          completionTokens ??= usage['completion_tokens'] as int?;
        }
      }

      // 关键实现：utf8.decoder.bind 正确处理跨 chunk 的多字节字符边界，
      // LineSplitter 按行切分 SSE 事件（data: 一行、空行分隔、[DONE] 终止）。
      // 注意不能使用 startChunkedConversion + 边收边 toString：该解码器要等
      // close() 才 flush，导致流式期间拿不到任何增量，全部回复被静默吞掉。
      await for (final line
          in utf8.decoder.bind(byteStream).transform(const LineSplitter())) {
        handleLine(line);
        if (done) break;
      }

      // 关键兜底：流正常结束但未收到任何有效内容时，显式抛错而非静默返回
      // 空内容。此前该场景会被上层当作"成功回复了空消息"处理，界面表现为
      // 无回复且无任何错误提示。
      if (!receivedContent) {
        if (!receivedDataLine) {
          throw const LlmException(
            LlmErrorType.parse,
            '响应格式异常：未收到流式数据（可能为网关错误或 base_url 不正确），请检查接口地址',
          );
        }
        throw const LlmException(
          LlmErrorType.parse,
          '模型未返回任何内容，请确认模型 ID 在当前服务商可用（可到服务商管理页点击「检查」验证）',
        );
      }
    } on FormatException {
      throw const LlmException(LlmErrorType.parse, '响应数据格式异常，请稍后重试');
    } on DioException catch (e) {
      throw _classifyError(e);
    }

    return LlmStreamResult(
      content: buffer.toString(),
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  /// 发起非流式对话请求（PRD 5.5.2：主动消息走非流式，超时 60s）。
  ///
  /// 供主动消息调度器使用：一次请求返回完整回复，不回调增量。
  Future<LlmStreamResult> chat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double? temperature,
    int? maxTokens,
    double? topP,
  }) async {
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        _joinUrl(baseUrl, '/chat/completions'),
        data: {
          'model': model,
          'messages': messages,
          'stream': false,
          if (temperature != null) 'temperature': temperature,
          if (maxTokens != null) 'max_tokens': maxTokens,
          if (topP != null) 'top_p': topP,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          receiveTimeout: const Duration(seconds: 60),
          sendTimeout: const Duration(seconds: 60),
        ),
      );
    } on DioException catch (e) {
      throw _classifyError(e);
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const LlmException(LlmErrorType.parse, '响应数据格式异常，请稍后重试');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmException(LlmErrorType.parse, '响应为空，请稍后重试');
    }
    final first = choices.first;
    final message = (first is Map<String, dynamic>) ? first['message'] : null;
    final content = (message is Map<String, dynamic>) ? message['content'] : null;
    final usage = data['usage'];
    return LlmStreamResult(
      content: content is String ? content : '',
      promptTokens: (usage is Map<String, dynamic>)
          ? usage['prompt_tokens'] as int?
          : null,
      completionTokens: (usage is Map<String, dynamic>)
          ? usage['completion_tokens'] as int?
          : null,
    );
  }

  /// 将 Dio 异常映射为中文可读的 [LlmException]（PRD 9.2）。
  LlmException _classifyError(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const LlmException(LlmErrorType.cancelled, '已停止生成');
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const LlmException(LlmErrorType.network, '网络连接失败，请检查网络后重试');
      case DioExceptionType.badCertificate:
        return const LlmException(LlmErrorType.network, '证书校验失败，请检查网络或代理设置');
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        switch (code) {
          case 400:
            return const LlmException(LlmErrorType.parse, '请求参数错误（400），请检查模型与参数设置');
          case 401:
          case 403:
            return LlmException(LlmErrorType.auth, 'API Key 无效或无权限（$code），请在设置中检查 API 配置');
          case 404:
            return const LlmException(LlmErrorType.model, '模型不存在或接口路径错误（404），请检查 base_url 与模型名');
          case 429:
            return const LlmException(LlmErrorType.rateLimit, '请求过于频繁（429），请稍后重试');
          default:
            return LlmException(LlmErrorType.server, '服务返回错误（$code），请稍后重试');
        }
      case DioExceptionType.unknown:
      case DioExceptionType.transformTimeout:
        return const LlmException(LlmErrorType.network, '网络请求失败，请检查网络后重试');
    }
  }

  /// 拼接 OpenAI 兼容接口 URL：规范化 baseUrl 尾部斜杠，避免产生
  /// `https://host/v1//chat/completions` 这类双斜杠路径导致网关 404。
  String _joinUrl(String baseUrl, String path) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base$path';
  }
}
