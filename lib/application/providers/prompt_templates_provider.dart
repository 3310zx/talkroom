import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/prompt_template.dart';
import '../../domain/repositories/prompt_template_repository.dart';
import 'database_provider.dart';

/// System Prompt 模板列表状态（PRD 2.4 R13：创建/编辑/保存/切换多个模板）。
final promptTemplatesProvider =
    StateNotifierProvider<PromptTemplatesNotifier, List<PromptTemplate>>(
  (ref) => PromptTemplatesNotifier(
      ref.watch(appDatabaseProvider).promptTemplateRepository),
);

class PromptTemplatesNotifier extends StateNotifier<List<PromptTemplate>> {
  PromptTemplatesNotifier(this._repository) : super(const []);

  final PromptTemplateRepository _repository;

  Future<void> load() async {
    state = await _repository.getAll();
  }

  Future<int> create({required String name, required String content}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _repository.insert(
      PromptTemplate(name: name, content: content, createdAt: now),
    );
    await load();
    return id;
  }

  Future<void> update(PromptTemplate template) async {
    await _repository.update(template);
    await load();
  }

  Future<void> delete(PromptTemplate template) async {
    if (template.builtin) return;
    await _repository.delete(template.id!);
    await load();
  }
}
