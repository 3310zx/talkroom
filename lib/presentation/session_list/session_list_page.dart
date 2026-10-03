import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/conversations_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/theme.dart';

/// 会话列表页（三栏左栏 / 移动端聊天 Tab 顶部入口）。
class SessionListPage extends ConsumerWidget {
  const SessionListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider);
    final selected = ref.watch(selectedConversationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LLM Chat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建会话',
            onPressed: () => _createConversation(ref),
          ),
        ],
      ),
      body: conversations.isEmpty
          ? _buildEmptyGuide(context)
          : ListView.builder(
              itemCount: conversations.length,
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                final isSelected = selected?.id == conversation.id;
                return ListTile(
                  selected: isSelected,
                  leading: Icon(
                    conversation.pinned ? Icons.push_pin : Icons.chat_bubble_outline,
                    color: conversation.pinned
                        ? AppTheme.brandGreen
                        : null,
                  ),
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
                  onTap: () => _selectConversation(ref, conversation),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => _onMenu(ref, conversation, value),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'pin', child: Text('置顶/取消置顶')),
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除会话')),
                    ],
                  ),
                );
              },
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
            // TODO(M0): 未添加 API 时的引导卡：跳转设置页添加 API（PRD 3.7）。
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

  void _selectConversation(WidgetRef ref, conversation) {
    ref.read(selectedConversationProvider.notifier).state = conversation;
    ref.read(messagesProvider.notifier).loadForConversation(conversation.id!);
  }

  Future<void> _onMenu(WidgetRef ref, conversation, String value) async {
    switch (value) {
      case 'pin':
        await ref.read(conversationsProvider.notifier).togglePinned(conversation);
      case 'delete':
        // TODO(M0): 删除前二次确认（当前骨架直接删除，后续加确认 Dialog）。
        await ref.read(conversationsProvider.notifier).delete(conversation.id!);
        if (ref.read(selectedConversationProvider)?.id == conversation.id) {
          ref.read(selectedConversationProvider.notifier).state = null;
          ref.read(messagesProvider.notifier).clear();
        }
      case 'rename':
        // TODO(M0): 弹窗重命名会话标题。
        break;
    }
  }

  /// 会话列表时间：今天 HH:mm；今年 MM-dd；更早 yyyy-MM-dd。
  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${two(dt.hour)}:${two(dt.minute)}';
    }
    if (dt.year == now.year) return '${two(dt.month)}-${two(dt.day)}';
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }
}

extension on Iterable<dynamic> {
  dynamic get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
