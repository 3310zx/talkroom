import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils.dart';
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

  /// 公开只读快照（H1：页面 dispose 后通过缓存的 Notifier 读取当前状态，
  /// 避免直接访问受保护的 state 成员）。
  List<Conversation> get snapshot => state;

  Future<void> load() async {
    final rows = await _repository.getAll();
    // v1.2.20：惰性清洗存量脏数据 —— 历史版本导入/生成时可能写入以换行
    // 或不可见字符开头/包含的 title、last_message，渲染层直接展示会出现
    // 「标题空白、摘要只剩日期」。这里统一清洗后展示，并将变化写回 DB
    // （直接写仓储避免再次触发 load 造成递归；失败不影响本次展示）。
    var needWriteBack = false;
    final cleaned = <Conversation>[];
    for (final c in rows) {
      final title = cleanConversationText(c.title);
      final summary = cleanConversationText(c.lastMessage);
      final newTitle = title.isEmpty ? '未命名会话' : title;
      if (newTitle != c.title || summary != c.lastMessage) {
        needWriteBack = true;
        cleaned.add(c.copyWith(title: newTitle, lastMessage: summary));
      } else {
        cleaned.add(c);
      }
    }
    if (needWriteBack) {
      for (final c in cleaned) {
        try {
          await _repository.update(c);
        } catch (_) {
          // 写回失败不影响内存态展示。
        }
      }
    }
    state = cleaned;
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

  /// 归档 / 恢复会话（R10：归档会话移入归档列表，可从归档恢复）。
  Future<void> toggleArchive(Conversation conversation) async {
    await update(conversation.copyWith(archived: !conversation.archived));
  }

  /// 重命名会话标题（R10）。
  Future<void> rename(Conversation conversation, String newTitle) async {
    final title = newTitle.trim();
    if (title.isEmpty) return;
    await update(conversation.copyWith(title: title));
  }

  /// 设置会话默认 System Prompt 模板（R13；templateId 为 null 表示跟随全局设置）。
  Future<void> setPromptTemplate(Conversation conversation, int? templateId) async {
    await update(conversation.copyWith(promptTemplateId: templateId));
  }
}
