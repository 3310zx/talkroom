import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/conversations_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/utils.dart';
import '../../domain/models/conversation.dart';

/// 归档会话列表页（R10）：展示已归档会话，支持恢复与删除。
///
/// 归档只改变会话的 archived 标记，消息与设置完整保留；
/// 恢复后会话回到主列表并可继续对话。
class ArchiveConversationsPage extends ConsumerWidget {
  const ArchiveConversationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final archived = conversations.where((c) => c.archived).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('归档会话')),
      body: archived.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.archive_outlined,
                    size: 48,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  const Text('暂无归档会话'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: archived.length,
              itemBuilder: (context, index) {
                final conversation = archived[index];
                return ListTile(
                  leading: const Icon(Icons.archive_outlined),
                  title: Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${_formatTime(conversation.updatedAt)}\n'
                    '${conversation.lastMessage.isEmpty ? '暂无消息' : conversation.lastMessage}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => _onMenu(context, ref, conversation, value),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'restore', child: Text('恢复')),
                      PopupMenuItem(value: 'delete', child: Text('删除会话')),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    WidgetRef ref,
    Conversation conversation,
    String value,
  ) async {
    switch (value) {
      case 'restore':
        await ref.read(conversationsProvider.notifier)
            .toggleArchive(conversation);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('已恢复「${conversation.title}」')));
        }
      case 'delete':
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
  }

  /// 会话列表时间：今天 HH:mm；今年 MM-dd；更早 yyyy-MM-dd。
  String _formatTime(int ms) => formatTime(ms);
}
