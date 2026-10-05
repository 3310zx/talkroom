import '../../domain/models/prompt_template.dart';
import '../../domain/repositories/prompt_template_repository.dart';
import '../database/app_database.dart';

/// System Prompt 模板仓储的 SQLite 实现（`prompt_templates` 表，M0 已建表，
/// v1.0.13 R13 正式启用）。
class PromptTemplateRepositoryImpl implements PromptTemplateRepository {
  PromptTemplateRepositoryImpl(this._appDatabase);

  final AppDatabase _appDatabase;

  @override
  Future<List<PromptTemplate>> getAll() async {
    final rows = await _appDatabase.db.query(
      'prompt_templates',
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(PromptTemplate.fromMap).toList();
  }

  @override
  Future<PromptTemplate?> getById(int id) async {
    final rows = await _appDatabase.db.query(
      'prompt_templates',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PromptTemplate.fromMap(rows.first);
  }

  @override
  Future<int> insert(PromptTemplate template) async {
    return _appDatabase.db.insert(
        'prompt_templates', template.toMap()..remove('id'));
  }

  @override
  Future<void> update(PromptTemplate template) async {
    await _appDatabase.db.update(
      'prompt_templates',
      template.toMap(),
      where: 'id = ?',
      whereArgs: [template.id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _appDatabase.db.delete(
      'prompt_templates',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
