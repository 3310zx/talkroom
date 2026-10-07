import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/api_configs_provider.dart';
import '../../core/open_url_io.dart'
    if (dart.library.html) '../../core/open_url_web.dart' as open_url;
import '../../core/utils.dart';
import '../../data/preset_providers.dart';
import '../../data/secure_storage/api_key_store.dart';
import '../../domain/models/api_config.dart';

/// API 服务商配置详情页（参考 UI 设计图二）。
///
/// 承担「操作层」职责：配置名称 / 接口地址 / API 密钥（密文 + 检查），
/// 以及独立「模型」管理区（+新建 / 重置 / 获取 / 改名 / 删除）。
/// 支持从 [presetProviders] 选中预设后新建：自动填充名称、接口地址与
/// 默认模型列表，API Key 仍由用户填写；[preset] 为 null 时保留原有
/// 手动配置能力。
/// 数据层保持不变：密钥仍经 [ApiKeyStore] 安全存储，配置仍走
/// [apiConfigsProvider] 读写 SQLite。
class ApiConfigDetailPage extends ConsumerStatefulWidget {
  const ApiConfigDetailPage({super.key, this.existing, this.preset});

  final ApiConfig? existing;

  /// 选中的预设服务商（仅新建时用于自动填充，编辑模式忽略）。
  final PresetProvider? preset;

  @override
  ConsumerState<ApiConfigDetailPage> createState() => _ApiConfigDetailPageState();
}

class _ApiConfigDetailPageState extends ConsumerState<ApiConfigDetailPage> {
  late final TextEditingController _baseUrlController;
  late final TextEditingController _apiKeyController;

  /// 服务商名称（大标题，点击铅笔可编辑）。
  late String _name;
  late List<String> _models;

  /// 重置基准：进入页面时的模型列表。
  late List<String> _originalModels;

  bool _obscureKey = true;
  bool _saving = false;
  bool _checking = false;
  bool _fetching = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final preset = widget.preset;
    // 新建时优先使用预设自动填充；编辑模式以既有配置为准（预设仅作提示）。
    _name = existing?.name ?? preset?.name ?? '';
    _baseUrlController =
        TextEditingController(text: existing?.baseUrl ?? preset?.baseUrl ?? '');
    _apiKeyController = TextEditingController();
    _models = List.of(existing?.modelIds ?? preset?.modelIds ?? const []);
    _originalModels = List.of(_models);
    _loadExistingKey(existing);
  }

  /// 编辑模式读取安全存储中的已有密钥（密文显示，留空则保持原值）。
  Future<void> _loadExistingKey(ApiConfig? existing) async {
    if (existing == null || existing.apiKeyRef.isEmpty) return;
    final key = await ApiKeyStore.read(existing.apiKeyRef);
    if (!mounted || key == null || key.isEmpty) return;
    _apiKeyController.text = key;
    setState(() {});
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildHeader(context),
          const SizedBox(height: 8),
          _sectionLabel(context, '接口地址'),
          TextField(
            controller: _baseUrlController,
            decoration: const InputDecoration(
              hintText: 'https://api.example.com/v1',
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          _sectionLabel(context, 'API 密钥'),
          _buildApiKeyRow(context),
          const SizedBox(height: 16),
          _buildModelSection(context),
          const SizedBox(height: 8),
          Text(
            'API Key 将加密存储在系统安全存储中，数据库只保存引用（PRD 6.2）。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_saving ? '保存中…' : '保存'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: _saving ? null : _deleteConfig,
              style: TextButton.styleFrom(foregroundColor: colorScheme.error),
              child: const Text('删除此服务商'),
            ),
          ],
        ],
      ),
    );
  }

  /// 大标题：服务商名 + 外链图标 + 编辑名称铅笔。
  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            _name.isEmpty ? '新服务商' : _name,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          icon: Icon(Icons.open_in_new, color: colorScheme.onSurfaceVariant),
          tooltip: '打开服务商站点',
          onPressed: () => _openBaseUrl(),
        ),
        IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: '编辑名称',
          onPressed: _editName,
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  Widget _buildApiKeyRow(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              hintText: _isEdit
                  ? '留空保持不变'
                  : (widget.preset?.requiresApiKey ?? true)
                      ? 'sk-...'
                      : '本地服务无需密钥，可留空',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey ? Icons.visibility : Icons.visibility_off,
                ),
                tooltip: _obscureKey ? '显示密钥' : '隐藏密钥',
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _checking ? null : _checkApiKey,
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          child: Text(_checking ? '检查中…' : '检查'),
        ),
      ],
    );
  }

  Widget _buildModelSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '模型',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _fetching ? null : _resetModels,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('重置'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _fetching ? null : _fetchModels,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('获取'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _addModel,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建'),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_models.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '暂无模型，点击「+ 新建」手动添加，或「获取」从服务商拉取',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          ..._models.asMap().entries.map(
                (entry) => _ModelTile(
                  modelId: entry.value,
                  onRename: () => _renameModel(entry.key),
                  onDelete: () => _removeModel(entry.key),
                ),
              ),
      ],
    );
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑服务商名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如 SiliconFlow'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _name = result);
    }
  }

  /// 打开服务商站点（桌面端调用系统默认浏览器）。
  Future<void> _openBaseUrl() async {
    final url = _baseUrlController.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      _toast('请先填写合法的接口地址');
      return;
    }
    try {
      await open_url.openExternalUrl(url);
    } catch (_) {
      _toast('请手动在浏览器打开：$url');
    }
  }

  /// 校验 API 密钥：请求 OpenAI 兼容 {baseUrl}/models。
  Future<bool> _verifyKey() async {
    final key = _apiKeyController.text.trim();
    final requiresKey = widget.preset?.requiresApiKey ?? true;
    if (key.isEmpty && requiresKey) {
      _toast('请先输入 API 密钥');
      return false;
    }
    var baseUrl = _baseUrlController.text.trim();
    // 去掉尾部斜杠，避免请求时拼出 `//chat/completions` 双斜杠路径。
    while (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      _toast('请先填写合法的接口地址');
      return false;
    }
    try {
      final response = await Dio().get<Map<String, dynamic>>(
        '${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/models',
        options: Options(
          headers: key.isEmpty ? null : {'Authorization': 'Bearer $key'},
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      final data = response.data;
      final list = (data?['data'] as List?) ?? const [];
      final ids = list
          .map((e) => (e is Map && e['id'] is String) ? e['id'] as String : null)
          .whereType<String>()
          .toList();
      if (ids.isEmpty) {
        _toast('密钥有效，但未检测到可用模型');
        return true;
      }
      // 合并进本地模型列表（去重，保存时统一落库）。
      setState(() {
        for (final id in ids) {
          if (!_models.contains(id)) _models.add(id);
        }
      });
      _toast('密钥有效，共检测到 ${ids.length} 个模型，已合并到模型列表');
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final detail = e.response?.data is Map
          ? ((e.response?.data as Map)['error'] is Map
              ? (((e.response?.data as Map)['error'] as Map)['message'] ??
                  'HTTP $status')
              : 'HTTP $status')
          : e.message;
      _toast('检查失败（${status ?? '网络错误'}）：$detail');
      return false;
    } catch (e) {
      _toast('检查失败：$e');
      return false;
    }
  }

  Future<void> _checkApiKey() async {
    setState(() => _checking = true);
    try {
      await _verifyKey();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  /// 获取模型：与检查共用同一接口，仅拉取模型列表合并。
  Future<void> _fetchModels() async {
    setState(() => _fetching = true);
    try {
      final key = _apiKeyController.text.trim();
      if (key.isEmpty && (widget.preset?.requiresApiKey ?? true)) {
        _toast('请先输入 API 密钥后再获取模型');
        return;
      }
      await _verifyKey();
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _addModel() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建模型'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '模型 ID，可多个用逗号分隔，如 deepseek-chat, gpt-4o-mini',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final ids = result
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    setState(() {
      for (final id in ids) {
        if (!_models.contains(id)) _models.add(id);
      }
    });
  }

  Future<void> _renameModel(int index) async {
    final controller = TextEditingController(text: _models[index]);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑模型'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() {
      final old = _models[index];
      _models[index] = result;
      _originalModels = _originalModels.map((e) => e == old ? result : e).toList();
    });
  }

  Future<void> _removeModel(int index) async {
    setState(() => _models.removeAt(index));
  }

  Future<void> _resetModels() async {
    if (listEquals(_models, _originalModels)) {
      _toast('模型列表未做改动');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置模型列表'),
        content: Text('将恢复为进入页面时的模型列表，当前未保存的改动会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _models = List.of(_originalModels));
    }
  }

  Future<void> _save() async {
    final name = _name.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (name.isEmpty) {
      _toast('请先填写服务商名称（点击大标题旁铅笔图标）');
      return;
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      _toast('接口地址需以 http:// 或 https:// 开头');
      return;
    }
    final apiKey = _apiKeyController.text.trim();
    final requiresKey = widget.preset?.requiresApiKey ?? true;
    if (!_isEdit && apiKey.isEmpty && requiresKey) {
      _toast('请先输入 API 密钥');
      return;
    }
    if (_models.isEmpty) {
      _toast('请至少添加一个模型');
      return;
    }

    setState(() => _saving = true);
    try {
      final notifier = ref.read(apiConfigsProvider.notifier);
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_isEdit) {
        final existing = widget.existing!;
        final updated = existing.copyWith(
          name: name,
          baseUrl: baseUrl,
          modelIds: _models,
        );
        await notifier.update(updated, apiKey: apiKey.isEmpty ? null : apiKey);
      } else {
        final refKey = ApiKeyStore.refKeyFor(now % 100000);
        final config = ApiConfig(
          name: name,
          baseUrl: baseUrl,
          apiKeyRef: refKey,
          modelIds: _models,
          createdAt: now,
          updatedAt: now,
        );
        await notifier.add(config, apiKey);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除此服务商'),
        content: const Text('将删除该配置及其安全存储中的密钥，确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(apiConfigsProvider.notifier).remove(widget.existing!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toast(String message) {
    if (!mounted) return;
    showToast(context, message);
  }
}

/// 单个模型条目：模型 ID + 参数标签（占位）+ 齿轮（改名）+ 红色删除。
class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.modelId,
    required this.onRename,
    required this.onDelete,
  });

  final String modelId;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(
          color: colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modelId,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.tune,
                      size: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '参数未同步',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.settings,
              color: colorScheme.onSurfaceVariant,
            ),
            tooltip: '编辑模型',
            onPressed: onRename,
          ),
          const SizedBox(width: 4),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: onDelete,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: colorScheme.error,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.remove, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
