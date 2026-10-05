import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../application/providers/api_configs_provider.dart';
import '../../application/providers/conversations_provider.dart';
import '../../application/providers/database_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/constants.dart';
import '../../data/secure_storage/api_key_store.dart';
import '../../domain/models/api_config.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/message.dart';
import '../../services/llm_client.dart';
import '../../services/conversation_exporter.dart';
import '../api_config/api_config_list_page.dart';
import '../search/global_search_page.dart';
import '../widgets/message_bubble.dart';
import 'chat_session_drawer.dart';
import 'conversation_param_page.dart';

/// 聊天页（三栏中间栏 / 移动端聊天 Tab）。
///
/// M0 对话闭环：输入发送 → 用户消息即时落库并显示 → LLM SSE 流式请求 →
/// 增量更新助手气泡 → 完成/失败/停止三态落库；顶栏展示当前 API/模型名；
/// 未配置 API 时给出引导跳设置页。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  static const int _historyLimit = 20;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _messageKeys = {};
  CancelToken? _cancelToken;
  bool _isSending = false;
  int? _currentAssistantId;

  /// R3「引用」：被引用消息的原文（输入框上方展示引用预览条，可取消）。
  String? _quoteContent;

  /// R9：已选择待发送的附件（相册图片 / 文件），展示在输入框上方可删除。
  final List<MessageAttachment> _pendingAttachments = [];

  /// R8：语音输入状态。
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _speechInitialized = false;
  bool _isListening = false;

  /// 是否已对 API 配置触发过「空态兜底加载」，防止 provider 未初始化/
  /// 加载失败时首页长期误显示「尚未添加 API 配置」。
  bool _apiEmptyLoadTriggered = false;

  @override
  void initState() {
    super.initState();
    // R8：异步探测语音能力（设备/权限不可用时隐藏按钮，不崩溃）。
    _initSpeech();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedConversationProvider);
    final messages = ref.watch(messagesProvider);
    final apiConfigs = ref.watch(apiConfigsProvider);
    // R12：监听到全局搜索跳转目标后滚动定位到对应消息。
    ref.listen(pendingSearchMessageIdProvider, (prev, next) {
      if (next != null) {
        _scrollToMessage(messages, next);
      }
    });
    // 兜底：列表为空且 provider 从未成功加载时，主动补一次加载，
    // 避免「尚未添加 API 配置」误报（数据实际存在但 state 未就绪）。
    final apiNotifier = ref.read(apiConfigsProvider.notifier);
    if (apiConfigs.isEmpty && !apiNotifier.loaded && !_apiEmptyLoadTriggered) {
      _apiEmptyLoadTriggered = true;
      Future<void>(apiNotifier.load);
    }
    final currentApi = _resolveApiConfig(apiConfigs, selected);
    final currentModel = _resolveModel(currentApi, selected);
    // 手机窄屏才需要会话抽屉；宽屏三栏已有左侧会话列表，不重复叠加。
    final isNarrow = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      drawer: isNarrow ? const ChatSessionDrawer() : null,
      appBar: AppBar(
        leading: isNarrow
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  tooltip: '会话列表',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selected?.title ?? 'LLM Chat',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            InkWell(
              onTap: _showModelPicker,
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _buildSubtitle(currentApi, currentModel),
                      style: const TextStyle(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // R12：跨会话全文搜索入口（窄屏聊天页同样可用）。
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索聊天记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GlobalSearchPage()),
            ),
          ),
          if (selected != null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '会话参数',
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ConversationParamPage(conversation: selected),
                  ),
                );
                if (changed == true && mounted) {
                  final updated = await ref
                      .read(appDatabaseProvider)
                      .conversationRepository
                      .getById(selected.id!);
                  if (updated != null) {
                    ref.read(selectedConversationProvider.notifier).state =
                        updated;
                  }
                }
              },
            ),
          // R11：导出当前会话（Markdown / 纯文本 / PDF）。
          if (selected != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: '导出会话',
              onPressed: () {
                final exportMessages = messages.where((m) {
                  return m.role == 'user' || m.role == 'assistant';
                }).toList();
                if (exportMessages.isEmpty) {
                  _showSnack('当前会话暂无消息可导出');
                  return;
                }
                ConversationExporter.exportConversation(
                  context,
                  selected,
                  exportMessages,
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: selected == null
                ? _buildEmptyState(context, apiConfigs.isEmpty)
                : messages.isEmpty
                    ? const Center(child: Text('发送第一条消息开始对话'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          final messageKey = message.id == null
                              ? null
                              : _messageKeys.putIfAbsent(
                                  message.id!, () => GlobalKey());
                          final bubble = MessageBubble(
                            isUser: message.role == 'user',
                            content: message.content,
                            status: message.status,
                            errorMessage: message.errorMessage,
                            onRetry: message.role == 'assistant' &&
                                    message.status == 'error'
                                ? () => _retry(message)
                                : null,
                            reasoningContent: message.reasoningContent,
                            reasoningDurationMs: message.reasoningDurationMs,
                            reasoningTokens: message.reasoningTokens,
                            attachments: message.attachments,
                            // R3 消息操作菜单回调：
                            // 重新生成（仅已完成的助手消息）/ 编辑（仅用户消息）/
                            // 删除 / 引用；对应菜单项在回调为 null 时自动隐藏。
                            onRegenerate: message.role == 'assistant' &&
                                    message.status == 'done'
                                ? () => _regenerate(message)
                                : null,
                            onEdit: message.role == 'user'
                                ? () => _editMessage(message)
                                : null,
                            onDelete: () => _deleteMessage(message),
                            onQuote: () => _quoteMessage(message),
                          );
                          return messageKey == null
                              ? bubble
                              : KeyedSubtree(key: messageKey, child: bubble);
                        },
                      ),
          ),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, bool hasApi) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasApi ? Icons.forum_outlined : Icons.dns_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              hasApi
                  ? '选择会话开始聊天\n也可以直接输入消息，将自动新建会话'
                  : '尚未添加 API 配置',
              textAlign: TextAlign.center,
            ),
            if (!hasApi) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _goAddApi,
                icon: const Icon(Icons.add),
                label: const Text('去添加 API'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 无 API 引导：窄屏切到设置 Tab，宽屏直接打开添加 API 页面。
  void _goAddApi() {
    final width = MediaQuery.of(context).size.width;
    if (width < 900) {
      ref.read(mobileTabProvider.notifier).state = 1;
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ApiConfigListPage()),
      );
    }
  }

  Widget _buildInputBar(BuildContext context) {
    final theme = Theme.of(context);
    final quote = _quoteContent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // R9：待发送附件预览条（缩略图/文件卡片，可删除）。
            if (_pendingAttachments.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _pendingAttachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final att = _pendingAttachments[index];
                      return Stack(
                        children: [
                          if (att.isImage && att.dataBase64 != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.memory(
                                base64Decode(att.dataBase64!),
                                width: 48,
                                height: 48,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.image_outlined),
                              ),
                            )
                          else
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: theme.colorScheme.outlineVariant),
                              ),
                              child: Icon(
                                Icons.insert_drive_file_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: InkWell(
                              onTap: () => setState(
                                  () => _pendingAttachments.removeAt(index)),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            // 引用预览条（R3）：引用内容带入输入框时展示，可一键取消。
            if (quote != null && quote.trim().isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.format_quote,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _quotePreview(quote),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: '取消引用',
                      color: theme.colorScheme.onSurfaceVariant,
                      onPressed: () => setState(() => _quoteContent = null),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // R9：附件入口（相册图片 / 文件选择器）。
                IconButton(
                  onPressed: _showAttachmentMenu,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '添加图片或文件',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    // R6 多行输入：自动增高，最大约 6 行，发送后重置高度。
                    minLines: 1,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    onSubmitted: (_) {
                      if (!_isSending) _send();
                    },
                    decoration: const InputDecoration(
                      hintText: '输入消息…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // R8：语音输入按钮。设备/权限不可用时隐藏，不崩溃。
                if (_speechAvailable)
                  IconButton(
                    onPressed: _isListening ? _stopListening : _startListening,
                    icon: Icon(
                      _isListening ? Icons.graphic_eq : Icons.mic_none,
                      color: _isListening
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _isListening ? '结束语音输入' : '语音输入',
                  ),
                const SizedBox(width: 4),
                // R7 停止生成：生成过程中发送按钮变为「停止」按钮，可中断 SSE。
                if (_isSending)
                  IconButton.filled(
                    onPressed: _stop,
                    icon: const Icon(Icons.stop),
                    tooltip: '停止生成',
                  )
                else
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                    tooltip: '发送',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 发送消息：自动建会话 → 用户消息落库 → 流式请求 → 三态落库。
  Future<void> _send([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    // R9：附件与文本可同时发送；两者皆空才拦截。
    final hasAttachments = _pendingAttachments.isNotEmpty;
    if (text.isEmpty && !hasAttachments || _isSending) return;
    if (preset == null) _inputController.clear();
    final attachments =
        preset == null ? List<MessageAttachment>.of(_pendingAttachments) : const <MessageAttachment>[];
    setState(() {
      _isSending = true;
      if (preset == null) _pendingAttachments.clear();
    });
    _currentAssistantId = null;
    _cancelToken = CancelToken();

    int? conversationId;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;

      // 1) 无选中会话时自动创建会话（PRD 4.3.1 / 任务 4）。
      var conv = ref.read(selectedConversationProvider);
      if (conv == null) {
        final id = await ref.read(conversationsProvider.notifier).create();
        conv = ref.read(conversationsProvider).firstWhere((c) => c.id == id);
        ref.read(selectedConversationProvider.notifier).state = conv;
        await ref.read(messagesProvider.notifier).loadForConversation(id);
      }
      conversationId = conv.id!;

      // 2) 用户消息即时落库并显示。
      await ref.read(messagesProvider.notifier).add(ChatMessage(
            conversationId: conversationId,
            role: 'user',
            content: text,
            status: 'done',
            createdAt: now,
            attachments: attachments,
          ));
      await _updateConversationMeta(conversationId, _summarize(text), now);
      _scrollToBottom();

      // 3) 助手占位消息（streaming），流式增量更新其内容。
      final assistantId =
          await ref.read(messagesProvider.notifier).add(ChatMessage(
                conversationId: conversationId,
                role: 'assistant',
                content: '',
                status: 'streaming',
                createdAt: now + 1,
              ));
      _currentAssistantId = assistantId;

      // 4) 解析 API 配置与密钥。
      final config = _resolveApiConfig(ref.read(apiConfigsProvider), conv);
      if (config == null) {
        throw const LlmException(LlmErrorType.auth, '尚未配置 API，请先到设置页添加 API 配置');
      }
      final apiKey = await ApiKeyStore.read(config.apiKeyRef);
      if (apiKey == null || apiKey.isEmpty) {
        throw const LlmException(LlmErrorType.auth, 'API Key 缺失，请到设置页重新填写');
      }
      final model = _resolveModel(config, conv);
      if (model.isEmpty) {
        throw const LlmException(LlmErrorType.model, '当前 API 配置未填写模型，请到设置页补充');
      }

      // 5) 参数来源：会话覆盖值优先，否则取 settings 表全局默认（PRD 4.5.1）。
      //    R13：会话设置了默认模板时，模板内容作为 system prompt（优先于全局设置）。
      final settings = ref.read(settingsProvider);
      final temperature = conv.temperature ??
          _doubleSetting(
              settings, AppConstants.settingTemperature, AppConstants.defaultTemperature);
      final maxTokens = conv.maxTokens ??
          _intSetting(
              settings, AppConstants.settingMaxTokens, AppConstants.defaultMaxTokens);
      final topP = conv.topP ??
          _doubleSetting(settings, AppConstants.settingTopP, AppConstants.defaultTopP);
      final frequencyPenalty = conv.frequencyPenalty ??
          _doubleSetting(
              settings, AppConstants.settingFrequencyPenalty, AppConstants.defaultFrequencyPenalty);
      final presencePenalty = conv.presencePenalty ??
          _doubleSetting(
              settings, AppConstants.settingPresencePenalty, AppConstants.defaultPresencePenalty);
      var systemPrompt = conv.systemPrompt ?? settings[AppConstants.settingSystemPrompt];
      if (conv.promptTemplateId != null) {
        final template = await ref
            .read(appDatabaseProvider)
            .promptTemplateRepository
            .getById(conv.promptTemplateId!);
        if (template != null && template.content.trim().isNotEmpty) {
          systemPrompt = template.content;
        }
      }

      // 6) 组装上下文：system prompt + 最近 N 条 done 消息 + 本次（PRD 4.4.1）。
      //    R9：含附件的用户消息按 OpenAI 多模态格式附加（image_url / file_url
      //    文本块），纯文本消息保持 string content 兼容旧模型。
      final llmMessages = <Map<String, dynamic>>[];
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        llmMessages.add({'role': 'system', 'content': systemPrompt});
      }
      final history = ref
          .read(messagesProvider)
          .where((m) => m.status == 'done' && m.id != assistantId)
          .toList();
      final recent = history.length > _historyLimit
          ? history.sublist(history.length - _historyLimit)
          : history;
      for (final m in recent) {
        llmMessages.add({
          'role': m.role == 'user' ? 'user' : 'assistant',
          'content': m.role == 'user' && m.attachments.isNotEmpty
              ? _buildMultimodalContent(m.content, m.attachments)
              : m.content,
        });
      }
      llmMessages.add({
        'role': 'user',
        'content': _buildMultimodalContent(text, attachments),
      });

      // 7) SSE 流式请求：增量更新气泡。
      final result = await LlmClient().chatStream(
        baseUrl: config.baseUrl,
        apiKey: apiKey,
        model: model,
        messages: llmMessages,
        onDelta: (delta) {
          ref.read(messagesProvider.notifier)
              .appendStreamingFragment(assistantId, delta);
          _scrollToBottom();
        },
        onReasoningDelta: (delta) {
          // 思维链增量实时累积到消息的 reasoningContent（与正文分离），
          // 使生成过程中即可看到「思考过程」折叠卡片。
          ref.read(messagesProvider.notifier)
              .appendReasoningFragment(assistantId, delta);
          _scrollToBottom();
        },
        cancelToken: _cancelToken,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
        frequencyPenalty: frequencyPenalty,
        presencePenalty: presencePenalty,
      );

      // 8) 完成态落库并刷新会话摘要；同时将缓存命中写入独立记录表
      // （设置页「命中缓存」数据源，与聊天历史解耦可单独清空）。
      await ref.read(messagesProvider.notifier).update(ChatMessage(
            id: assistantId,
            conversationId: conversationId,
            role: 'assistant',
            content: result.content,
            status: 'done',
            modelId: model,
            promptTokens: result.promptTokens,
            completionTokens: result.completionTokens,
            reasoningContent: result.reasoningContent,
            reasoningDurationMs: result.reasoningDurationMs,
            reasoningTokens: result.reasoningTokens,
            cachedTokens: result.cachedTokens,
            createdAt: now + 1,
          ));
      if (result.cachedTokens != null || result.promptTokens != null) {
        await ref
            .read(appDatabaseProvider)
            .messageRepository
            .insertCacheHit(CacheHitRecord(
              modelId: model,
              cachedTokens: result.cachedTokens ?? 0,
              promptTokens: result.promptTokens,
              completionTokens: result.completionTokens,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ));
      }
      await _updateConversationMeta(
        conversationId,
        _summarize(result.content),
        DateTime.now().millisecondsSinceEpoch,
      );
    } on LlmException catch (e) {
      await _finishAssistant(
        status: e.isCancelled ? 'stopped' : 'error',
        errorMessage: e.message,
      );
    } catch (e) {
      await _finishAssistant(status: 'error', errorMessage: '发送失败：$e');
    } finally {
      _cancelToken = null;
      _currentAssistantId = null;
      if (mounted) setState(() => _isSending = false);
    }
  }

  /// 停止生成：取消当前 CancelToken，流式请求抛出 cancelled 后进入停止态。
  void _stop() {
    _cancelToken?.cancel();
  }

  // ── R8 语音输入 ──────────────────────────────────────────────

  /// 初始化语音识别（R8）：设备不支持或权限被拒时隐藏按钮，不崩溃。
  Future<void> _initSpeech() async {
    if (_speechInitialized) return;
    _speechInitialized = true;
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' && _isListening) {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (!mounted) return;
      setState(() => _speechAvailable = ok);
    } catch (_) {
      if (mounted) setState(() => _speechAvailable = false);
    }
  }

  Future<void> _startListening() async {
    if (_isListening) return;
    try {
      final ok = await _speech.listen(
        onResult: (result) {
          if (!result.finalResult) return;
          final recognized = result.recognizedWords.trim();
          if (recognized.isEmpty) return;
          final current = _inputController.text.trim();
          _inputController.text = current.isEmpty
              ? recognized
              : '$current $recognized';
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
        },
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          localeId: 'zh_CN',
        ),
      );
      if (!mounted) return;
      setState(() => _isListening = ok);
      if (!ok) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('语音输入不可用，请检查麦克风权限')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isListening = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('语音输入失败，请检查麦克风权限')));
      }
    }
  }

  void _stopListening() {
    _speech.stop();
    if (mounted) setState(() => _isListening = false);
  }

  // ── R9 附件上传 ──────────────────────────────────────────────

  /// 附件入口菜单：从相册选择图片 / 选择文件。
  Future<void> _showAttachmentMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择图片'),
              onTap: () => Navigator.of(sheetContext).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('选择文件'),
              onTap: () => Navigator.of(sheetContext).pop('file'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'image') {
      await _pickImageFromGallery();
    } else {
      await _pickFile();
    }
  }

  /// 相册选图：读取原图并压缩为 Base64 图片附件（OpenAI image_url 兼容）。
  Future<void> _pickImageFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(MessageAttachment(
          type: 'image',
          name: picked.name,
          mimeType: 'image/jpeg',
          sizeBytes: bytes.length,
          dataBase64: base64Encode(bytes),
        ));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('选择图片失败：$e')));
      }
    }
  }

  /// 文件选择器：读取文件为文件附件（附文本预览，便于模型理解）。
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      final path = file.path;
      Uint8List? data = bytes;
      if (data == null && path != null) {
        data = await File(path).readAsBytes();
      }
      if (data == null) return;
      final size = data.length;
      final dataBase64 = size <= 20 * 1024 * 1024 ? base64Encode(data) : null;
      // 文本类文件提取前 120 字符预览；其余跳过。
      String? preview;
      final lowerName = file.name.toLowerCase();
      final isTextLike = lowerName.endsWith('.txt') ||
          lowerName.endsWith('.md') ||
          lowerName.endsWith('.json') ||
          lowerName.endsWith('.yaml') ||
          lowerName.endsWith('.yml') ||
          lowerName.endsWith('.csv') ||
          lowerName.endsWith('.log') ||
          lowerName.endsWith('.xml') ||
          lowerName.endsWith('.py') ||
          lowerName.endsWith('.dart') ||
          lowerName.endsWith('.js') ||
          lowerName.endsWith('.ts') ||
          lowerName.endsWith('.java') ||
          lowerName.endsWith('.c') ||
          lowerName.endsWith('.cpp') ||
          lowerName.endsWith('.html') ||
          lowerName.endsWith('.sql');
      if (isTextLike && size < 512 * 1024) {
        try {
          final decoded = utf8.decode(data, allowMalformed: true);
          preview = decoded.trim().replaceAll(RegExp(r'\s+'), ' ');
          if (preview.length > 120) preview = preview.substring(0, 120);
        } catch (_) {
          preview = null;
        }
      }
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(MessageAttachment(
          type: 'file',
          name: file.name,
          mimeType: file.extension?.isNotEmpty == true
              ? 'application/${file.extension}'
              : 'application/octet-stream',
          sizeBytes: size,
          dataBase64: dataBase64,
          textPreview: preview,
        ));
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text('选择文件失败：$e')));
      }
    }
  }

  /// R9：组装 OpenAI 兼容多模态 content。
  ///
  /// 无附件时返回纯文本字符串（兼容旧模型/旧消息）；有附件时返回
  /// `[{type: text}, {type: image_url}, ...]` 数组。
  dynamic _buildMultimodalContent(
      String text, List<MessageAttachment> attachments) {
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
            'image_url': {'url': 'data:${att.mimeType ?? 'image/jpeg'};base64,$data'},
          });
        }
      } else {
        final data = att.dataBase64;
        if (data != null && data.isNotEmpty) {
          // OpenAI 兼容文件引用（部分网关支持 file_url）。
          parts.add({
            'type': 'file',
            'file': {
              'file_name': att.name,
              'file_data': 'data:${att.mimeType ?? 'application/octet-stream'};base64,$data',
            },
          });
        }
      }
    }
    return parts;
  }

  /// 失败/停止终态落库（保留已生成内容，错误附带中文提示）。
  Future<void> _finishAssistant({
    required String status,
    required String errorMessage,
  }) async {
    final id = _currentAssistantId;
    final conv = ref.read(selectedConversationProvider);
    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage)));
      return;
    }
    ChatMessage? current;
    for (final m in ref.read(messagesProvider)) {
      if (m.id == id) {
        current = m;
        break;
      }
    }
    if (current == null) return;
    await ref.read(messagesProvider.notifier)
        .update(current.copyWith(status: status, errorMessage: errorMessage));
    if (conv != null) {
      await _updateConversationMeta(
        conv.id!,
        _summarize(current.content),
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  /// 重试：重发失败助手消息之前最近的用户消息。
  void _retry(ChatMessage failed) {
    final msgs = ref.read(messagesProvider);
    final index = msgs.indexWhere((m) => m.id == failed.id);
    if (index < 0) return;
    for (var i = index - 1; i >= 0; i--) {
      if (msgs[i].role == 'user') {
        _send(msgs[i].content);
        return;
      }
    }
  }

  /// R3「重新生成」：删除该助手消息及其之后的所有消息，
  /// 并用其之前最近一条用户消息重新发起请求。
  Future<void> _regenerate(ChatMessage assistantMessage) async {
    if (_isSending) {
      _showSnack('正在生成回复，请稍候…');
      return;
    }
    final msgs = ref.read(messagesProvider);
    final index = msgs.indexWhere((m) => m.id == assistantMessage.id);
    if (index < 0) return;
    ChatMessage? userMessage;
    for (var i = index - 1; i >= 0; i--) {
      if (msgs[i].role == 'user') {
        userMessage = msgs[i];
        break;
      }
    }
    if (userMessage == null) return;
    await ref.read(messagesProvider.notifier).deleteFrom(userMessage.id!);
    await _send(userMessage.content);
  }

  /// R3「编辑」（仅用户消息）：弹窗编辑原文，保存后删除该消息及之后
  /// 的所有消息，用新内容重新发送生成新回复。
  Future<void> _editMessage(ChatMessage message) async {
    if (_isSending) {
      _showSnack('正在生成回复，请稍候…');
      return;
    }
    final controller = TextEditingController(text: message.content);
    final newText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑消息'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '输入修改后的内容',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存并重发'),
          ),
        ],
      ),
    );
    final trimmed = newText?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await ref.read(messagesProvider.notifier).deleteFrom(message.id!);
    await _send(trimmed);
  }

  /// R3「删除」：确认后删除该条消息；若删除的是正在流式生成的
  /// 助手消息，同时中断生成。
  Future<void> _deleteMessage(ChatMessage message) async {
    if (_isSending) {
      _showSnack('正在生成回复，请稍候…');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除消息'),
        content: const Text('确定删除这条消息吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (message.id != null && message.id == _currentAssistantId) {
      _stop();
    }
    await ref.read(messagesProvider.notifier).remove(message);
  }

  /// R3「引用」：将消息内容以引用块样式带入输入框（可取消）。
  void _quoteMessage(ChatMessage message) {
    setState(() => _quoteContent = message.content);
  }

  /// 引用预览：压缩空白并截断，用于输入框上方预览条。
  String _quotePreview(String content) {
    var plain = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (plain.length > 40) plain = '${plain.substring(0, 40)}…';
    return plain;
  }

  /// 刷新会话摘要与最后更新时间（会话列表自动联动）。
  Future<void> _updateConversationMeta(int convId, String summary, int now) async {
    Conversation? conv;
    for (final c in ref.read(conversationsProvider)) {
      if (c.id == convId) {
        conv = c;
        break;
      }
    }
    if (conv == null) return;
    await ref.read(conversationsProvider.notifier)
        .update(conv.copyWith(lastMessage: summary, updatedAt: now));
  }

  /// 当前 API 配置：会话绑定 > 首个启用 > 首个。
  ApiConfig? _resolveApiConfig(List<ApiConfig> configs, Conversation? conv) {
    if (configs.isEmpty) return null;
    if (conv != null && conv.apiConfigId != null) {
      for (final c in configs) {
        if (c.id == conv.apiConfigId) return c;
      }
    }
    for (final c in configs) {
      if (c.enabled) return c;
    }
    return configs.first;
  }

  /// 当前模型：会话绑定 > 配置第一个模型。
  String _resolveModel(ApiConfig? config, Conversation? conv) {
    if (conv != null && conv.modelId != null && conv.modelId!.isNotEmpty) {
      return conv.modelId!;
    }
    if (config != null && config.modelIds.isNotEmpty) {
      return config.modelIds.first;
    }
    return '';
  }

  /// 顶栏模型名点击：弹出当前服务商可用模型列表供切换。
  ///
  /// - 未配置 API：提示先添加 API 配置；
  /// - 服务商无模型：提示「请先在服务商配置中添加模型」并提供跳转；
  /// - 有模型：底部弹层选择，切换结果持久化到会话 modelId。
  Future<void> _showModelPicker() async {
    final apiConfigs = ref.read(apiConfigsProvider);
    final conv = ref.read(selectedConversationProvider);
    final api = _resolveApiConfig(apiConfigs, conv);
    if (api == null) {
      _showSnack('尚未配置 API，请先到设置页添加 API 配置');
      return;
    }
    if (api.modelIds.isEmpty) {
      _showNoModelSheet(api.name);
      return;
    }

    final currentModel = _resolveModel(api, conv);
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '更换模型',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                api.name,
                style: Theme.of(sheetContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final model in api.modelIds)
                    ListTile(
                      title: Text(
                        model,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: model == currentModel
                          ? Icon(
                              Icons.check,
                              color: Theme.of(sheetContext).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(model),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked == null || picked == currentModel) return;
    await _switchModel(picked);
  }

  /// 切换当前会话使用的模型：写回会话 modelId 并持久化。
  Future<void> _switchModel(String model) async {
    final conv = ref.read(selectedConversationProvider);
    if (conv == null) {
      _showSnack('请先发送消息创建会话，再切换模型');
      return;
    }
    final updated = conv.copyWith(modelId: model);
    ref.read(selectedConversationProvider.notifier).state = updated;
    await ref.read(conversationsProvider.notifier).update(updated);
    _showSnack('已切换到模型：$model');
  }

  /// 服务商无模型时的空态提示，并提供「去配置」跳转。
  void _showNoModelSheet(String apiName) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.model_training_outlined,
                  size: 40, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                '请先在服务商配置中添加模型',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '服务商「$apiName」尚未配置可用模型，添加后才能切换。',
                style: Theme.of(sheetContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ApiConfigListPage()),
                    );
                  },
                  child: const Text('去配置'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _buildSubtitle(ApiConfig? api, String model) {
    if (api == null) return '未配置 API · 请到设置页添加';
    if (model.isEmpty) return api.name;
    return '${api.name} · $model';
  }

  double _doubleSetting(Map<String, String> settings, String key, double fallback) {
    final v = settings[key];
    if (v == null) return fallback;
    return double.tryParse(v) ?? fallback;
  }

  int _intSetting(Map<String, String> settings, String key, int fallback) {
    final v = settings[key];
    if (v == null) return fallback;
    return int.tryParse(v) ?? fallback;
  }

  /// 会话列表摘要：去 Markdown 标记后的纯文本，截断 40 字（PRD 4.3.2）。
  String _summarize(String text) {
    var plain = text
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(RegExp(r'`[^`]*`'), ' ')
        .replaceAll(RegExp(r'[#>*_~\[\]()!|-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (plain.length > 40) plain = plain.substring(0, 40);
    return plain;
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// R12：跨会话搜索跳转定位。先按索引估算位置滚动，待目标消息
  /// 构建后再用 GlobalKey 精确定位到可见区域中部。
  void _scrollToMessage(List<ChatMessage> messages, int messageId) {
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0) {
      ref.read(pendingSearchMessageIdProvider.notifier).state = null;
      return;
    }
    if (!_scrollController.hasClients) {
      ref.read(pendingSearchMessageIdProvider.notifier).state = null;
      return;
    }
    final estimated = (index * 96.0)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    _scrollController.jumpTo(estimated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _messageKeys[messageId];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.3,
        );
      }
      ref.read(pendingSearchMessageIdProvider.notifier).state = null;
      _showSnack('已定位到搜索结果');
    });
  }
}
