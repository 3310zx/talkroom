import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/api_configs_provider.dart';
import '../../application/providers/conversations_provider.dart';
import '../../application/providers/database_provider.dart';
import '../../application/providers/memories_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../domain/models/api_config.dart';
import '../../domain/models/conversation.dart';
import '../memories/memories_page.dart';
import 'conversation_param_page.dart';

/// 宽屏三栏右侧辅助面板（平板端布局）。
///
/// 展示当前会话与所用服务商/模型/参数信息，并提供「设置」入口。
/// v1.2.20：可用模型列表支持点击切换（与移动端顶栏行为一致，写回会话
/// modelId 并持久化），选中项高亮 + 对勾反馈；底部补偿系统导航键 inset。
/// 数据解析逻辑与聊天页保持一致（API：会话绑定 > 首个启用 > 首个；
/// 模型：会话绑定 > 配置第一个）。
class ChatDetailPanel extends ConsumerWidget {
  const ChatDetailPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selected = ref.watch(selectedConversationProvider);
    final messages = ref.watch(messagesProvider);
    final apiConfigs = ref.watch(apiConfigsProvider);
    final settings = ref.watch(settingsProvider);
    final api = _resolveApiConfig(apiConfigs, selected);
    final model = _resolveModel(api, selected);

    return Scaffold(
      appBar: AppBar(
        title: const Text('详情'),
        centerTitle: true,
      ),
      body: SafeArea(
        // v1.2.20：底部避让系统导航键 —— Android edge-to-edge 下
        // MediaQuery.padding 为 0，改用 viewPadding 手动补偿，避免
        // frequency_penalty 等参数行与「编辑会话参数」按钮被导航键遮挡。
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            8,
            0,
            8 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: [
            if (selected == null)
              _buildEmpty(context)
            else ...[
              _sectionHeader(context, '会话'),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(
                  conversationDisplayTitle(selected.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '消息 ${messages.length} 条\n${_formatTime(selected.updatedAt)} 更新',
                ),
              ),
              const Divider(),
              _sectionHeader(context, '服务商'),
              ListTile(
                leading: Icon(
                  Icons.dns_outlined,
                  color: api?.enabled == true ? AppTheme.brandGreen : null,
                ),
                title: Text(api?.name ?? '未选择服务商'),
                subtitle: Text(
                  api == null ? '暂无可用 API 配置' : api.baseUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.model_training_outlined, size: 20),
                title: const Text('当前模型', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  model.isEmpty ? '未配置模型' : model,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (api != null && api.modelIds.isNotEmpty) ...[
                const Divider(),
                _sectionHeader(context, '可用模型'),
                // v1.2.20：模型项改为可点击切换，与移动端顶栏「更换模型」
                // 行为一致 —— 点击后写回会话 modelId 并持久化；选中项
                // 以背景高亮 + 对勾双重反馈，避免平板端无选中态反馈。
                for (final m in api.modelIds)
                  ListTile(
                    dense: true,
                    selected: m == model,
                    selectedTileColor:
                        Theme.of(context).colorScheme.primary.withValues(
                              alpha: 0.10,
                            ),
                    leading: Icon(
                      m == model ? Icons.check_circle : Icons.circle_outlined,
                      size: 18,
                      color: m == model
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    title: Text(
                      m,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: m == model ? null : () => _switchModel(ref, m, context),
                  ),
              ],
              const Divider(),
              _sectionHeader(context, '参数'),
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune, size: 20),
                title: const Text('temperature', style: TextStyle(fontSize: 13)),
                trailing: Text(
                  '${selected.temperature ?? double.tryParse(settings[AppConstants.settingTemperature] ?? '') ?? AppConstants.defaultTemperature}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune, size: 20),
                title: const Text('max_tokens', style: TextStyle(fontSize: 13)),
                trailing: Text(
                  '${selected.maxTokens ?? int.tryParse(settings[AppConstants.settingMaxTokens] ?? '') ?? AppConstants.defaultMaxTokens}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune, size: 20),
                title: const Text('top_p', style: TextStyle(fontSize: 13)),
                trailing: Text(
                  '${selected.topP ?? double.tryParse(settings[AppConstants.settingTopP] ?? '') ?? AppConstants.defaultTopP}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune, size: 20),
                title: const Text('frequency_penalty',
                    style: TextStyle(fontSize: 13)),
                trailing: Text(
                  '${selected.frequencyPenalty ?? double.tryParse(settings[AppConstants.settingFrequencyPenalty] ?? '') ?? AppConstants.defaultFrequencyPenalty}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune, size: 20),
                title: const Text('presence_penalty',
                    style: TextStyle(fontSize: 13)),
                trailing: Text(
                  '${selected.presencePenalty ?? double.tryParse(settings[AppConstants.settingPresencePenalty] ?? '') ?? AppConstants.defaultPresencePenalty}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.notes_outlined, size: 20),
                title:
                    const Text('System Prompt', style: TextStyle(fontSize: 13)),
                subtitle: Text(
                  selected.systemPrompt ??
                      settings[AppConstants.settingSystemPrompt] ??
                      '未设置',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 功能三：会话详情记忆区块。
              const Divider(),
              _sectionHeader(context, '记忆库'),
              _buildMemoryBlock(context, ref, selected),
              ListTile(
                dense: true,
                leading: const Icon(Icons.open_in_new, size: 18),
                title: const Text('管理记忆库', style: TextStyle(fontSize: 13)),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MemoriesPage()),
                ),
              ),
              if (selected.temperature != null ||
                  selected.maxTokens != null ||
                  selected.topP != null ||
                  selected.frequencyPenalty != null ||
                  selected.presencePenalty != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '该会话已覆盖部分全局默认参数',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
            ],
            if (selected != null) ...[
              const Divider(),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                        side: BorderSide(color: theme.colorScheme.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      icon: const Icon(Icons.tune),
                      label: const Text('编辑会话参数'),
                      onPressed: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) =>
                                ConversationParamPage(conversation: selected),
                          ),
                        );
                        if (changed == true) {
                          final updated = await ref
                              .read(appDatabaseProvider)
                              .conversationRepository
                              .getById(selected.id!);
                          if (updated != null) {
                            ref
                                .read(selectedConversationProvider.notifier)
                                .state = updated;
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// v1.2.20：切换当前会话使用的模型 —— 与移动端顶栏「更换模型」一致：
  /// 写回会话 modelId 并持久化到 DB，随后刷新选中会话与会话列表。
  Future<void> _switchModel(
      WidgetRef ref, String model, BuildContext context) async {
    final conv = ref.read(selectedConversationProvider);
    if (conv == null) {
      showToast(context, '请先发送消息创建会话，再切换模型');
      return;
    }
    if (conv.modelId == model) return;
    final updated = conv.copyWith(modelId: model);
    ref.read(selectedConversationProvider.notifier).state = updated;
    // 先提示再异步落库，避免 async gap 中误用 BuildContext。
    showToast(context, '已切换到模型：$model');
    await ref.read(conversationsProvider.notifier).update(updated);
  }

  /// 功能三：当前会话记忆区块（置顶优先 + 最近，最多展示 5 条）。
  Widget _buildMemoryBlock(BuildContext context, WidgetRef ref, Conversation selected) {
    final theme = Theme.of(context);
    if (selected.id == null) return const SizedBox.shrink();
    final memories = ref.watch(conversationMemoriesProvider(selected.id!)).maybeWhen(
          data: (list) => list,
          orElse: () => const [],
        );
    if (memories.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Text(
          '暂无记忆\n在消息长按菜单「保存到记忆库」添加',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in memories.take(5))
          ListTile(
            dense: true,
            leading: Icon(
              item.pinned ? Icons.push_pin : Icons.bookmark_outline,
              size: 18,
              color: item.pinned ? theme.colorScheme.primary : null,
            ),
            title: Text(
              item.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              item.kindLabel,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.outline),
            ),
          ),
        if (memories.length > 5)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              '还有 ${memories.length - 5} 条记忆，前往「管理记忆库」查看',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline,
              size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          const Text(
            '暂无选中会话\n此面板展示会话详情、模型与服务商参数',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  /// 当前 API 配置：会话绑定 > 首个启用 > 首个（与聊天页逻辑一致）。
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

  /// 当前模型：会话绑定 > 配置第一个模型（与聊天页逻辑一致）。
  String _resolveModel(ApiConfig? config, Conversation? conv) =>
      resolveModel(config, conv);

  /// 简单时间展示：今天 HH:mm；今年 MM-dd；更早 yyyy-MM-dd。
  String _formatTime(int ms) => formatTime(ms);
}
