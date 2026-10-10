import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/api_configs_provider.dart';
import '../../data/preset_providers.dart';
import '../../domain/models/api_config.dart';
import 'api_config_detail_page.dart';

/// API 服务商总览列表页（参考 UI 设计图一）。
///
/// 列表页仅承担「选择层」职责：
/// - 展示全部已添加的服务商（图标 + 名称 + 在线状态点 + 箭头）；
/// - 底部固定「+ 添加」入口：弹出预设服务商选择面板，选中后自动填充
///   接口地址与默认模型（仅需填写 API Key），也支持手动配置；
/// - 点击条目进入对应服务商的配置详情页。
class ApiConfigListPage extends ConsumerWidget {
  const ApiConfigListPage({super.key});

  /// 依据服务商名称生成稳定的徽标颜色。
  static Color _colorFor(String name) {
    const palette = [
      Color(0xFFE67E22), // 橙
      Color(0xFF4285F4), // 蓝
      Color(0xFF8E44AD), // 紫
      Color(0xFF07C160), // 绿
      Color(0xFFE74C3C), // 红
      Color(0xFF16A085), // 青
      Color(0xFF34495E), // 深蓝灰
      Color(0xFFD35400), // 深橙
    ];
    if (name.isEmpty) return palette[0];
    return palette[name.hashCode.abs() % palette.length];
  }

  String _initialFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiConfigs = ref.watch(apiConfigsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    // R22：收藏项置顶展示（仓储已按 favorite DESC 排序，这里再分组标头）。
    final favorites = apiConfigs.where((c) => c.favorite).toList();
    final showFavoriteHeader = favorites.isNotEmpty;
    final itemCount = apiConfigs.length + (showFavoriteHeader ? 1 : 0);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Column(
        children: [
          Expanded(
            child: apiConfigs.isEmpty
                ? _buildEmpty(context)
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: itemCount,
                    itemBuilder: (context, index) {
                      if (showFavoriteHeader && index == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Row(
                            children: [
                              Icon(Icons.star,
                                  size: 16, color: Colors.amber.shade700),
                              const SizedBox(width: 6),
                              Text(
                                '收藏',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                        );
                      }
                      final itemIndex =
                          showFavoriteHeader ? index - 1 : index;
                      final config = apiConfigs[itemIndex];
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Divider(height: 1),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _colorFor(config.name),
                              child: Text(
                                _initialFor(config.name),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(config.name),
                            subtitle: Text(
                              config.baseUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    config.favorite
                                        ? Icons.star
                                        : Icons.star_border,
                                    color: config.favorite
                                        ? Colors.amber.shade700
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  tooltip: config.favorite
                                      ? '取消收藏'
                                      : '收藏（置顶展示）',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => ref
                                      .read(apiConfigsProvider.notifier)
                                      .toggleFavorite(config),
                                ),
                                if (config.enabled) ...[
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF07C160),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Icon(
                                  Icons.chevron_right,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                            onTap: () => _openDetail(context, config),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    side: BorderSide(color: colorScheme.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('添加'),
                  onPressed: () => _showAddSheet(context, ref),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined, size: 48, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('尚未添加服务商', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '点击下方「添加」，配置 OpenAI 兼容接口后即可对话',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 打开详情页；[preset] 非空表示从预设新建（自动填充，仅需填 API Key）。
  Future<void> _openDetail(
    BuildContext context,
    ApiConfig? existing, {
    PresetProvider? preset,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiConfigDetailPage(existing: existing, preset: preset),
      ),
    );
  }

  /// 「+ 添加」：弹出预设服务商选择面板（底部弹层）。
  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final pageContext = context;
    final existingNames =
        ref.read(apiConfigsProvider).map((c) => c.name).toSet();
    showModalBottomSheet<void>(
      context: pageContext,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '选择服务商预设',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final preset in presetProviders)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(preset.brandColorArgb),
                        child: Text(
                          preset.name.isEmpty
                              ? '?'
                              : preset.name.trim().characters.first.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(preset.name),
                      subtitle: Text(
                        preset.baseUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: existingNames.contains(preset.name)
                          ? Text(
                              '已添加',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(sheetContext)
                                    .colorScheme
                                    .primary,
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        final existing = ref
                            .read(apiConfigsProvider)
                            .where((c) => c.name == preset.name)
                            .firstOrNull;
                        // 已添加则直接进入编辑；未添加则携带预设自动填充。
                        _openDetail(
                          pageContext,
                          existing,
                          preset: existing == null ? preset : null,
                        );
                      },
                    ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('手动配置'),
                    subtitle: const Text('自定义名称 / 接口地址 / 模型列表'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _openDetail(pageContext, null);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
