import '../core/constants.dart';
import '../domain/models/message.dart';
import 'llm_client.dart';

/// 上下文用量估算器。
///
/// 参考 deepx-code 的压缩触发方式：发送前按估算 token 与上下文窗口比较。
/// 由于各接口的 tokenizer 不可得，此处采用保守的字符加权估算：
/// - 中文（含 CJK 标点 / 假名 / 谚文）：1 字符 ≈ 1 token；
/// - 其余（英文 / 数字 / ASCII 符号）：4 字符 ≈ 1 token，向上取整。
///
/// 该估算对中文偏保守（宁可早触发压缩，也不让请求超窗）。
abstract final class ContextUsageEstimator {
  /// 单条消息的固定结构开销（role / 分隔符等），对齐 OpenAI 的粗略经验值。
  static const int perMessageOverhead = 4;

  /// 整个消息数组的固定开销。
  static const int messagesOverhead = 3;

  /// 估算一段文本的 token 数（中英混合加权）。
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;
    var cjk = 0;
    var other = 0;
    for (final rune in text.runes) {
      if (_isCjk(rune)) {
        cjk++;
      } else {
        other++;
      }
    }
    // 英文 4 字符 1 token（向上取整），中文 1 字符 1 token。
    return cjk + ((other + 3) ~/ 4);
  }

  /// 估算单条消息的 token 数（正文 + 结构开销）。
  static int estimateMessageTokens(Map<String, dynamic> message) {
    final content = message['content'];
    final text = content is String ? content : '';
    return estimateTokens(text) + perMessageOverhead;
  }

  /// 估算整组请求消息的 token 数。
  static int estimateMessagesTokens(List<Map<String, dynamic>> messages) {
    var total = messagesOverhead;
    for (final message in messages) {
      total += estimateMessageTokens(message);
    }
    return total;
  }

  /// CJK 及全角字符判定（中文 1 字符按 1 token 计）。
  static bool _isCjk(int rune) {
    return (rune >= 0x3000 && rune <= 0x303F) || // CJK 标点
        (rune >= 0x3040 && rune <= 0x30FF) || // 日文假名
        (rune >= 0x3400 && rune <= 0x4DBF) || // CJK 扩展 A
        (rune >= 0x4E00 && rune <= 0x9FFF) || // CJK 基本区
        (rune >= 0xAC00 && rune <= 0xD7AF) || // 谚文
        (rune >= 0xF900 && rune <= 0xFAFF) || // CJK 兼容
        (rune >= 0xFF00 && rune <= 0xFFEF); // 全角字符
  }
}

/// 上下文压缩配置（来源：设置页「上下文压缩」分类，全部可配置）。
class ContextCompressionConfig {
  const ContextCompressionConfig({
    this.enabled = true,
    this.contextWindow = AppConstants.defaultContextWindowTokens,
    this.triggerPercent = AppConstants.defaultContextTriggerPercent,
    this.tailKeepTokens = AppConstants.defaultContextTailKeepTokens,
    this.summaryMaxChars = AppConstants.defaultContextSummaryMaxChars,
  });

  /// 是否启用自动压缩。
  final bool enabled;

  /// 模型上下文窗口（token）。
  final int contextWindow;

  /// 触发阈值百分比（1 ~ 100）。
  final int triggerPercent;

  /// 尾部保留的最近消息 token 预算。
  final int tailKeepTokens;

  /// 摘要最大字数。
  final int summaryMaxChars;

  /// 触发压缩的 token 阈值。
  int get triggerTokens {
    final value = contextWindow * triggerPercent / 100;
    return value.round();
  }

  /// 估算用量是否已达到触发阈值。
  bool shouldCompress(int estimatedTokens) =>
      enabled && estimatedTokens >= triggerTokens;

  /// 从 settings 表读取配置（缺失或非法值回落到默认值）。
  factory ContextCompressionConfig.fromSettings(Map<String, String?> settings) {
    final enabledRaw = settings[AppConstants.settingContextCompressionEnabled];
    // 默认开启：仅在显式写入 '0' 时关闭。
    final enabled = enabledRaw != '0';

    int readInt(String key, int fallback, {int min = 1, int? max}) {
      final parsed = int.tryParse((settings[key] ?? '').trim());
      if (parsed == null || parsed < min) return fallback;
      if (max != null && parsed > max) return max;
      return parsed;
    }

    return ContextCompressionConfig(
      enabled: enabled,
      contextWindow: readInt(AppConstants.settingContextWindowTokens,
          AppConstants.defaultContextWindowTokens),
      triggerPercent: readInt(
          AppConstants.settingContextTriggerPercent,
          AppConstants.defaultContextTriggerPercent,
          max: 100),
      tailKeepTokens: readInt(AppConstants.settingContextTailKeepTokens,
          AppConstants.defaultContextTailKeepTokens),
      summaryMaxChars: readInt(AppConstants.settingContextSummaryMaxChars,
          AppConstants.defaultContextSummaryMaxChars),
    );
  }
}

/// 自动压缩失败熔断器（v1.2.24）。
///
/// 纯内存状态，不落库：自动压缩连续失败 [maxConsecutiveFailures] 次后熔断，
/// 本会话不再尝试自动压缩，避免每次发送都额外打一次失败的 LLM 请求；
/// 手动压缩成功或切换会话时复位。
class AutoCompressionCircuitBreaker {
  AutoCompressionCircuitBreaker({this.maxConsecutiveFailures = 3})
      : assert(maxConsecutiveFailures > 0);

  /// 触发熔断所需的连续失败次数。
  final int maxConsecutiveFailures;

  int _consecutiveFailures = 0;
  int? _conversationId;

  /// 当前连续失败次数（仅自动压缩失败累加）。
  int get consecutiveFailures => _consecutiveFailures;

  /// 是否已熔断（本会话暂停自动压缩）。
  bool get isOpen => _consecutiveFailures >= maxConsecutiveFailures;

  /// 是否仍在尝试自动压缩。
  bool get allowsAutoCompression => !isOpen;

  /// 绑定当前会话：会话切换时清零失败计数。
  void bindConversation(int? conversationId) {
    if (_conversationId == conversationId) return;
    _conversationId = conversationId;
    _consecutiveFailures = 0;
  }

  /// 记录一次自动压缩失败，返回本次是否「刚刚触发熔断」（用于只提示一次）。
  bool recordFailure() {
    final wasOpen = isOpen;
    _consecutiveFailures++;
    return !wasOpen && isOpen;
  }

  /// 记录一次压缩成功（自动或手动），清零失败计数。
  void recordSuccess() {
    _consecutiveFailures = 0;
  }

  /// 熔断提示文案（深浅色、桌面/移动端共用）。
  String get pauseHint =>
      '自动压缩已连续失败 $maxConsecutiveFailures 次，已暂停自动压缩，可手动重试';
}

/// 分层结果：待压缩的更早消息 + 原样保留的尾部最近消息。
class ContextCompressionSplit {
  const ContextCompressionSplit({required this.older, required this.tail});

  final List<ChatMessage> older;
  final List<ChatMessage> tail;

  /// 待压缩部分估算 token。
  int get olderTokens => older.fold(
      0, (sum, m) => sum + ContextUsageEstimator.estimateTokens(m.content) +
          ContextUsageEstimator.perMessageOverhead);

  /// 尾部保留部分估算 token。
  int get tailTokens => tail.fold(
      0, (sum, m) => sum + ContextUsageEstimator.estimateTokens(m.content) +
          ContextUsageEstimator.perMessageOverhead);
}

/// 一次压缩的结果（用于持久化与提示）。
class ContextCompressionResult {
  const ContextCompressionResult({
    required this.summary,
    required this.uptoMessageId,
    required this.compressedCount,
    required this.beforeTokens,
    required this.afterTokens,
  });

  /// 合并后的新摘要。
  final String summary;

  /// 本次已压缩到的消息 id（id <= 该值的消息不再参与请求组装）。
  final int uptoMessageId;

  /// 本次被压成摘要的消息条数。
  final int compressedCount;

  /// 压缩前上下文估算 token（摘要段 + 被压缩消息）。
  final int beforeTokens;

  /// 压缩后上下文估算 token（摘要段）。
  final int afterTokens;

  /// 节省的估算 token（可能为负，表示摘要比原文还长）。
  int get savedTokens => beforeTokens - afterTokens;
}

/// 上下文压缩器：分层保留尾部 + LLM 摘要合并（参考 deepx-code）。
///
/// 压缩不删除任何原始消息，只产出摘要与「已压缩到的消息 id」，
/// 由调用方写入 conversations 表并用于请求组装。
class ContextCompressor {
  ContextCompressor({LlmClient? client}) : _client = client ?? LlmClient();

  final LlmClient _client;

  /// 分层：从最新消息往回累加，直到达到 [tailKeepTokens] 预算为止，
  /// 该预算内的最近消息原样保留，更早的消息进入待压缩区。
  ///
  /// 至少保留一条消息（避免把最后一条也压掉导致上下文空洞）。
  ContextCompressionSplit splitForTail(
      List<ChatMessage> history, int tailKeepTokens) {
    if (history.isEmpty) {
      return const ContextCompressionSplit(older: [], tail: []);
    }
    final tail = <ChatMessage>[];
    var used = 0;
    for (var i = history.length - 1; i >= 0; i--) {
      final message = history[i];
      final cost = ContextUsageEstimator.estimateMessageTokens({
            'content': message.content,
          });
      // 预算已用完则停止（首条无条件纳入，保证尾部至少一条）。
      if (tail.isNotEmpty && used + cost > tailKeepTokens) break;
      used += cost;
      tail.insert(0, message);
    }
    final olderCount = history.length - tail.length;
    return ContextCompressionSplit(
      older: olderCount > 0 ? history.sublist(0, olderCount) : const [],
      tail: tail,
    );
  }

  /// 构造「已有摘要 + 新增内容」的合并提示词（不丢已有信息）。
  String buildMergePrompt({
    required String? existingSummary,
    required String newContent,
    required int summaryMaxChars,
  }) {
    final hasExisting =
        existingSummary != null && existingSummary.trim().isNotEmpty;
    final buffer = StringBuffer()
      ..writeln('你是一个对话上下文压缩器。请把下面的内容压缩成一段连贯、信息完整的中文摘要。')
      ..writeln('要求：')
      ..writeln('1. 保留关键事实、已做出的决定、未完成的待办事项、用户的偏好与约束；')
      ..writeln('2. 不丢失已有摘要中的有效信息，与新增内容去重合并，不臆造任何内容；')
      ..writeln('3. 使用第三人称客观叙述，舍弃寒暄与重复表述；')
      ..writeln('4. 只输出摘要正文，不要标题、不要解释、不要 Markdown 标记；')
      ..writeln('5. 保留用户的关键指令与偏好原话，以简短引用形式写入摘要'
          '（例如「用户要求：只改中文文案」），非全文照抄；')
      ..writeln('6. 摘要不超过 $summaryMaxChars 字。')
      ..writeln()
      ..writeln('【已有摘要】')
      ..writeln(hasExisting ? existingSummary.trim() : '（暂无，本次为首次压缩）')
      ..writeln()
      ..writeln('【新增待压缩对话】')
      ..writeln(newContent);
    return buffer.toString().trim();
  }

  /// 把消息列表渲染成给 LLM 阅读的纯文本（角色 + 正文）。
  String renderMessages(List<ChatMessage> messages) {
    final buffer = StringBuffer();
    for (final message in messages) {
      final content = message.content.trim();
      if (content.isEmpty) continue;
      final role = message.role == 'user' ? '用户' : '助手';
      final attachmentNote = message.attachments.isEmpty
          ? ''
          : '（含 ${message.attachments.length} 个附件）';
      buffer.writeln('$role$attachmentNote：$content');
    }
    return buffer.toString().trim();
  }

  /// 执行一次压缩：分层 → 合并摘要（非流式 LLM 调用）。
  ///
  /// [history] 必须是「尚未被摘要覆盖」的有效消息（调用方按
  /// contextSummaryUptoId 过滤后传入），[existingSummary] 为会话已有摘要。
  /// 无需压缩（无待压缩消息 / 摘要为空）时返回 null。
  /// LLM 调用失败会抛出 [LlmException]，由调用方静默降级。
  Future<ContextCompressionResult?> compress({
    required List<ChatMessage> history,
    required String? existingSummary,
    required ContextCompressionConfig config,
    required String baseUrl,
    required String apiKey,
    required String model,
    double? temperature,
    double? topP,
  }) async {
    final candidates = history
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .where((m) => m.content.trim().isNotEmpty)
        .toList();
    if (candidates.isEmpty) return null;
    final split = splitForTail(candidates, config.tailKeepTokens);
    if (split.older.isEmpty) return null;

    final rendered = renderMessages(split.older);
    if (rendered.isEmpty) return null;

    final prompt = buildMergePrompt(
      existingSummary: existingSummary,
      newContent: rendered,
      summaryMaxChars: config.summaryMaxChars,
    );
    // 摘要长度按字数（非 token）约束，给足余量避免被 max_tokens 截断。
    final maxTokens = (config.summaryMaxChars * 2 + 256).clamp(256, 8192);

    final result = await _client.chat(
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      messages: [
        {'role': 'system', 'content': '你是严谨的对话摘要压缩器，只输出中文摘要正文。'},
        {'role': 'user', 'content': prompt},
      ],
      temperature: temperature,
      maxTokens: maxTokens,
      topP: topP,
    );
    final summary = result.content.trim();
    if (summary.isEmpty) {
      throw const LlmException(LlmErrorType.parse, '摘要结果为空');
    }
    final capped = summary.length > config.summaryMaxChars
        ? '${summary.substring(0, config.summaryMaxChars)}…'
        : summary;

    final uptoId = split.older.last.id;
    if (uptoId == null) return null;

    final beforeTokens = split.olderTokens +
        (existingSummary == null
            ? 0
            : ContextUsageEstimator.estimateTokens(existingSummary));
    return ContextCompressionResult(
      summary: capped,
      uptoMessageId: uptoId,
      compressedCount: split.older.length,
      beforeTokens: beforeTokens,
      afterTokens: ContextUsageEstimator.estimateTokens(capped),
    );
  }
}
