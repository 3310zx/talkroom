import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers/active_tasks_provider.dart';
import '../../application/providers/api_configs_provider.dart';
import '../../application/providers/database_provider.dart';
import '../../application/providers/local_server_provider.dart';
import '../../application/providers/prompt_templates_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../core/constants.dart';
import '../../core/param_presets.dart';
import '../../core/theme.dart';
import '../../data/preset_providers.dart';
import '../../domain/models/active_task.dart';
import '../../domain/models/active_task_schedule.dart';
import '../../domain/models/api_config.dart';
import '../../domain/models/message.dart';
import '../../domain/models/prompt_template.dart';
import '../../services/update_service.dart';
import '../about/about_page.dart';
import '../active_tasks/active_task_edit_page.dart';
import '../active_tasks/active_task_log_page.dart';
import '../api_config/api_config_detail_page.dart';
import 'backup_section.dart';

/// Talkroom macOS 桌面端设置页（左侧分类导航 + 右侧详情面板）。
///
/// 参照 macOS System Settings 的信息架构思路（不照搬）：
/// 左侧固定 9 个分类导航（外观 / API 服务 / 默认参数 / System Prompt /
/// 主动消息 / 本地服务 / 性能 / 数据备份 / 关于），右侧直接展示当前分类的
/// 具体设置项，不再使用「点击 → 进入子页」式长列表。
///
/// 仅用于 macOS；iPad / iPhone 继续使用 [SettingsPage] 原有移动端布局。
class MacosSettingsPage extends ConsumerStatefulWidget {
  const MacosSettingsPage({super.key});

  @override
  ConsumerState<MacosSettingsPage> createState() => _MacosSettingsPageState();
}

/// 设置分类（顺序即左侧导航顺序）。
enum _Section {
  appearance('外观', Icons.brightness_6_outlined),
  api('API 服务', Icons.dns_outlined),
  defaultParams('默认参数', Icons.tune),
  systemPrompt('System Prompt', Icons.person_outline),
  activeTasks('主动消息', Icons.notifications_active_outlined),
  localServer('本地服务', Icons.lan_outlined),
  performance('性能', Icons.speed_outlined),
  backup('数据备份', Icons.backup_outlined),
  about('关于', Icons.info_outline);

  const _Section(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _MacosSettingsPageState extends ConsumerState<MacosSettingsPage> {
  _Section _selected = _Section.appearance;
  String _currentVersion = '…';

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final v = await UpdateService.currentVersion();
      if (mounted) setState(() => _currentVersion = v);
    } catch (_) {
      // 版本读取失败时保持占位符，不阻塞设置页
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        // 左侧固定分类导航
        Container(
          width: 208,
          color: colorScheme.surfaceContainerLow,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    '设置',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    children: [
                      for (final section in _Section.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: _navItem(context, section),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // 右侧详情面板
        Expanded(child: _buildPanel(context)),
      ],
    );
  }

  Widget _navItem(BuildContext context, _Section section) {
    final selected = _selected == section;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.secondaryContainer.withValues(alpha: 0.55)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => setState(() => _selected = section),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Icon(
                section.icon,
                size: 19,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanel(BuildContext context) {
    return switch (_selected) {
      _Section.appearance => const _AppearancePanel(),
      _Section.api => const _ApiPanel(),
      _Section.defaultParams => const _DefaultParamsPanel(),
      _Section.systemPrompt => const _SystemPromptPanel(),
      _Section.activeTasks => const _ActiveTasksPanel(),
      _Section.localServer => const _LocalServerPanel(),
      _Section.performance => const _PerformancePanel(),
      _Section.backup => const _BackupPanel(),
      _Section.about => _AboutPanel(version: _currentVersion),
    };
  }
}

/// 面板通用外壳：标题 + 滚动内容。
class _PanelScaffold extends StatelessWidget {
  const _PanelScaffold({
    required this.title,
    required this.child,
    this.actions = const [],
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 22, 24, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              ...actions,
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// 面板内分组标题。
class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// 设置行：图标 + 标题 + 副标题 + trailing 控件。
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 外观 ─────────────────────────────────────────────────────────

class _AppearancePanel extends ConsumerWidget {
  const _AppearancePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final themeMode = AppThemeMode.fromValue(
      settings[AppConstants.settingThemeMode],
    );
    final seedMode = AppSeedMode.fromValue(
      settings[AppConstants.settingThemeSeedMode],
    );
    final startupLast =
        settings[AppConstants.settingStartupBehavior] ==
            AppConstants.startupBehaviorLast;
    final notifier = ref.read(settingsProvider.notifier);

    return _PanelScaffold(
      title: '外观',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupTitle('主题模式'),
          _SettingRow(
            icon: Icons.brightness_6_outlined,
            title: '跟随系统 / 浅色 / 深色',
            subtitle: '当前：${themeMode.label}',
            trailing: SegmentedButton<AppThemeMode>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: [
                for (final mode in AppThemeMode.values)
                  ButtonSegment<AppThemeMode>(
                    value: mode,
                    label: Text(mode.label),
                  ),
              ],
              selected: {themeMode},
              onSelectionChanged: (selection) {
                final value = selection.first;
                if (value == themeMode) return;
                notifier.set(AppConstants.settingThemeMode, value.value);
              },
            ),
          ),
          const SizedBox(height: 10),
          _GroupTitle('主题色'),
          _AppearanceSeedRow(
            seedMode: seedMode,
            settings: settings,
          ),
          const SizedBox(height: 10),
          _GroupTitle('启动行为'),
          _SettingRow(
            icon: Icons.restart_alt,
            title: '进入应用时的行为',
            subtitle: startupLast ? '回到退出时的对话' : '创建新对话',
            trailing: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  label: Text('创建新对话'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  label: Text('回到退出时的对话'),
                ),
              ],
              selected: {startupLast},
              onSelectionChanged: (selection) {
                final v = selection.first;
                notifier.set(
                  AppConstants.settingStartupBehavior,
                  v
                      ? AppConstants.startupBehaviorLast
                      : AppConstants.startupBehaviorNew,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceSeedRow extends ConsumerWidget {
  const _AppearanceSeedRow({
    required this.seedMode,
    required this.settings,
  });

  final AppSeedMode seedMode;
  final Map<String, String?> settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final customHex = settings[AppConstants.settingThemeCustomSeed] ?? '';
    final subtitle = switch (seedMode) {
      AppSeedMode.custom =>
        '自定义 ${customHex.isEmpty ? '（未设置，默认微信绿）' : customHex}',
      AppSeedMode.monet => '莫奈 · 跟随系统壁纸动态取色（Android 12+）',
      AppSeedMode.preset => '默认（微信绿）',
    };
    final swatchColor =
        seedMode == AppSeedMode.custom
            ? (AppTheme.parseHexColor(customHex) ?? AppTheme.brandGreen)
            : AppTheme.brandGreen;

    return _SettingRow(
      icon: Icons.palette_outlined,
      title: '主色取色源',
      subtitle: subtitle,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: swatchColor,
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.outlineVariant),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: () => _editSeed(ref, context),
            child: const Text('更改…'),
          ),
        ],
      ),
    );
  }

  Future<void> _editSeed(WidgetRef ref, BuildContext context) async {
    final notifier = ref.read(settingsProvider.notifier);
    var mode = seedMode;
    var hex =
        settings[AppConstants.settingThemeCustomSeed] ?? '#07C160';
    var hexValid = AppTheme.parseHexColor(hex) != null;
    final hexController = TextEditingController(text: hex);

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final previewSeed =
              mode == AppSeedMode.custom
                  ? (AppTheme.parseHexColor(hex) ?? AppTheme.brandGreen)
                  : AppTheme.brandGreen;
          return AlertDialog(
            title: const Text('主题色'),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '选择取色来源；自定义模式下可从预设色板取色或直接输入 HEX。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(dialogContext).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 12),
                    RadioGroup<AppSeedMode>(
                      groupValue: mode,
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          mode = value;
                          if (value == AppSeedMode.custom && !hexValid) {
                            hex = '#07C160';
                            hexController.text = hex;
                            hexValid = true;
                          }
                        });
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final m in AppSeedMode.values)
                            RadioListTile<AppSeedMode>(
                              value: m,
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(m.label),
                              subtitle: m == AppSeedMode.monet
                                  ? const Text('跟随系统壁纸动态取色，需 Android 12+')
                                  : (m == AppSeedMode.custom
                                      ? const Text('预设色板或 HEX 输入自定义主色')
                                      : null),
                            ),
                        ],
                      ),
                    ),
                    if (mode == AppSeedMode.custom) ...[
                      const SizedBox(height: 6),
                      Text(
                        '预设色板',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(dialogContext).colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final c in AppTheme.presetPalette)
                            GestureDetector(
                              onTap: () => setDialogState(() {
                                hex =
                                    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
                                hexController.text = hex;
                                hexValid = true;
                              }),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: c,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.parseHexColor(hex) == c
                                        ? Theme.of(dialogContext)
                                            .colorScheme
                                            .onSurface
                                        : Theme.of(dialogContext)
                                            .colorScheme
                                            .outlineVariant,
                                    width: AppTheme.parseHexColor(hex) == c
                                        ? 3
                                        : 1,
                                  ),
                                ),
                                child: AppTheme.parseHexColor(hex) == c
                                    ? Icon(
                                        Icons.check,
                                        size: 14,
                                        color: c.computeLuminance() > 0.5
                                            ? Colors.black87
                                            : Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: hexController,
                        decoration: InputDecoration(
                          labelText: 'HEX 色值',
                          hintText: '#07C160',
                          errorText: hex.isEmpty || hexValid
                              ? null
                              : '无效 HEX 色值',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setDialogState(() {
                          hex = v;
                          hexValid = AppTheme.parseHexColor(v) != null;
                        }),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.palette_outlined,
                            size: 16,
                            color: Color.alphaBlend(
                              Colors.white.withValues(alpha: 0.15),
                              previewSeed,
                            )),
                        const SizedBox(width: 6),
                        Text(
                          '预览：#'
                          '${(previewSeed.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (mode == AppSeedMode.custom && !hexValid) return;
                  Navigator.of(dialogContext).pop(true);
                },
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) return;
    await notifier.set(AppConstants.settingThemeSeedMode, mode.value);
    if (mode == AppSeedMode.custom) {
      final parsed = AppTheme.parseHexColor(hex);
      if (parsed != null) {
        await notifier.set(
          AppConstants.settingThemeCustomSeed,
          '#${(parsed.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        );
      }
    }
  }
}

// ── API 服务 ─────────────────────────────────────────────────────

class _ApiPanel extends ConsumerWidget {
  const _ApiPanel();

  static Color _colorFor(String name) {
    const palette = [
      Color(0xFFE67E22),
      Color(0xFF4285F4),
      Color(0xFF8E44AD),
      Color(0xFF07C160),
      Color(0xFFE74C3C),
      Color(0xFF16A085),
      Color(0xFF34495E),
      Color(0xFFD35400),
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
    return _PanelScaffold(
      title: 'API 服务',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => _showAddSheet(context, ref),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加服务商'),
        ),
      ],
      child: apiConfigs.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.dns_outlined,
                      size: 48, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('尚未添加服务商',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '点击右上角「添加服务商」，配置 OpenAI 兼容接口后即可对话',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GroupTitle(
                    '当前服务商（${apiConfigs.length} 个 · '
                    '${apiConfigs.where((c) => c.enabled).length} 在线）'),
                for (final config in apiConfigs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _providerTile(context, ref, config),
                  ),
              ],
            ),
    );
  }

  Widget _providerTile(
    BuildContext context,
    WidgetRef ref,
    ApiConfig config,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetail(context, config),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _colorFor(config.name),
                child: Text(
                  _initialFor(config.name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            config.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (config.favorite) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.star,
                              size: 14, color: Colors.amber.shade700),
                        ],
                        if (config.enabled) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF07C160),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      config.baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _openDetail(context, config),
                child: const Text('编辑'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(
    BuildContext context,
    ApiConfig? existing, {
    PresetProvider? preset,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ApiConfigDetailPage(
          existing: existing,
          preset: preset,
        ),
      ),
    );
  }

  /// 「添加服务商」：预设选择对话框（与移动端一致的预设能力）。
  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final existingNames =
        ref.read(apiConfigsProvider).map((c) => c.name).toSet();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('选择服务商预设'),
        content: SizedBox(
          width: 400,
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
                        fontSize: 13,
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
                            color: Theme.of(dialogContext)
                                .colorScheme
                                .primary,
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(dialogContext).pop();
                    final existing = ref
                        .read(apiConfigsProvider)
                        .where((c) => c.name == preset.name)
                        .firstOrNull;
                    _openDetail(
                      context,
                      existing,
                      preset: existing == null ? preset : null,
                    );
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('手动配置'),
                subtitle: const Text('自定义名称 / 接口地址 / 模型列表'),
                onTap: () {
                  Navigator.of(dialogContext).pop();
                  _openDetail(context, null);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}

// ── 默认参数 ─────────────────────────────────────────────────────

class _DefaultParamsPanel extends ConsumerStatefulWidget {
  const _DefaultParamsPanel();

  @override
  ConsumerState<_DefaultParamsPanel> createState() =>
      _DefaultParamsPanelState();
}

class _DefaultParamsPanelState extends ConsumerState<_DefaultParamsPanel> {
  late final TextEditingController _temperatureCtrl;
  late final TextEditingController _maxTokensCtrl;
  late final TextEditingController _topPCtrl;
  late final TextEditingController _frequencyCtrl;
  late final TextEditingController _presenceCtrl;
  String _selectedPreset = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _temperatureCtrl = TextEditingController(
        text: settings[AppConstants.settingTemperature] ??
            '${AppConstants.defaultTemperature}');
    _maxTokensCtrl = TextEditingController(
        text: settings[AppConstants.settingMaxTokens] ??
            '${AppConstants.defaultMaxTokens}');
    _topPCtrl = TextEditingController(
        text: settings[AppConstants.settingTopP] ??
            '${AppConstants.defaultTopP}');
    _frequencyCtrl = TextEditingController(
        text: settings[AppConstants.settingFrequencyPenalty] ??
            '${AppConstants.defaultFrequencyPenalty}');
    _presenceCtrl = TextEditingController(
        text: settings[AppConstants.settingPresencePenalty] ??
            '${AppConstants.defaultPresencePenalty}');
  }

  @override
  void dispose() {
    _temperatureCtrl.dispose();
    _maxTokensCtrl.dispose();
    _topPCtrl.dispose();
    _frequencyCtrl.dispose();
    _presenceCtrl.dispose();
    super.dispose();
  }

  void _applyPreset(String name) {
    final preset =
        kParamPresets.firstWhere((p) => p.name == name);
    setState(() {
      _selectedPreset = name;
      _temperatureCtrl.text = preset.temperature.toString();
      _maxTokensCtrl.text = preset.maxTokens.toString();
      _topPCtrl.text = preset.topP.toString();
      _frequencyCtrl.text = preset.frequencyPenalty.toString();
      _presenceCtrl.text = preset.presencePenalty.toString();
    });
  }

  Future<void> _save() async {
    final temp = double.tryParse(_temperatureCtrl.text.trim());
    final maxTok = int.tryParse(_maxTokensCtrl.text.trim());
    final topP = double.tryParse(_topPCtrl.text.trim());
    final freq = double.tryParse(_frequencyCtrl.text.trim());
    final presence = double.tryParse(_presenceCtrl.text.trim());
    if (temp == null || temp < 0 || temp > 2) {
      _toast('temperature 需为 0.0 ~ 2.0 的数字');
      return;
    }
    if (maxTok == null || maxTok < 1) {
      _toast('max_tokens 需为不小于 1 的整数');
      return;
    }
    if (topP == null || topP < 0 || topP > 1) {
      _toast('top_p 需为 0.0 ~ 1.0 的数字');
      return;
    }
    if (freq == null || freq < -2 || freq > 2) {
      _toast('frequency_penalty 需为 -2.0 ~ 2.0 的数字');
      return;
    }
    if (presence == null || presence < -2 || presence > 2) {
      _toast('presence_penalty 需为 -2.0 ~ 2.0 的数字');
      return;
    }
    setState(() => _saving = true);
    try {
      final notifier = ref.read(settingsProvider.notifier);
      await notifier.set(
          AppConstants.settingTemperature, _temperatureCtrl.text.trim());
      await notifier.set(
          AppConstants.settingMaxTokens, _maxTokensCtrl.text.trim());
      await notifier.set(AppConstants.settingTopP, _topPCtrl.text.trim());
      await notifier.set(
          AppConstants.settingFrequencyPenalty, _frequencyCtrl.text.trim());
      await notifier.set(
          AppConstants.settingPresencePenalty, _presenceCtrl.text.trim());
      if (!mounted) return;
      _toast('默认参数已保存');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _PanelScaffold(
      title: '默认参数',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupTitle('参数预设（一键填充）'),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in kParamPresets)
                ChoiceChip(
                  label: Text(preset.name),
                  selected: _selectedPreset == preset.name,
                  onSelected: (_) => _applyPreset(preset.name),
                ),
            ],
          ),
          if (_selectedPreset.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kParamPresets
                    .firstWhere((p) => p.name == _selectedPreset)
                    .description,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.primary,
                ),
              ),
            ),
          _GroupTitle('模型推理参数'),
          _paramField(_temperatureCtrl, 'temperature（0.0 ~ 2.0，默认 0.7）',
              const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 10),
          _paramField(
              _maxTokensCtrl, 'max_tokens（1 ~ 上限，默认 2048）', TextInputType.number),
          const SizedBox(height: 10),
          _paramField(_topPCtrl, 'top_p（0.0 ~ 1.0，默认 1.0）',
              const TextInputType.numberWithOptions(decimal: true)),
          const SizedBox(height: 10),
          _paramField(
              _frequencyCtrl,
              'frequency_penalty（-2.0 ~ 2.0，默认 0.0）',
              const TextInputType.numberWithOptions(
                  decimal: true, signed: true)),
          const SizedBox(height: 10),
          _paramField(
              _presenceCtrl,
              'presence_penalty（-2.0 ~ 2.0，默认 0.0）',
              const TextInputType.numberWithOptions(
                  decimal: true, signed: true)),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? '保存中…' : '保存默认参数'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paramField(
    TextEditingController controller,
    String label,
    TextInputType keyboardType,
  ) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}

// ── System Prompt ────────────────────────────────────────────────

class _SystemPromptPanel extends ConsumerStatefulWidget {
  const _SystemPromptPanel();

  @override
  ConsumerState<_SystemPromptPanel> createState() =>
      _SystemPromptPanelState();
}

class _SystemPromptPanelState extends ConsumerState<_SystemPromptPanel> {
  late final TextEditingController _promptCtrl;
  bool _savingPrompt = false;

  @override
  void initState() {
    super.initState();
    _promptCtrl = TextEditingController(
      text: ref.read(settingsProvider)[AppConstants.settingSystemPrompt] ?? '',
    );
    Future.microtask(
        () => ref.read(promptTemplatesProvider.notifier).load());
  }

  @override
  void dispose() {
    _promptCtrl.dispose();
    super.dispose();
  }

  Future<void> _savePrompt() async {
    setState(() => _savingPrompt = true);
    try {
      await ref
          .read(settingsProvider.notifier)
          .set(AppConstants.settingSystemPrompt, _promptCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('全局 System Prompt 已保存')));
    } finally {
      if (mounted) setState(() => _savingPrompt = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(promptTemplatesProvider);
    final settings = ref.watch(settingsProvider);
    final globalPrompt = settings[AppConstants.settingSystemPrompt] ?? '';
    final globalTemplateId = templates
        .where((t) => t.content == globalPrompt && globalPrompt.isNotEmpty)
        .map((t) => t.id)
        .firstOrNull;

    return _PanelScaffold(
      title: 'System Prompt',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupTitle('全局 System Prompt（所有会话默认）'),
          TextField(
            controller: _promptCtrl,
            maxLines: 8,
            minLines: 5,
            decoration: const InputDecoration(
              hintText: '可选：设置全局系统提示词，如「你是一个乐于助人的助手」',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _savingPrompt ? null : _savePrompt,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(_savingPrompt ? '保存中…' : '保存全局提示词'),
            ),
          ),
          const SizedBox(height: 6),
          _GroupTitle('模板（点击模板设为全局默认）'),
          Row(
            children: [
              const Spacer(),
              TextButton.icon(
                onPressed: () => _showImportDialog(context),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('导入'),
              ),
              TextButton.icon(
                onPressed: () => _showTemplateEditor(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('新建'),
              ),
            ],
          ),
          if (templates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '还没有模板\n点击「新建」创建，或「导入」已有模板',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
              ),
            )
          else
            for (final template in templates)
              _templateTile(
                context,
                ref,
                template,
                isGlobal: template.id != null &&
                    template.id == globalTemplateId,
              ),
        ],
      ),
    );
  }

  Widget _templateTile(
    BuildContext context,
    WidgetRef ref,
    PromptTemplate template, {
    required bool isGlobal,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _applyAsGlobal(ref, template),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              template.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (template.builtin) ...[
                            const SizedBox(width: 6),
                            _tag(context, '内置',
                                colorScheme.secondaryContainer,
                                colorScheme.onSecondaryContainer),
                          ],
                          if (isGlobal) ...[
                            const SizedBox(width: 6),
                            _tag(context, '全局默认',
                                colorScheme.primaryContainer,
                                colorScheme.onPrimaryContainer),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        template.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '模板操作',
                  onSelected: (value) => _onMenu(
                      context, ref, template, value, isGlobal),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    const PopupMenuItem(
                        value: 'export_json', child: Text('复制 JSON')),
                    const PopupMenuItem(
                        value: 'export_text', child: Text('复制文本')),
                    if (!template.builtin)
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tag(BuildContext context, String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, color: fg),
      ),
    );
  }

  Future<void> _applyAsGlobal(WidgetRef ref, PromptTemplate template) async {
    await ref
        .read(settingsProvider.notifier)
        .set(AppConstants.settingSystemPrompt, template.content);
    if (!mounted) return;
    setState(() {
      _promptCtrl.text = template.content;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('已切换：${template.name} 作为全局默认提示词')));
  }

  Future<void> _showTemplateEditor(
    BuildContext context, [
    PromptTemplate? template,
  ]) async {
    final nameController =
        TextEditingController(text: template?.name ?? '');
    final contentController =
        TextEditingController(text: template?.content ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(template == null ? '新建模板' : '编辑模板'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(
                  labelText: '模板名称',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentController,
                maxLines: 8,
                minLines: 5,
                decoration: const InputDecoration(
                  labelText: '模板内容（System Prompt）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              final content = contentController.text.trim();
              if (name.isEmpty || content.isEmpty) return;
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final name = nameController.text.trim();
    final content = contentController.text.trim();
    final notifier = ref.read(promptTemplatesProvider.notifier);
    if (template == null) {
      await notifier.create(name: name, content: content);
    } else {
      await notifier.update(template.copyWith(name: name, content: content));
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('模板已保存')));
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final mode = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('导入模板'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('json'),
            child: const ListTile(
              leading: Icon(Icons.data_object),
              title: Text('导入 JSON'),
              subtitle: Text('格式：{"name":"模板名","content":"模板内容"}'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('text'),
            child: const ListTile(
              leading: Icon(Icons.notes),
              title: Text('导入文本'),
              subtitle: Text('以文本第一行为模板名，其余为模板内容'),
            ),
          ),
        ],
      ),
    );
    if (!context.mounted || mode == null) return;

    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(mode == 'json' ? '粘贴 JSON' : '粘贴模板文本'),
        content: TextField(
          controller: controller,
          maxLines: 10,
          minLines: 6,
          autofocus: true,
          decoration: InputDecoration(
            hintText: mode == 'json'
                ? '{"name":"我的模板","content":"你是…"}'
                : '第一行：模板名称\n其余行：模板内容',
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (!context.mounted || raw == null || raw.trim().isEmpty) return;

    PromptTemplate? parsed;
    if (mode == 'json') {
      parsed = PromptTemplate.fromJsonText(raw.trim());
      if (parsed == null) {
        _toast(context, 'JSON 解析失败，请检查格式');
        return;
      }
    } else {
      final lines = raw.trim().split('\n');
      final name = lines.first.trim();
      final content = lines.skip(1).join('\n').trim();
      if (name.isEmpty || content.isEmpty) {
        _toast(context, '文本格式不正确：第一行应为模板名称');
        return;
      }
      parsed = PromptTemplate(
        name: name,
        content: content,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    await ref
        .read(promptTemplatesProvider.notifier)
        .create(name: parsed.name, content: parsed.content);
    if (!context.mounted) return;
    _toast(context, '已导入模板「${parsed.name}」');
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    PromptTemplate template,
    String value,
    bool isGlobal,
  ) async {
    switch (value) {
      case 'edit':
        await _showTemplateEditor(context, template);
      case 'export_json':
        await Clipboard.setData(ClipboardData(text: template.toJsonText()));
        if (!context.mounted) return;
        _toast(context, '模板 JSON 已复制到剪贴板');
      case 'export_text':
        await Clipboard.setData(ClipboardData(text: template.toText()));
        if (!context.mounted) return;
        _toast(context, '模板文本已复制到剪贴板');
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除模板'),
            content: Text('确定删除模板「${template.name}」吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      Theme.of(dialogContext).colorScheme.error,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('删除'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await ref.read(promptTemplatesProvider.notifier).delete(template);
        if (!context.mounted) return;
        if (isGlobal) {
          _toast(context, '已删除模板（原全局默认提示词保留）');
        }
    }
  }

  void _toast(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// ── 主动消息 ─────────────────────────────────────────────────────

class _ActiveTasksPanel extends ConsumerStatefulWidget {
  const _ActiveTasksPanel();

  @override
  ConsumerState<_ActiveTasksPanel> createState() => _ActiveTasksPanelState();
}

class _ActiveTasksPanelState extends ConsumerState<_ActiveTasksPanel> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(activeTasksProvider.notifier).load());
  }

  Future<void> _openEdit({ActiveTask? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ActiveTaskEditPage(existing: existing),
      ),
    );
    if (!mounted) return;
    await ref.read(activeTasksProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(activeTasksProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return _PanelScaffold(
      title: '主动消息',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => _openEdit(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('新建任务'),
        ),
      ],
      child: tasks.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 48, color: colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('尚未创建定时任务',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '点击右上角「新建任务」，让 LLM 定时向会话主动发消息',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GroupTitle('定时任务（${tasks.length}）'),
                for (final task in tasks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _taskTile(context, ref, task),
                  ),
              ],
            ),
    );
  }

  Widget _taskTile(BuildContext context, WidgetRef ref, ActiveTask task) {
    final colorScheme = Theme.of(context).colorScheme;
    final schedule = ActiveTaskSchedule.fromJson(
      task.scheduleData,
      taskType: task.taskType,
    );
    final notifier = ref.read(activeTasksProvider.notifier);
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Switch(
              value: task.enabled,
              onChanged: (v) => notifier.setEnabled(task, v),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.taskName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    schedule.describe(),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '下次执行：${_formatTime(task.nextRunAt)} · 最近结果：${_statusText(task)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_deliveryText(task)}'
                    '${task.quietStart == null ? '' : ' · 静默时段：${task.quietStart} ~ ${task.quietEnd}'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '执行日志',
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ActiveTaskLogPage(task: task),
                ),
              ),
            ),
            IconButton(
              tooltip: '编辑',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _openEdit(existing: task),
            ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _confirmDelete(context, ref, task),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ActiveTask task,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除定时任务'),
        content: Text('确定删除「${task.taskName}」吗？删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && task.id != null) {
      await ref.read(activeTasksProvider.notifier).remove(task.id!);
    }
  }

  String _deliveryText(ActiveTask task) => switch (task.delivery) {
        'chat' => '投递：仅聊天',
        'notification' => '投递：仅通知',
        _ => '投递：聊天 + 通知',
      };

  String _statusText(ActiveTask task) {
    if (task.lastStatus == null) return '尚未执行';
    final at =
        task.lastRunAt == null ? '' : '（${_formatTime(task.lastRunAt)}）';
    return switch (task.lastStatus!) {
      'ok' => '成功$at',
      'failed' => '失败$at',
      'skipped' => '跳过$at',
      'missed' => '错过$at',
      _ => '${task.lastStatus}$at',
    };
  }
}

String _formatTime(int? millis) {
  if (millis == null) return '—';
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ── 本地服务 ─────────────────────────────────────────────────────

class _LocalServerPanel extends ConsumerStatefulWidget {
  const _LocalServerPanel();

  @override
  ConsumerState<_LocalServerPanel> createState() => _LocalServerPanelState();
}

class _LocalServerPanelState extends ConsumerState<_LocalServerPanel> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(localServerStatusProvider);
    final autoStart =
        ref.watch(settingsProvider)[AppConstants.settingServerAutoStart] == '1';
    final colorScheme = Theme.of(context).colorScheme;

    return _PanelScaffold(
      title: '本地服务',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 运行状态
          Material(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    status == null ? Icons.dns_outlined : Icons.dns,
                    size: 32,
                    color: status == null
                        ? colorScheme.onSurfaceVariant
                        : const Color(0xFF07C160),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status == null ? '本地服务器未启动' : '运行中 · 端口 ${status.port}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          status == null
                              ? '电脑端作为权威源集中存储聊天记录，手机可同一局域网连接'
                              : '启动时间：${_formatDateTime(status.startedAt)}'
                                    '\n已配对设备：${status.pairedDevices} 台'
                                    '${status.pairLocked ? '\n⚠️ 配对码已锁定（错误次数过多）' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (status == null)
                    FilledButton.icon(
                      onPressed: _starting ? null : _startServer,
                      icon: _starting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow, size: 18),
                      label: Text(_starting ? '启动中…' : '启动服务器'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: _stopServer,
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('停止服务器'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Material(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            child: SwitchListTile(
              secondary: const Icon(Icons.power_settings_new),
              title: const Text('应用启动时自动拉起服务器'),
              subtitle: const Text('电脑端有效；首次开启会引导配置'),
              value: autoStart,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              onChanged: (v) async {
                await ref.read(settingsProvider.notifier).set(
                    AppConstants.settingServerAutoStart, v ? '1' : '0');
                if (v) await _startServer();
              },
            ),
          ),
          const SizedBox(height: 6),
          _GroupTitle('配对信息'),
          Material(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.password, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        status?.pairCode == null ||
                                status!.pairCode!.isEmpty
                            ? '未生成配对码'
                            : '配对码：${status.pairCode!.split('').join(' ')}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    status == null
                        ? '启动服务器后生成一次性配对码，供手机端连接'
                        : (status.pairLocked
                            ? '已锁定，剩余 ${(status.pairRemainingLockMs / 60000).ceil()} 分钟解锁'
                            : '配对码一次性有效，配对成功后自动失效'),
                    style: TextStyle(
                      fontSize: 12,
                      color: status != null && status.pairLocked
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (status?.serverDeviceId != null &&
                      status!.serverDeviceId!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '服务器设备 ID：${status.serverDeviceId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed:
                            status == null ? null : _regeneratePairCode,
                        child: const Text('重新生成配对码'),
                      ),
                      if (status != null)
                        TextButton(
                          onPressed: _copyPairCode,
                          child: const Text('复制配对码'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          _GroupTitle('局域网地址'),
          _lanIpsCard(status?.lanIps ?? const <String>[]),
          const SizedBox(height: 6),
          _GroupTitle('已配对设备'),
          const _PairedDevicesCard(),
        ],
      ),
    );
  }

  Widget _lanIpsCard(List<String> ips) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = ref.read(localServerStatusProvider);
    if (ips.isEmpty) {
      return Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.wifi_off),
              SizedBox(width: 10),
              Expanded(
                child: Text('未检测到局域网 IP\n请确认电脑已连接 Wi-Fi / 以太网'),
              ),
            ],
          ),
        ),
      );
    }
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          for (final ip in ips)
            ListTile(
              dense: true,
              leading: const Icon(Icons.lan_outlined, size: 20),
              title: Text(ip),
              subtitle: Text('http://$ip:${status?.port ?? '--'}'),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: '复制地址',
                onPressed: () => _copyText('http://$ip:${status?.port ?? ''}'),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '--';
    final l = dt.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }

  Future<void> _startServer() async {
    final service = ref.read(localServerServiceProvider);
    if (service.isRunning) {
      await _refreshStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地服务器已在运行')),
      );
      return;
    }
    setState(() => _starting = true);
    try {
      final settings = ref.read(settingsProvider);
      final lastPort =
          int.tryParse(settings[AppConstants.settingServerLastPort] ?? '') ??
              AppConstants.defaultServerPort;
      final port = await service.probePort(startPort: lastPort);
      await service.start(port: port);
      final ips = await service.getLanIpv4Addresses();
      final info = await service.pairInfo();
      await ref
          .read(settingsProvider.notifier)
          .set(AppConstants.settingServerLastPort, '$port');
      ref.read(localServerStatusProvider.notifier).state = LocalServerState(
        port: port,
        lanIps: ips,
        startedAt: DateTime.now(),
        pairCode: info['pair_code_set'] == true
            ? await service.getPairCode()
            : await service.ensurePairCode(),
        serverDeviceId: info['server_device_id'] as String?,
        pairedDevices: info['paired_devices'] as int? ?? 0,
        pairLocked: info['pair_locked'] == true,
        pairRemainingLockMs: info['pair_remaining_lock_ms'] as int? ?? 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '服务器已启动：${ips.isEmpty ? '0.0.0.0' : ips.first}:$port'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopServer() async {
    await ref.read(localServerServiceProvider).stop();
    ref.read(localServerStatusProvider.notifier).state = null;
  }

  Future<void> _regeneratePairCode() async {
    final service = ref.read(localServerServiceProvider);
    final code = await service.ensurePairCode();
    final info = await service.pairInfo();
    ref.read(localServerStatusProvider.notifier).state =
        ref.read(localServerStatusProvider.notifier).state?.copyWith(
              pairCode: code,
              pairLocked: false,
              pairRemainingLockMs: 0,
              pairedDevices: info['paired_devices'] as int? ?? 0,
            );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('新配对码已生成：$code')));
  }

  Future<void> _copyPairCode() async {
    final status = ref.read(localServerStatusProvider.notifier).state;
    final code = status?.pairCode;
    if (code == null || code.isEmpty) return;
    await _copyText(code);
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制')));
  }

  Future<void> _refreshStatus() async {
    final service = ref.read(localServerServiceProvider);
    final status = ref.read(localServerStatusProvider.notifier).state;
    if (status == null) return;
    final info = await service.pairInfo();
    ref.read(localServerStatusProvider.notifier).state = status.copyWith(
      pairCode: await service.getPairCode(),
      serverDeviceId: info['server_device_id'] as String?,
      pairedDevices: info['paired_devices'] as int? ?? 0,
      pairLocked: info['pair_locked'] == true,
      pairRemainingLockMs: info['pair_remaining_lock_ms'] as int? ?? 0,
    );
    ref.invalidate(localServerDevicesProvider);
  }
}

class _PairedDevicesCard extends ConsumerWidget {
  const _PairedDevicesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(localServerDevicesProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return devices.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text('加载失败：$e'),
        ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Material(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            child: const ListTile(
              leading: Icon(Icons.devices_other),
              title: Text('暂无已配对设备'),
              subtitle: Text('手机端连接配置页输入配对码即可加入'),
            ),
          );
        }
        return Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: [
              for (final device in list)
                ListTile(
                  dense: true,
                  leading: Icon(
                    device.deviceType == 'server'
                        ? Icons.desktop_windows
                        : Icons.smartphone,
                    size: 20,
                  ),
                  title: Text(device.deviceName),
                  subtitle: Text(
                    '${device.deviceType} · 最后活跃 '
                    '${_fmtLastSeen(device.lastSeenAt)}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.person_remove_outlined, size: 20),
                    tooltip: '移除设备',
                    onPressed: () => _removeDevice(ref, device.deviceId),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _fmtLastSeen(int ms) {
    if (ms <= 0) return '未知';
    return DateTime.fromMillisecondsSinceEpoch(ms)
        .toLocal()
        .toString()
        .substring(0, 19);
  }

  Future<void> _removeDevice(WidgetRef ref, String deviceId) async {
    final db = ref.read(appDatabaseProvider);
    await db.deviceRepository.removeByDeviceId(deviceId);
    ref.invalidate(localServerDevicesProvider);
  }
}

// ── 性能 ─────────────────────────────────────────────────────────

class _PerformancePanel extends ConsumerStatefulWidget {
  const _PerformancePanel();

  @override
  ConsumerState<_PerformancePanel> createState() => _PerformancePanelState();
}

class _PerformancePanelState extends ConsumerState<_PerformancePanel> {
  List<CacheHitRecord> _cacheHits = const [];
  List<ChatMessage> _stats = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = ref.read(appDatabaseProvider).messageRepository;
      final records = await repo.listCacheHits();
      final stats = await repo.listPerformanceStats(limit: 30);
      if (!mounted) return;
      setState(() {
        _cacheHits = records;
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  Future<void> _clearCacheHits() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空命中缓存记录'),
        content: const Text(
            '将删除全部缓存命中记录（仅影响该记录列表，不会删除聊天消息）。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref
        .read(appDatabaseProvider)
        .messageRepository
        .clearCacheHits();
    if (!mounted) return;
    setState(() => _cacheHits = const []);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已清空命中缓存记录')));
  }

  @override
  Widget build(BuildContext context) {
    return _PanelScaffold(
      title: '性能',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
              ? Center(child: Text(_error ?? '加载失败'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GroupTitle('命中缓存'),
                    _cacheHitsCard(context),
                    const SizedBox(height: 6),
                    _GroupTitle('性能图表'),
                    _statsSummary(context),
                    const SizedBox(height: 8),
                    _chartBlock(
                      context,
                      '最近 ${_durations().length} 次请求耗时（ms）',
                      _durations(),
                      emptyHint: '暂无耗时数据（旧记录未记录耗时）',
                    ),
                    const SizedBox(height: 16),
                    _chartBlock(
                      context,
                      '最近 ${_stats.length} 次 Token 用量',
                      _tokens(),
                      emptyHint: '暂无 Token 数据',
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '说明：图表展示最近 30 条已完成的助手回复；耗时单位为毫秒，Token 为提示词 + 生成 + 缓存用量合计。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
    );
  }

  List<int> _durations() =>
      _stats.map((m) => m.durationMs).whereType<int>().toList();

  List<int> _tokens() => _stats
      .map((m) =>
          (m.promptTokens ?? 0) +
          (m.completionTokens ?? 0) +
          (m.cachedTokens ?? 0))
      .toList();

  Widget _cacheHitsCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_cacheHits.isEmpty) {
      return Material(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('暂无缓存命中记录')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        TextButton.icon(
          onPressed: _clearCacheHits,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('清空记录'),
        ),
        Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          child: Column(
            children: [
              for (final record in _cacheHits.take(30))
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 14,
                    backgroundColor: colorScheme.secondaryContainer,
                    child: Icon(
                      Icons.speed,
                      size: 16,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                  title: Text(
                    record.modelId == null || record.modelId!.isEmpty
                        ? '未知模型'
                        : record.modelId!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_fmtTime(record.createdAt)}'
                    ' · ${record.hitRate == null ? '命中率未知' : '${(record.hitRate! * 100).toStringAsFixed(1)}%'}'
                    ' · 命中 ${record.cachedTokens} tokens',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => _showDetail(record),
                ),
            ],
          ),
        ),
        if (_cacheHits.length > 30)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '仅展示最近 30 条',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  void _showDetail(CacheHitRecord record) {
    final total = (record.promptTokens ?? 0) + (record.completionTokens ?? 0);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('缓存命中详情'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('时间', _fmtTime(record.createdAt)),
            _detailRow(
                '模型',
                record.modelId == null || record.modelId!.isEmpty
                    ? '未知模型'
                    : record.modelId!),
            _detailRow('缓存命中 token', record.cachedTokens.toString()),
            _detailRow(
                'Prompt token', record.promptTokens?.toString() ?? '未知'),
            _detailRow('Completion token',
                record.completionTokens?.toString() ?? '未知'),
            _detailRow('总 token',
                record.promptTokens == null ? '未知' : total.toString()),
            _detailRow(
              '命中率',
              record.hitRate == null
                  ? '未知（无 prompt_tokens）'
                  : '${(record.hitRate! * 100).toStringAsFixed(1)}%',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(value),
        ],
      ),
    );
  }

  Widget _statsSummary(BuildContext context) {
    final durations = _durations();
    final tokens = _tokens();
    final avgDuration = durations.isEmpty
        ? null
        : durations.reduce((a, b) => a + b) / durations.length;
    final totalTokens = tokens.fold<int>(0, (sum, v) => sum + v);
    return Row(
      children: [
        Expanded(
          child: _statCard(context, '统计请求数', '${_stats.length}',
              Icons.message),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
              context, '平均耗时', avgDuration == null ? '—' : '${avgDuration.round()} ms',
              Icons.timer_outlined),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(context, '总 Token', '$totalTokens',
              Icons.data_usage),
        ),
      ],
    );
  }

  Widget _statCard(
      BuildContext context, String label, String value, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 6),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chartBlock(
    BuildContext context,
    String title,
    List<int> values, {
    required String emptyHint,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (values.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              emptyHint,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final v in values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$v',
                          style: const TextStyle(fontSize: 10),
                          maxLines: 1,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 18,
                          height: (v /
                                      (values.reduce(
                                              (a, b) => a > b ? a : b) <=
                                          0
                                      ? 1
                                      : values.reduce(
                                          (a, b) => a > b ? a : b)) *
                                  120)
                              .clamp(2.0, 120.0),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withAlpha(217),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(3)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text('·', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _fmtTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

// ── 数据备份 ─────────────────────────────────────────────────────

class _BackupPanel extends StatelessWidget {
  const _BackupPanel();

  @override
  Widget build(BuildContext context) {
    return const _PanelScaffold(
      title: '数据备份',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupTitle('备份管理'),
          _BackupEmbed(),
        ],
      ),
    );
  }
}

/// 直接复用移动端设置页的数据备份区（导出 / 导入按钮与完整业务逻辑）。
class _BackupEmbed extends ConsumerWidget {
  const _BackupEmbed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // BackupSection 自带分隔线，包一层规避多余 Divider。
    return const BackupSection();
  }
}

// ── 关于 ─────────────────────────────────────────────────────────

class _AboutPanel extends ConsumerStatefulWidget {
  const _AboutPanel({required this.version});

  final String version;

  @override
  ConsumerState<_AboutPanel> createState() => _AboutPanelState();
}

class _AboutPanelState extends ConsumerState<_AboutPanel> {
  bool _checking = false;

  static const String _repoUrl = 'https://github.com/3310zx/talkroom';
  static const String _releaseUrl = '$_repoUrl/releases/latest';

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 打不开链接时静默失败，桌面端一般由系统浏览器接管。
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final update = await UpdateService().fetchLatestRelease();
      final current = await UpdateService.currentVersion();
      if (!mounted) return;
      if (UpdateService.compareVersions(update.version, current) > 0) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('发现新版本 ${update.version}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (update.name.isNotEmpty && update.name != update.version)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        update.name,
                        style: TextStyle(
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
                  Text(update.body.isEmpty ? '暂无更新说明' : update.body),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _launch(_releaseUrl);
                },
                icon: const Icon(Icons.download),
                label: const Text('前往 Releases 页'),
              ),
            ],
          ),
        );
      } else {
        _toast('当前已是最新版本 $current');
      }
    } on UpdateCheckException catch (e) {
      if (!mounted) return;
      if (e.type == UpdateCheckErrorType.rateLimited ||
          e.type == UpdateCheckErrorType.forbidden) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('检查更新暂时失败'),
            content: Text(
                '${e.message}\n\n你也可以前往 GitHub Releases 页查看最新版本。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('稍后'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _launch(_releaseUrl);
                },
                icon: const Icon(Icons.open_in_browser),
                label: const Text('前往 Releases 页'),
              ),
            ],
          ),
        );
      } else {
        _toast(e.message.isEmpty ? '检查更新暂时失败，请稍后重试' : e.message);
      }
    } catch (_) {
      if (!mounted) return;
      _toast('检查更新暂时失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _PanelScaffold(
      title: '关于',
      actions: [
        FilledButton.tonalIcon(
          onPressed: _checking ? null : _checkForUpdate,
          icon: _checking
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt, size: 18),
          label: Text(_checking ? '检查中…' : '检查更新'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF07C160),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.chat_bubble,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppConstants.appName,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '版本 ${widget.version}',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '跨平台第三方 LLM 对话客户端\nmacOS / Android / Web',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          _GroupTitle('更新日志'),
          Material(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in AboutPage.kChangelog) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.version,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.notes,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item != AboutPage.kChangelog.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          _GroupTitle('开源信息'),
          Material(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.code, size: 20),
                  title: const Text('GitHub 仓库'),
                  subtitle: const Text('3310zx/talkroom\n基于 Flutter 开源生态构建'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launch(_repoUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.update, size: 20),
                  title: const Text('版本发布页'),
                  subtitle: const Text('查看 Releases 与安装包（APK / macOS dmg）'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _launch(_releaseUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => _launch(_releaseUrl),
            icon: const Icon(Icons.download),
            label: const Text('前往 GitHub Releases 下载'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
