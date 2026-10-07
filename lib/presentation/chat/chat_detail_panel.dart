import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/api_configs_provider.dart';
import '../../application/providers/database_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../domain/models/api_config.dart';
import '../../domain/models/conversation.dart';
import 'conversation_param_page.dart';

/// 宽屏三栏右侧辅助面板（平板端布局）。
///
/// 展示当前会话与所用服务商/模型/参数信息，并提供「设置」入口。
/// 不参与任何数据变更，仅做只读展示；数据解析逻辑与聊天页保持一致
/// （API：会话绑定 > 首个启用 > 首个；模型：会话绑定 > 配置第一个）。
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
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (selected == null)
            _buildEmpty(context)
          else ...[
            _sectionHeader(context, '会话'),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(
                selected.title,
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
              for (final m in api.modelIds)
                ListTile(
                  dense: true,
                  leading: Icon(
                    m == model ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: m == model ? AppTheme.brandGreen : null,
                  ),
                  title: Text(
                    m,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
