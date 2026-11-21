import '../core/constants.dart';

import '../domain/models/message.dart';
import 'context_compressor.dart';

/// 请求内容的 token 估算器（v1.2.25）。
///
/// 与 [ContextAssembler] 的实际拼装口径严格一致：
/// - 文本按 [ContextUsageEstimator.estimateTokens] 中英加权估算；
/// - 图片按固定 [imageTokens] 估算（base64 不参与字符估算）；
/// - 未能解析正文、只能原样携带的文件按 [rawFileTokens] 估算。
class ContextTokenEstimator {
  const ContextTokenEstimator._();

  /// 单张图片固定估算 token（各厂商差异大，取偏保守值）。
  static const int imageTokens = 1000;

  /// 无法解析正文、只能 base64 携带文件时的固定估算 token。
  static const int rawFileTokens = 2000;

  /// 估算已拼装好的 content（String 或多模态 List）。
  static int contentTokens(dynamic content) {
    if (content is String) {
      return ContextUsageEstimator.estimateTokens(content);
    }
    if (content is List) {
      var sum = 0;
      for (final part in content) {
        if (part is! Map) continue;
        final type = part['type'];
        if (type == 'text') {
          sum += ContextUsageEstimator.estimateTokens(
              (part['text'] as String?) ?? '');
        } else if (type == 'image_url') {
          sum += imageTokens;
        } else {
          sum += rawFileTokens;
        }
      }
      return sum;
    }
    return 0;
  }

  /// 估算一条历史消息（含附件正文 / 图片）。
  static int messageTokens(
    ChatMessage message,
    dynamic Function(String, List<MessageAttachment>) buildContent,
  ) {
    final content = message.role == 'user' && message.attachments.isNotEmpty
        ? buildContent(message.content, message.attachments)
        : message.content;
    return contentTokens(content) + ContextUsageEstimator.perMessageOverhead;
  }
}

/// 一次请求的组装结果。
class ContextAssembly {
  const ContextAssembly({
    required this.messages,
    required this.estimateTokens,
    required this.historyIncluded,
    required this.historyDropped,
  });

  /// 最终发给模型的消息数组。
  final List<Map<String, dynamic>> messages;

  /// 与 [messages] 同口径的 token 估算（供压缩判定与预算校验复用）。
  final int estimateTokens;

  /// 实际进入请求的历史消息条数。
  final int historyIncluded;

  /// 因超出 token 预算被跳过的历史消息条数。
  final int historyDropped;
}

/// 上下文组装（v1.2.25，取代 chat_page 与 active_task_scheduler 各自的拼接逻辑）。
///
/// 统一保证：
/// 1. system 段顺序固定：全局提示词 → 系统提示词 → 记忆 → 历史摘要；
/// 2. 历史只取最近 [historyLimit] 条，并从最新往回累加 token 预算，
///    超预算的单条消息跳过（continue）而非终止循环，最新消息必达；
/// 3. 估算与实际拼装使用同一份 content，避免口径漂移。
class ContextAssembler {
  const ContextAssembler._();

  /// 裁剪空白后的 system 段落列表（顺序固定）。
  static List<String> buildSystemSegments({
    String? globalPrompt,
    String? systemPrompt,
    List<String> memoryLines = const [],
    String? contextSummary,
  }) {
    final segments = <String>[];
    if (globalPrompt != null && globalPrompt.trim().isNotEmpty) {
      segments.add(globalPrompt.trim());
    }
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      segments.add(systemPrompt.trim());
    }
    if (memoryLines.isNotEmpty) {
      segments.add('以下是本会话的关键记忆，请参考：\n${memoryLines.join('\n')}');
    }
    final summary = (contextSummary ?? '').trim();
    if (summary.isNotEmpty) {
      segments.add(
          '以下是本次会话较早历史的压缩摘要，请作为背景信息参考：\n'
          '【${AppConstants.contextSummarySectionTitle}】\n$summary');
    }
    return segments;
  }

  /// 组装一次聊天请求。
  ///
  /// [history] 必须是「已剔除本轮用户消息」且「已按摘要游标过滤」的完整历史，
  /// 本方法内部只取最近 [historyLimit] 条并在 [tokenBudget] 内裁剪。
  /// [appendCurrentUser] 为 false（变体保留模式）时不追加本轮用户消息，
  /// 因为该消息本身就在历史中。
  static ContextAssembly assemble({
    String? globalPrompt,
    String? systemPrompt,
    List<String> memoryLines = const [],
    String? contextSummary,
    required List<ChatMessage> history,
    int summaryUptoId = 0,
    required int historyLimit,
    required int tokenBudget,
    required String currentUserText,
    List<MessageAttachment> currentAttachments = const [],
    bool appendCurrentUser = true,
    String? userInstruction,
    required dynamic Function(String, List<MessageAttachment>) buildContent,
  }) {
    final messages = <Map<String, dynamic>>[];
    var used = ContextUsageEstimator.messagesOverhead;

    for (final segment in buildSystemSegments(
      globalPrompt: globalPrompt,
      systemPrompt: systemPrompt,
      memoryLines: memoryLines,
      contextSummary: contextSummary,
    )) {
      messages.add({'role': 'system', 'content': segment});
      used += ContextUsageEstimator.estimateTokens(segment) +
          ContextUsageEstimator.perMessageOverhead;
    }

    // 尾部保留的本轮 user 段与附加指令先占预算，保证其一定进入请求。
    var tailReserved = 0;
    if (appendCurrentUser) {
      tailReserved += ContextTokenEstimator.contentTokens(
              buildContent(currentUserText, currentAttachments)) +
          ContextUsageEstimator.perMessageOverhead;
    }
    final instruction = userInstruction?.trim();
    if (instruction != null && instruction.isNotEmpty) {
      tailReserved += ContextUsageEstimator.estimateTokens(instruction) +
          ContextUsageEstimator.perMessageOverhead;
    }
    used += tailReserved;

    // 已压缩进摘要的消息不再参与请求（原始消息仍完整保留在会话记录中）。
    final visible = summaryUptoId > 0
        ? history.where((m) => (m.id ?? 0) > summaryUptoId).toList()
        : history;
    final recent = visible.length > historyLimit
        ? visible.sublist(visible.length - historyLimit)
        : visible;
    final picked = <Map<String, dynamic>>[];
    var dropped = 0;
    for (var i = recent.length - 1; i >= 0; i--) {
      final message = recent[i];
      final content =
          message.role == 'user' && message.attachments.isNotEmpty
              ? buildContent(message.content, message.attachments)
              : message.content;
      final cost = ContextTokenEstimator.contentTokens(content) +
          ContextUsageEstimator.perMessageOverhead;
      // 预算不足时跳过该条（continue），继续尝试更靠后的更新消息；
      // 首个进入的历史消息（即最新一条）无条件保留，确保最新对话必达。
      if (picked.isNotEmpty && used + cost > tokenBudget) {
        dropped++;
        continue;
      }
      used += cost;
      picked.insert(0, {
        'role': message.role == 'user' ? 'user' : 'assistant',
        'content': content,
      });
    }
    messages.addAll(picked);

    if (appendCurrentUser) {
      messages.add({
        'role': 'user',
        'content': buildContent(currentUserText, currentAttachments),
      });
    }
    if (instruction != null && instruction.isNotEmpty) {
      messages.add({'role': 'user', 'content': instruction});
    }

    return ContextAssembly(
      messages: messages,
      estimateTokens: used,
      historyIncluded: picked.length,
      historyDropped: dropped,
    );
  }
}
