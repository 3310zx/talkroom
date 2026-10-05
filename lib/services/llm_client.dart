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
    this.reasoningContent,
    this.reasoningDurationMs,
    this.reasoningTokens,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
  });

  /// 正文（不含思维链）
  final String content;

  /// 思维链文本（与正文分离，供界面折叠展示）
  final String? reasoningContent;

  /// 思考耗时（毫秒）：从请求发出到收到首个正文 token。
  final int? reasoningDurationMs;

  /// 思考消耗 token（usage 缺失时按字符数估算）
  final int? reasoningTokens;

  final int? promptTokens;
  final int? completionTokens;

  /// 缓存命中 token（usage.prompt_tokens_details.cached_tokens）
  final int? cachedTokens;
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
    required List<Map<String, dynamic>> messages,
    required void Function(String delta) onDelta,
    /// 思维链增量回调（可选）：reasoning_content 每到达一段即回调，
    /// 供界面实时累积到思维链折叠卡片（与正文分离展示）。
    void Function(String delta)? onReasoningDelta,
    CancelToken? cancelToken,
    double? temperature,
    int? maxTokens,
    double? topP,
  }) async {
    final contentBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    int? promptTokens;
    int? completionTokens;
    int? cachedTokens;
    // 思考耗时：请求发出时刻（post 前）→ 首个正文 token 到达时刻；
    // 若流结束仍未收到正文（纯推理被停止等），用流结束时刻兜底。
    final requestStartedAt = DateTime.now();
    DateTime? firstContentAt;
    DateTime? streamEndAt;

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
          // 正文增量：进入 contentBuffer 并通过 onDelta 实时回调界面。
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            firstContentAt ??= DateTime.now();
            contentBuffer.write(content);
            onDelta(content);
            receivedContent = true;
          }
          // 思维链增量：进入独立 reasoningBuffer（与正文分离展示），
          // 不回调用户正文 onDelta；若提供了 onReasoningDelta 则实时回调，
          // 让界面在生成过程中即可看到思维链折叠卡片。
          final reasoning = delta['reasoning_content'];
          if (reasoning is String && reasoning.isNotEmpty) {
            reasoningBuffer.write(reasoning);
            onReasoningDelta?.call(reasoning);
            receivedContent = true;
          }
        }
        final usage = decoded['usage'];
        if (usage is Map<String, dynamic>) {
          promptTokens ??= usage['prompt_tokens'] as int?;
          completionTokens ??= usage['completion_tokens'] as int?;
          final details = usage['prompt_tokens_details'];
          if (details is Map<String, dynamic>) {
            cachedTokens ??= details['cached_tokens'] as int?;
          }
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
      streamEndAt = DateTime.now();

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

    final content = contentBuffer.toString();
    final reasoning = reasoningBuffer.toString();
    // 流正常结束必有 streamEndAt（异常路径已提前 throw），此处仅兜底 firstContentAt。
    final reasoningEnd = firstContentAt ?? streamEndAt;
    final reasoningDurationMs =
        reasoningEnd.difference(requestStartedAt).inMilliseconds;
    // usage 缺失时按字符数估算（约 4 字符/token，与多数中文 tokenizer 接近）；
    // prompt_tokens 因缺少输入文本信息无法估算，保持 null。
    final estimatedCompletion =
        content.isNotEmpty ? (content.length / 4).ceil() : null;
    final estimatedReasoning =
        reasoning.isNotEmpty ? (reasoning.length / 4).ceil() : null;

    return LlmStreamResult(
      content: content,
      reasoningContent: reasoning.isEmpty ? null : reasoning,
      reasoningDurationMs: reasoning.isEmpty ? null : reasoningDurationMs,
      reasoningTokens: reasoning.isEmpty ? null : estimatedReasoning,
      promptTokens: promptTokens,
      completionTokens: completionTokens ?? estimatedCompletion,
      cachedTokens: cachedTokens,
    );
  }

  /// 发起非流式对话请求（PRD 5.5.2：主动消息走非流式，超时 60s）。
  ///
  /// 供主动消息调度器使用：一次请求返回完整回复，不回调增量。
  Future<LlmStreamResult> chat({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, dynamic>> messages,
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
    final reasoning =
        (message is Map<String, dynamic>) ? message['reasoning_content'] : null;
    final usage = data['usage'];
    final promptTokens = (usage is Map<String, dynamic>)
        ? usage['prompt_tokens'] as int?
        : null;
    final completionTokens = (usage is Map<String, dynamic>)
        ? usage['completion_tokens'] as int?
        : null;
    int? cachedTokens;
    if (usage is Map<String, dynamic>) {
      final details = usage['prompt_tokens_details'];
      if (details is Map<String, dynamic>) {
        cachedTokens = details['cached_tokens'] as int?;
      }
    }
    final text = content is String ? content : '';
    final reasoningText = reasoning is String ? reasoning : '';
    // usage 缺失时按字符数估算；prompt_tokens 无输入文本信息无法估算。
    return LlmStreamResult(
      content: text,
      reasoningContent: reasoningText.isEmpty ? null : reasoningText,
      reasoningDurationMs: null,
      reasoningTokens:
          reasoningText.isEmpty ? null : (reasoningText.length / 4).ceil(),
      promptTokens: promptTokens,
      completionTokens: completionTokens ?? (text.isEmpty ? null : (text.length / 4).ceil()),
      cachedTokens: cachedTokens,
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
            return LlmException(
              LlmErrorType.parse,
              _friendlyBadRequest(e.response?.data),
            );
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

  /// 400 错误的友好中文提示（PRD 2.4 / R9）：
  /// 优先识别「不支持图片 / 多模态 / 文件」类错误，给出可操作的中文提示；
  /// 其他 400 保持通用提示。
  String _friendlyBadRequest(Object? data) {
    var raw = '';
    if (data is String) {
      raw = data;
    } else if (data is Map<String, dynamic>) {
      final err = data['error'];
      if (err is String) {
        raw = err;
      } else if (err is Map<String, dynamic>) {
        raw = err['message']?.toString() ?? '';
      }
      if (raw.isEmpty) raw = data['message']?.toString() ?? '';
    }
    final lower = raw.toLowerCase();
    final mentionsImage = lower.contains('image') ||
        lower.contains('picture') ||
        lower.contains('figure') ||
        lower.contains('multimodal') ||
        lower.contains('vision') ||
        lower.contains('视觉') ||
        lower.contains('图片') ||
        lower.contains('图像');
    final mentionsFile = lower.contains('file') ||
        lower.contains('attachment') ||
        lower.contains('文件') ||
        lower.contains('附件');
    if (mentionsImage) {
      return '当前模型不支持图片输入，请更换支持多模态的模型后重试，或移除图片后直接发送文字';
    }
    if (mentionsFile) {
      return '当前模型不支持文件输入，请更换支持文件/多模态的模型后重试，或移除文件后直接发送文字';
    }
    return '请求参数错误（400），请检查模型与参数设置';
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
