import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../api_config/api_config_list_page.dart';
import '../widgets/message_bubble.dart';
import 'chat_session_drawer.dart';

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
  CancelToken? _cancelToken;
  bool _isSending = false;
  int? _currentAssistantId;

  /// 是否已对 API 配置触发过「空态兜底加载」，防止 provider 未初始化/
  /// 加载失败时首页长期误显示「尚未添加 API 配置」。
  bool _apiEmptyLoadTriggered = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedConversationProvider);
    final messages = ref.watch(messagesProvider);
    final apiConfigs = ref.watch(apiConfigsProvider);
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
                          return MessageBubble(
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
                          );
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
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
            const SizedBox(width: 8),
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
      ),
    );
  }

  /// 发送消息：自动建会话 → 用户消息落库 → 流式请求 → 三态落库。
  Future<void> _send([String? preset]) async {
    final text = (preset ?? _inputController.text).trim();
    if (text.isEmpty || _isSending) return;
    if (preset == null) _inputController.clear();
    setState(() => _isSending = true);
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
      final settings = ref.read(settingsProvider);
      final temperature = conv.temperature ??
          _doubleSetting(
              settings, AppConstants.settingTemperature, AppConstants.defaultTemperature);
      final maxTokens = conv.maxTokens ??
          _intSetting(
              settings, AppConstants.settingMaxTokens, AppConstants.defaultMaxTokens);
      final topP = conv.topP ??
          _doubleSetting(settings, AppConstants.settingTopP, AppConstants.defaultTopP);
      final systemPrompt = conv.systemPrompt ?? settings[AppConstants.settingSystemPrompt];

      // 6) 组装上下文：system prompt + 最近 N 条 done 消息 + 本次（PRD 4.4.1）。
      final llmMessages = <Map<String, String>>[];
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
          'content': m.content,
        });
      }
      llmMessages.add({'role': 'user', 'content': text});

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
        cancelToken: _cancelToken,
        temperature: temperature,
        maxTokens: maxTokens,
        topP: topP,
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
}
