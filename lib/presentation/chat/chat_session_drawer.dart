import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/conversations_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/prompt_templates_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../domain/models/conversation.dart';

/// 窄屏聊天页的会话抽屉：展示会话列表并支持点选切换对话（微信风格）。
///
/// 仅手机窄屏使用；宽屏三栏已有 SessionListPage 左栏，不重复叠加。
/// 长按/右键会话条目弹出操作菜单（置顶/重命名/默认模板/归档/删除），
/// 与桌面端 SessionListPage 行为保持一致。
class ChatSessionDrawer extends ConsumerWidget {
  const ChatSessionDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final selected = ref.watch(selectedConversationProvider);

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.82,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '会话',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: '新建会话',
                    onPressed: () => _createConversation(context, ref),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: conversations.isEmpty
                  ? _buildEmptyGuide(context)
                  : ListView.builder(
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final conversation = conversations[index];
                        final isSelected = selected?.id == conversation.id;
                        // 长按弹出操作菜单；GestureDetector 仅拦截长按/次级
                        // 手势，不影响点选切换会话。
                        return GestureDetector(
                          onLongPressStart: (details) =>
                              _showConversationMenuAt(
                                  context, details.globalPosition,
                                  conversation, ref),
                          child: ListTile(
                            selected: isSelected,
                            leading: Icon(
                              conversation.pinned
                                  ? Icons.push_pin
                                  : Icons.chat_bubble_outline,
                              color: conversation.pinned
                                  ? AppTheme.brandGreen
                                  : null,
                            ),
                            title: Text(
                              conversation.title.trim().isEmpty
                                  ? '未命名会话'
                                  : conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${_formatTime(conversation.updatedAt)}\n'
                              '${conversation.lastMessage.isEmpty ? '暂无消息' : conversation.lastMessage}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () =>
                                _selectConversation(context, ref, conversation),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyGuide(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            const Text('还没有会话\n点击右上角 + 新建', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  /// 会话操作菜单项：与桌面端 SessionListPage 三点菜单/长按菜单一致。
  List<PopupMenuEntry<String>> _buildConversationMenuItems(
      Conversation conversation) {
    return [
      PopupMenuItem(
        value: 'pin',
        child: Text(conversation.pinned ? '取消置顶' : '置顶'),
      ),
      const PopupMenuItem(value: 'rename', child: Text('重命名')),
      const PopupMenuItem(value: 'template', child: Text('默认模板')),
      const PopupMenuItem(value: 'archive', child: Text('归档')),
      const PopupMenuItem(value: 'delete', child: Text('删除会话')),
    ];
  }

  /// 长按会话条目：在点击位置弹出上下文操作菜单（与桌面端行为一致）。
  Future<void> _showConversationMenuAt(BuildContext context, Offset globalPosition,
      Conversation conversation, WidgetRef ref) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final local = overlay.globalToLocal(globalPosition);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        local.dx + 1,
        local.dy + 1,
      ),
      items: _buildConversationMenuItems(conversation),
    );
    if (value == null || !context.mounted) return;
    await _onMenu(context, ref, conversation, value);
  }

  Future<void> _onMenu(BuildContext context, WidgetRef ref,
      Conversation conversation, String value) async {
    switch (value) {
      case 'pin':
        await ref
            .read(conversationsProvider.notifier)
            .togglePinned(conversation);
      case 'rename':
        await _showRenameDialog(context, ref, conversation);
      case 'template':
        await _showTemplatePicker(context, ref, conversation);
      case 'archive':
        await ref
            .read(conversationsProvider.notifier)
            .toggleArchive(conversation);
        // 归档当前选中会话时清空聊天区。
        if (ref.read(selectedConversationProvider)?.id == conversation.id) {
          ref.read(selectedConversationProvider.notifier).state = null;
          ref.read(messagesProvider.notifier).clear();
        }
      case 'delete':
        await _showDeleteDialog(context, ref, conversation);
    }
  }

  /// 重命名：弹窗修改会话标题（与桌面端一致）。
  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref,
      Conversation conversation) async {
    final controller = TextEditingController(text: conversation.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(
            hintText: '输入会话标题',
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
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.trim().isEmpty) return;
    await ref
        .read(conversationsProvider.notifier)
        .rename(conversation, newTitle);
    _syncSelectedIfCurrent(ref, conversation);
  }

  /// 默认模板：为该会话选择 System Prompt 模板（与桌面端一致）。
  Future<void> _showTemplatePicker(BuildContext context, WidgetRef ref,
      Conversation conversation) async {
    final notifier = ref.read(promptTemplatesProvider.notifier);
    await notifier.load();
    if (!context.mounted) return;
    final templates = ref.read(promptTemplatesProvider);

    final pickedId = await showModalBottomSheet<int?>(
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
                '设置默认模板（${conversation.title}）',
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            if (templates.isEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '还没有可用模板，请先到设置页创建模板',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: const Text('跟随全局默认'),
                      subtitle: const Text('使用设置页中的全局 System Prompt'),
                      trailing: conversation.promptTemplateId == null
                          ? Icon(
                              Icons.check,
                              color: Theme.of(sheetContext).colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.of(sheetContext).pop(null),
                    ),
                    for (final template in templates)
                      ListTile(
                        title: Text(
                          template.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          template.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: conversation.promptTemplateId != null &&
                                conversation.promptTemplateId == template.id
                            ? Icon(
                                Icons.check,
                                color:
                                    Theme.of(sheetContext).colorScheme.primary,
                              )
                            : null,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(template.id),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;
    if (pickedId == conversation.promptTemplateId) return;
    await ref
        .read(conversationsProvider.notifier)
        .setPromptTemplate(conversation, pickedId);
    _syncSelectedIfCurrent(ref, conversation);
  }

  /// 删除：二次确认后删除会话（保留确认，避免误删）。
  Future<void> _showDeleteDialog(BuildContext context, WidgetRef ref,
      Conversation conversation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「${conversation.title}」吗？\n会话内的消息将一并删除。'),
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
    await ref.read(conversationsProvider.notifier).delete(conversation.id!);
    if (ref.read(selectedConversationProvider)?.id == conversation.id) {
      ref.read(selectedConversationProvider.notifier).state = null;
      ref.read(messagesProvider.notifier).clear();
    }
  }

  /// 若操作的是当前选中会话，同步选中态标题/模板（与桌面端一致）。
  void _syncSelectedIfCurrent(WidgetRef ref, Conversation conversation) {
    final updated = ref
        .read(conversationsProvider)
        .where((c) => c.id == conversation.id)
        .firstOrNull;
    if (updated != null &&
        ref.read(selectedConversationProvider)?.id == updated.id) {
      ref.read(selectedConversationProvider.notifier).state = updated;
    }
  }

  /// 新建会话并选中，随后收起抽屉。
  Future<void> _createConversation(
      BuildContext context, WidgetRef ref) async {
    final id = await ref.read(conversationsProvider.notifier).create();
    final conversations = ref.read(conversationsProvider);
    final created = conversations.where((c) => c.id == id).firstOrNull;
    if (created != null) {
      ref.read(selectedConversationProvider.notifier).state = created;
      await ref.read(messagesProvider.notifier).loadForConversation(id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }

  /// 点选会话：切换选中并加载消息，随后收起抽屉。
  void _selectConversation(
      BuildContext context, WidgetRef ref, Conversation conversation) {
    ref.read(selectedConversationProvider.notifier).state = conversation;
    ref.read(messagesProvider.notifier).loadForConversation(conversation.id!);
    Navigator.of(context).pop();
  }

  /// 会话列表时间：今天 HH:mm；今年 MM-dd；更早 yyyy-MM-dd。
  String _formatTime(int ms) => formatTime(ms);
}

extension on Iterable<Conversation> {
  Conversation? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
