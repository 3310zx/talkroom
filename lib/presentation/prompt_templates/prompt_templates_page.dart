import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/providers/prompt_templates_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../core/constants.dart';
import '../../domain/models/prompt_template.dart';

/// System Prompt 模板管理页（PRD 2.4 R13）。
///
/// 支持：创建 / 编辑 / 保存 / 切换（设为全局默认）；模板列表可设为某会话
/// 默认（入口在会话列表菜单）；导入 / 导出（JSON / 文本）。内置模板禁删。
class PromptTemplatesPage extends ConsumerStatefulWidget {
  const PromptTemplatesPage({super.key});

  @override
  ConsumerState<PromptTemplatesPage> createState() => _PromptTemplatesPageState();
}

class _PromptTemplatesPageState extends ConsumerState<PromptTemplatesPage> {
  @override
  void initState() {
    super.initState();
    // 进入页面即加载模板列表（模板数据存库，不随页面重建丢失）。
    Future.microtask(
        () => ref.read(promptTemplatesProvider.notifier).load());
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Prompt 模板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: '导入模板',
            onPressed: () => _showImportDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建模板',
            onPressed: () => _showTemplateEditor(),
          ),
        ],
      ),
      body: templates.isEmpty
          ? _buildEmptyGuide()
          : ListView.separated(
              itemCount: templates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final template = templates[index];
                final isGlobal = template.id != null && template.id == globalTemplateId;
                return ListTile(
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          template.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (template.builtin) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '内置',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondaryContainer,
                            ),
                          ),
                        ),
                      ],
                      if (isGlobal) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '全局默认',
                            style: TextStyle(
                              fontSize: 11,
                              color:
                                  Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    template.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  onTap: () => _applyAsGlobal(template),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) =>
                        _onMenu(context, template, value, isGlobal),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'edit', child: const Text('编辑')),
                      PopupMenuItem(
                          value: 'export_json', child: const Text('导出 JSON')),
                      PopupMenuItem(
                          value: 'export_text', child: const Text('导出文本')),
                      if (!template.builtin)
                        const PopupMenuItem(
                            value: 'delete', child: Text('删除')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmptyGuide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.article_outlined,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('还没有模板\n点击右上角 + 新建，或导入已有模板',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// 点击模板：切换为全局默认 System Prompt（R13「切换模板」）。
  Future<void> _applyAsGlobal(PromptTemplate template) async {
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.set(AppConstants.settingSystemPrompt, template.content);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text('已切换：${template.name} 作为全局默认提示词')));
    }
  }

  /// 新建 / 编辑模板对话框。
  Future<void> _showTemplateEditor([PromptTemplate? template]) async {
    final nameController = TextEditingController(text: template?.name ?? '');
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
  }

  /// 导入：选择 JSON / 文本，粘贴内容解析后保存。
  Future<void> _showImportDialog() async {
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
    if (!mounted) return;
    if (mode == null) return;

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
            border: OutlineInputBorder(),
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
    if (!context.mounted) return;
    if (raw == null || raw.trim().isEmpty) return;

    PromptTemplate? parsed;
    if (mode == 'json') {
      parsed = PromptTemplate.fromJsonText(raw.trim());
      if (parsed == null) {
        _showToast('JSON 解析失败，请检查格式');
        return;
      }
    } else {
      final lines = raw.trim().split('\n');
      final name = lines.first.trim();
      final content = lines.skip(1).join('\n').trim();
      if (name.isEmpty || content.isEmpty) {
        _showToast('文本格式不正确：第一行应为模板名称');
        return;
      }
      parsed = PromptTemplate(
        name: name,
        content: content,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    }

    await ref.read(promptTemplatesProvider.notifier)
        .create(name: parsed.name, content: parsed.content);
    _showToast('已导入模板「${parsed.name}」');
  }

  Future<void> _onMenu(
    BuildContext context,
    PromptTemplate template,
    String value,
    bool isGlobal,
  ) async {
    switch (value) {
      case 'edit':
        await _showTemplateEditor(template);
      case 'export_json':
        await Share.share(template.toJsonText(), subject: '模板 ${template.name} (JSON)');
      case 'export_text':
        await Share.share(template.toText(), subject: '模板 ${template.name} (文本)');
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
        // 删除的是全局默认模板时，仅清除「全局默认」标记，不修改已写入的提示词。
        if (isGlobal) {
          _showToast('已删除模板（原全局默认提示词保留）');
        }
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

extension on Iterable<int?> {
  int? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
