import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/conversations_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../core/theme.dart';
import '../../domain/models/conversation.dart';

/// 窄屏聊天页的会话抽屉：展示会话列表并支持点选切换对话（微信风格）。
///
/// 仅手机窄屏使用；宽屏三栏已有 SessionListPage 左栏，不重复叠加。
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
                        return ListTile(
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
                          onTap: () =>
                              _selectConversation(context, ref, conversation),
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

extension on Iterable<Conversation> {
  Conversation? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
