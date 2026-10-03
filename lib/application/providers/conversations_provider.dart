import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/conversation.dart';
import '../../domain/repositories/conversation_repository.dart';
import 'database_provider.dart';

/// 会话列表状态（PRD 2.2：conversationsProvider）。
final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, List<Conversation>>(
  (ref) => ConversationsNotifier(ref.watch(appDatabaseProvider).conversationRepository),
);

class ConversationsNotifier extends StateNotifier<List<Conversation>> {
  ConversationsNotifier(this._repository) : super(const []);

  final ConversationRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<int> create({String title = '新会话'}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _repository.insert(
      Conversation(title: title, updatedAt: now, createdAt: now),
    );
    await load();
    return id;
  }

  Future<void> update(Conversation conversation) async {
    await _repository.update(conversation);
    await load();
  }

  Future<void> delete(int id) async {
    await _repository.delete(id);
    await load();
  }

  Future<void> togglePinned(Conversation conversation) async {
    await update(conversation.copyWith(pinned: !conversation.pinned));
  }
}
