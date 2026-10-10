import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/conversations_provider.dart';
import '../../application/providers/database_provider.dart';
import '../../application/providers/messages_provider.dart';
import '../../application/providers/ui_state_provider.dart';
import '../../domain/models/conversation.dart';
import '../../domain/models/message_search_hit.dart';

/// 跨会话历史记录搜索页（R12，v1.0.15）。
///
/// 关键词全局模糊搜索全部聊天消息内容，命中列表按消息时间倒序展示
/// （会话标题 + 消息摘要 + 时间 + 角色标记），点击后跳转到对应会话
/// 并自动滚动定位到命中消息。
class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  bool _searching = false;
  bool _searched = false;
  List<MessageSearchHit> _hits = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final kw = value.trim();
    if (kw.isEmpty) {
      setState(() {
        _searching = false;
        _searched = false;
        _hits = const [];
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final repo = ref.read(appDatabaseProvider).messageRepository;
      final hits = await repo.searchMessages(kw, limit: 100);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searched = true;
        _hits = hits;
      });
    });
  }

  Future<void> _openHit(MessageSearchHit hit) async {
    final conversations = ref.read(conversationsProvider);
    var conversation = conversations
        .where((c) => c.id == hit.conversationId)
        .firstOrNull;
    if (conversation == null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      conversation = Conversation(
        id: hit.conversationId,
        title: hit.conversationTitle,
        updatedAt: now,
        createdAt: now,
      );
    }
    ref.read(selectedConversationProvider.notifier).state = conversation;
    await ref.read(messagesProvider.notifier).loadForConversation(hit.conversationId);
    ref.read(pendingSearchMessageIdProvider.notifier).state = hit.message.id;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索聊天记录')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '输入关键词搜索全部聊天记录…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _controller.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: '清空',
                            onPressed: () {
                              _controller.clear();
                              _onChanged('');
                            },
                          ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final kw = _controller.text.trim();
    if (kw.isEmpty) {
      return const Center(
        child: Text(
          '支持搜索全部会话的聊天内容\n点击结果可跳转到对应会话定位',
          textAlign: TextAlign.center,
        ),
      );
    }
    if (_searching) return const SizedBox.shrink();
    if (!_searched) return const SizedBox.shrink();
    if (_hits.isEmpty) {
      return Center(child: Text('没有匹配「$kw」的聊天记录'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final hit = _hits[index];
        final isUser = hit.message.role == 'user';
        return ListTile(
          leading: Icon(
            isUser ? Icons.person_outline : Icons.smart_toy_outlined,
            color: isUser ? Colors.blueGrey : Colors.teal,
          ),
          title: Text(
            hit.conversationTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            hit.message.content.isEmpty ? '（会话标题匹配）' : hit.message.content,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text(
            _formatTime(hit.message.createdAt),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          onTap: () => _openHit(hit),
        );
      },
    );
  }

  String _formatTime(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.month}月${dt.day}日';
  }
}
