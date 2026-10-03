import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers/api_configs_provider.dart';
import '../../application/providers/local_server_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../application/providers/sync_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/update_service.dart';
import '../active_tasks/active_tasks_page.dart';
import '../api_config/api_config_list_page.dart';
import '../cache_hits/cache_hits_page.dart';
import '../sync/local_server_page.dart';
import '../sync/sync_setup_page.dart';

/// 设置页（三栏右栏 / 移动端设置 Tab）。
///
/// 包含：API 配置管理、本地服务器（局域网）、参数设置占位。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  /// 当前应用版本号（异步从 package_info_plus 读取，用于"检查更新"副标题展示）
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
    final apiConfigs = ref.watch(apiConfigsProvider);
    final serverStatus = ref.watch(localServerStatusProvider);
    final settings = ref.watch(settingsProvider);
    final syncStatus = ref.watch(syncStatusProvider);
    final themeMode = AppThemeMode.fromValue(
      settings[AppConstants.settingThemeMode],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _sectionHeader('外观'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('主题模式'),
            subtitle: Text(themeMode.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editThemeMode,
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('启动行为'),
            subtitle: Text(
              settings[AppConstants.settingStartupBehavior] ==
                      AppConstants.startupBehaviorLast
                  ? '进入应用时回到退出时的对话'
                  : '进入应用时创建新对话',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editStartupBehavior,
          ),

          const Divider(),
          _sectionHeader('API 配置'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务商管理'),
            subtitle: Text(
              apiConfigs.isEmpty
                  ? '尚未添加服务商'
                  : '${apiConfigs.length} 个服务商 · ${apiConfigs.where((c) => c.enabled).length} 在线',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openListPage(),
          ),

          const Divider(),
          _sectionHeader('主动消息（P1）'),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('主动消息'),
            subtitle: const Text('定时任务：让 LLM 主动向会话发消息'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ActiveTasksPage(),
              ),
            ),
          ),

          const Divider(),
          _sectionHeader('局域网同步（P1）'),

          ListTile(
            leading: Icon(
              syncStatus.connected
                  ? Icons.cloud_done
                  : (syncStatus.enabled ? Icons.cloud_queue : Icons.cloud_off),
              color: syncStatus.connected
                  ? Colors.green
                  : (syncStatus.enabled ? Colors.orange : null),
            ),
            title: const Text('消息同步 / 配对'),
            subtitle: Text(
              syncStatus.enabled
                  ? (syncStatus.connected
                      ? '已连接 ${syncStatus.host}:${syncStatus.port}'
                      : '已配对，等待连接')
                  : '未开启同步',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SyncSetupPage()),
            ),
          ),
          ListTile(
            leading: serverStatus == null
                ? const Icon(Icons.lan_outlined)
                : const Icon(Icons.lan, color: Colors.green),
            title: Text(serverStatus == null ? '本地服务器未启动' : '本地服务器运行中'),
            subtitle: Text(
              serverStatus == null
                  ? '电脑端作为权威源集中存储聊天记录'
                  : '端口 ${serverStatus.port} · 已配对 ${serverStatus.pairedDevices} 台'
                      '${serverStatus.pairCode == null || serverStatus.pairCode!.isEmpty ? '' : ' · 配对码 ${serverStatus.pairCode}'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LocalServerPage()),
            ),
          ),

          const Divider(),
          _sectionHeader('性能'),
          ListTile(
            leading: const Icon(Icons.speed_outlined),
            title: const Text('命中缓存'),
            subtitle: const Text('查看历史请求的缓存命中情况（token 命中率）'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CacheHitsPage()),
            ),
          ),

          const Divider(),
          _sectionHeader('参数设置'),

          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('默认参数'),
            subtitle: Text(
              'temperature=${settings[AppConstants.settingTemperature] ?? '0.7'} '
              'max_tokens=${settings[AppConstants.settingMaxTokens] ?? '2048'} '
              'top_p=${settings[AppConstants.settingTopP] ?? '1.0'}',
            ),
            onTap: _editDefaultParams,
          ),
          const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('System Prompt 预设'),
            subtitle: Text('TODO(M0)：提示词模板管理'),
            enabled: false,
          ),

          const Divider(),
          _sectionHeader('关于'),
          ListTile(
            leading: const Icon(Icons.system_update_alt_outlined),
            title: const Text('检查更新'),
            subtitle: Text('当前版本 $_currentVersion'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _checkForUpdate,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  /// 选择主题模式（跟随系统 / 浅色 / 深色），持久化到 settings 表。
  Future<void> _editThemeMode() async {
    final current = AppThemeMode.fromValue(
      ref.read(settingsProvider)[AppConstants.settingThemeMode],
    );
    final selected = await showDialog<AppThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('主题模式'),
        children: [
          RadioGroup<AppThemeMode>(
            groupValue: current,
            onChanged: (value) {
              if (value != null) Navigator.of(context).pop(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in AppThemeMode.values)
                  RadioListTile<AppThemeMode>(
                    value: mode,
                    title: Text(mode.label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;
    await ref
        .read(settingsProvider.notifier)
        .set(AppConstants.settingThemeMode, selected.value);
  }

  /// 选择启动行为（回到退出时的对话 / 创建新对话），持久化到 settings 表。
  Future<void> _editStartupBehavior() async {
    final current =
        ref.read(settingsProvider)[AppConstants.settingStartupBehavior];
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('启动行为'),
        children: [
          RadioGroup<String>(
            groupValue: current == AppConstants.startupBehaviorLast
                ? AppConstants.startupBehaviorLast
                : AppConstants.startupBehaviorNew,
            onChanged: (value) {
              if (value != null) Navigator.of(context).pop(value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                RadioListTile<String>(
                  value: AppConstants.startupBehaviorLast,
                  title: Text('进入应用时回到退出时的对话'),
                ),
                RadioListTile<String>(
                  value: AppConstants.startupBehaviorNew,
                  title: Text('进入应用时创建新对话'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;
    await ref
        .read(settingsProvider.notifier)
        .set(AppConstants.settingStartupBehavior, selected);
  }

  Future<void> _openListPage() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ApiConfigListPage()),
    );
  }

  /// 检查更新：请求 GitHub Releases API，与当前版本比对后弹窗提示。
  ///
  /// - 有新版本：显示新版本号、Release 名称与更新说明，提供 APK 下载按钮；
  /// - 无新版本：提示已是最新版本；
  /// - 请求失败/解析失败：提示检查失败原因。
  Future<void> _checkForUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final navigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              SizedBox(width: 16),
              Text('正在检查更新…'),
            ],
          ),
        ),
      ),
    );

    try {
      final update = await UpdateService().fetchLatestRelease();
      final current = await UpdateService.currentVersion();
      if (!mounted) return;
      navigator.pop();
      if (UpdateService.compareVersions(update.version, current) > 0) {
        await _showUpdateDialog(update);
      } else {
        _showSnack('当前已是最新版本 $current');
      }
    } catch (e) {
      if (!mounted) return;
      navigator.pop();
      _showSnack('检查更新失败：$e');
    }
  }

  /// 有新版本时的更新对话框：版本号、Release 名称、更新说明、下载按钮。
  Future<void> _showUpdateDialog(UpdateInfo update) async {
    final canDownload = update.apkUrl != null && update.apkUrl!.isNotEmpty;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('发现新版本 ${update.version}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (update.name.isNotEmpty && update.name != update.version)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    update.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              Text(
                update.body.isEmpty ? '暂无更新说明' : update.body,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后'),
          ),
          if (canDownload)
            FilledButton.icon(
              onPressed: () => _downloadApk(update.apkUrl!),
              icon: const Icon(Icons.download),
              label: const Text('下载 APK'),
            ),
        ],
      ),
    );
  }

  /// 打开 APK 下载链接（浏览器/外部应用）。
  Future<void> _downloadApk(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('无法打开下载链接：$url');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 编辑全局默认参数（PRD 4.5.1：temperature/max_tokens/top_p/system_prompt）。
  Future<void> _editDefaultParams() async {
    final settings = ref.read(settingsProvider);
    final temperatureCtrl = TextEditingController(
        text: settings[AppConstants.settingTemperature] ??
            '${AppConstants.defaultTemperature}');
    final maxTokensCtrl = TextEditingController(
        text: settings[AppConstants.settingMaxTokens] ??
            '${AppConstants.defaultMaxTokens}');
    final topPCtrl = TextEditingController(
        text: settings[AppConstants.settingTopP] ?? '${AppConstants.defaultTopP}');
    final systemPromptCtrl = TextEditingController(
        text: settings[AppConstants.settingSystemPrompt] ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('默认参数'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: temperatureCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'temperature（0.0 ~ 2.0，默认 0.7）',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: maxTokensCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'max_tokens（1 ~ 上限，默认 2048）',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: topPCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'top_p（0.0 ~ 1.0，默认 1.0）',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: systemPromptCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'system_prompt（可选）',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (!mounted) return;

    final temp = double.tryParse(temperatureCtrl.text.trim());
    final maxTok = int.tryParse(maxTokensCtrl.text.trim());
    final topP = double.tryParse(topPCtrl.text.trim());
    if (temp == null || temp < 0 || temp > 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('temperature 需为 0.0 ~ 2.0 的数字')),
      );
      return;
    }
    if (maxTok == null || maxTok < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('max_tokens 需为不小于 1 的整数')),
      );
      return;
    }
    if (topP == null || topP < 0 || topP > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('top_p 需为 0.0 ~ 1.0 的数字')),
      );
      return;
    }
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.set(
        AppConstants.settingTemperature, temperatureCtrl.text.trim());
    await notifier.set(
        AppConstants.settingMaxTokens, maxTokensCtrl.text.trim());
    await notifier.set(AppConstants.settingTopP, topPCtrl.text.trim());
    await notifier.set(
        AppConstants.settingSystemPrompt, systemPromptCtrl.text.trim());
  }
}
