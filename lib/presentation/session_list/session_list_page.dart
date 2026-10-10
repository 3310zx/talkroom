import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/conversations_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/prompt_templates_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../domain/models/conversation.dart';
import '../search/global_search_page.dart';
import 'archive_conversations_page.dart';

/// 会话列表页（三栏左栏 / 移动端聊天 Tab 顶部入口）。
///
/// R10 会话管理增强：
/// - 重命名：菜单弹窗修改标题；
/// - 置顶：菜单切换置顶（已置顶会话排前）；
/// - 删除：菜单删除（二次确认，已选中则清空聊天区）；
/// - 搜索：顶部搜索框按标题/摘要过滤；
/// - 归档：菜单归档（移入归档列表，归档页可恢复/删除）。
class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({super.key});

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final selected = ref.watch(selectedConversationProvider);

    // 非归档会话为当前列表；归档会话数量展示为入口角标。
    final active = conversations.where((c) => !c.archived).toList();
    final archivedCount = conversations.where((c) => c.archived).length;
    final keyword = _keyword.trim();
    final visible = keyword.isEmpty
        ? active
        : active
            .where((c) =>
                c.title.contains(keyword) || c.lastMessage.contains(keyword))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Chat'),
        actions: [
          // R12：跨会话全文搜索入口。
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索聊天记录',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GlobalSearchPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建会话',
            onPressed: () => _createConversation(ref),
          ),
        ],
      ),
      body: Column(
        children: [
          // R10 搜索：按会话标题 / 最后一条摘要过滤。
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _keyword = value),
              decoration: InputDecoration(
                hintText: '搜索会话…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: '清空搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _keyword = '');
                        },
                      ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(
            child: conversations.isEmpty
                ? _buildEmptyGuide(context)
                : visible.isEmpty
                    ? Center(child: Text('没有匹配「$keyword」的会话'))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final conversation = visible[index];
                          final isSelected = selected?.id == conversation.id;
                          // R14 长按/右键会话条目弹出操作菜单（重命名/删除等）；
                          // GestureDetector 仅拦截次级（右键）手势，不影响点选。
                          return GestureDetector(
                            onSecondaryTapDown: (details) =>
                                _showConversationMenuAt(
                                    details.globalPosition, conversation),
                            onLongPressStart: (details) =>
                                _showConversationMenuAt(
                                    details.globalPosition, conversation),
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
                            onTap: () => _selectConversation(ref, conversation),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) =>
                                  _onMenu(ref, conversation, value),
                              itemBuilder: (context) =>
                                  _buildConversationMenuItems(conversation),
                            ),
                          ),
                          );
                        },
                      ),
          ),
          // 归档入口（R10）：查看已归档会话，可恢复或删除。
          if (conversations.isNotEmpty)
            ListTile(
              dense: true,
              leading: Icon(
                Icons.archive_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              title: Text(
                '归档（$archivedCount）',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArchiveConversationsPage()),
              ),
            ),
        ],
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
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            const Text('还没有会话\n点击右上角 + 新建', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _createConversation(WidgetRef ref) async {
    final id = await ref.read(conversationsProvider.notifier).create();
    final conversations = ref.read(conversationsProvider);
    final created = conversations.where((c) => c.id == id).firstOrNull;
    if (created != null) {
      ref.read(selectedConversationProvider.notifier).state = created;
      await ref.read(messagesProvider.notifier).loadForConversation(id);
    }
  }

  void _selectConversation(WidgetRef ref, Conversation conversation) {
    ref.read(selectedConversationProvider.notifier).state = conversation;
    ref.read(messagesProvider.notifier).loadForConversation(conversation.id!);
  }

  /// R14 会话操作菜单项：三点按钮菜单与长按/右键菜单共用。
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

  /// R14 长按/右键会话条目：在点击位置弹出上下文操作菜单，
  /// 与三点按钮菜单保持一致的编辑能力（置顶/重命名/模板/归档/删除）。
  Future<void> _showConversationMenuAt(
      Offset globalPosition, Conversation conversation) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
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
    if (value == null || !mounted) return;
    await _onMenu(ref, conversation, value);
  }

  Future<void> _onMenu(
      WidgetRef ref, Conversation conversation, String value) async {
    switch (value) {
      case 'pin':
        await ref.read(conversationsProvider.notifier)
            .togglePinned(conversation);
      case 'rename':
        await _showRenameDialog(ref, conversation);
      case 'template':
        await _showTemplatePicker(ref, conversation);
      case 'archive':
        await ref.read(conversationsProvider.notifier)
            .toggleArchive(conversation);
        // 归档当前选中会话时清空聊天区。
        if (ref.read(selectedConversationProvider)?.id == conversation.id) {
          ref.read(selectedConversationProvider.notifier).state = null;
          ref.read(messagesProvider.notifier).clear();
        }
      case 'delete':
        await _showDeleteDialog(ref, conversation);
    }
  }

  /// R10 重命名：弹窗修改会话标题。
  Future<void> _showRenameDialog(WidgetRef ref, Conversation conversation) async {
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
    await ref.read(conversationsProvider.notifier).rename(conversation, newTitle);
    // 若重命名的是当前选中会话，同步更新选中态标题。
    final updated = ref
        .read(conversationsProvider)
        .where((c) => c.id == conversation.id)
        .firstOrNull;
    if (updated != null &&
        ref.read(selectedConversationProvider)?.id == updated.id) {
      ref.read(selectedConversationProvider.notifier).state = updated;
    }
  }

  /// R13 默认模板：为该会话选择 System Prompt 模板（设为会话默认）；
  /// 选择「跟随全局默认」清除会话级绑定，回退使用全局设置。
  Future<void> _showTemplatePicker(
      WidgetRef ref, Conversation conversation) async {
    final notifier = ref.read(promptTemplatesProvider.notifier);
    await notifier.load();
    if (!mounted) return;
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
    await ref.read(conversationsProvider.notifier)
        .setPromptTemplate(conversation, pickedId);
    // 同步选中态，避免顶栏/发送逻辑使用旧会话对象。
    final updated = ref
        .read(conversationsProvider)
        .where((c) => c.id == conversation.id)
        .firstOrNull;
    if (updated != null &&
        ref.read(selectedConversationProvider)?.id == updated.id) {
      ref.read(selectedConversationProvider.notifier).state = updated;
    }
  }

  /// R10 删除：二次确认后删除会话（保留确认，避免误删）。
  Future<void> _showDeleteDialog(
      WidgetRef ref, Conversation conversation) async {
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

  /// 会话列表时间：今天 HH:mm；今年 MM-dd；更早 yyyy-MM-dd。
  String _formatTime(int ms) => formatTime(ms);
}

extension on Iterable<Conversation> {
  Conversation? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
