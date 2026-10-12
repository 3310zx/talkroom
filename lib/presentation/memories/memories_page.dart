import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/conversations_provider.dart';
import '../../application/providers/database_provider.dart';
import '../../application/providers/memories_provider.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/memory_item.dart';

/// 记忆库管理页（功能三）。
///
/// 浏览全部记忆（置顶优先 + 最近）、搜索、添加、删除、置顶/取消置顶。
/// 记忆按会话归属（决策 D5）；记忆不参与局域网同步与备份（决策 D7 / D8）。
class MemoriesPage extends ConsumerStatefulWidget {
  const MemoriesPage({super.key});

  @override
  ConsumerState<MemoriesPage> createState() => _MemoriesPageState();
}

class _MemoriesPageState extends ConsumerState<MemoriesPage> {
  final _searchCtrl = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider);
    final memories = _keyword.trim().isEmpty
        ? ref.watch(allMemoriesProvider).maybeWhen(
            data: (list) => list,
            orElse: () => const [],
          )
        : ref.watch(memorySearchProvider(_keyword.trim())).maybeWhen(
            data: (list) => list,
            orElse: () => const [],
          );
    final convById = {for (final c in conversations) if (c.id != null) c.id!: c};

    return Scaffold(
      appBar: AppBar(title: const Text('记忆库')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addMemory(context, conversations),
        icon: const Icon(Icons.add),
        label: const Text('添加记忆'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '搜索记忆内容',
                suffixIcon: _keyword.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _keyword = '');
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _keyword = v),
            ),
          ),
          Expanded(
            child: memories.isEmpty
                ? const Center(child: Text('还没有记忆\n在消息长按菜单「保存到记忆库」添加', textAlign: TextAlign.center))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: memories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = memories[index];
                      final conv = convById[item.conversationId];
                      return ListTile(
                        leading: Icon(
                          item.pinned
                              ? Icons.push_pin
                              : Icons.bookmark_outline,
                          color: item.pinned
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          item.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${conv?.title ?? '会话 #${item.conversationId}'} · '
                          '${item.kindLabel} · ${_formatTime(item.updatedAt)}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: item.pinned ? '取消置顶' : '置顶',
                              icon: Icon(
                                item.pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                              ),
                              onPressed: () =>
                                  ref.read(memoriesProvider.notifier).togglePinned(item),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              onPressed: () => _deleteMemory(ref, item),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addMemory(BuildContext context, List<Conversation> conversations) async {
    final controller = TextEditingController();
    int? conversationId;
    if (conversations.isNotEmpty) conversationId = conversations.first.id;
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('添加记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '输入要记住的内容',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: conversationId,
              decoration: const InputDecoration(
                labelText: '所属会话',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final c in conversations)
                  if (c.id != null)
                    DropdownMenuItem(value: c.id, child: Text(c.title)),
              ],
              onChanged: (v) => conversationId = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (content == null || content.isEmpty) return;
    if (conversationId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先创建会话，再添加记忆')),
      );
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.read(appDatabaseProvider).memoryRepository.insert(MemoryItem(
          conversationId: conversationId!,
          content: content,
          kind: 'manual',
          createdAt: now,
          updatedAt: now,
        ));
    ref.invalidate(allMemoriesProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已添加记忆')),
    );
  }

  Future<void> _deleteMemory(WidgetRef ref, MemoryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除记忆'),
        content: Text('确定删除这条记忆吗？\n\n「${item.content}」'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(appDatabaseProvider).memoryRepository.delete(item.id!);
    ref.invalidate(allMemoriesProvider);
  }
}
