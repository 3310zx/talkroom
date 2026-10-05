import '../models/prompt_template.dart';

/// System Prompt 模板仓储（PRD 6.1.2 `prompt_templates` 表，v1.0.13 R13）。
abstract interface class PromptTemplateRepository {
  /// 全部模板（内置 + 自定义，按 created_at 升序）。
  Future<List<PromptTemplate>> getAll();

  /// 按 id 查询模板（R13 会话默认模板解析用；不存在返回 null）。
  Future<PromptTemplate?> getById(int id);

  /// 新增模板（返回落库 id）。
  Future<int> insert(PromptTemplate template);

  /// 更新模板（名称 / 内容）。
  Future<void> update(PromptTemplate template);

  /// 删除模板（内置模板由上层禁止删除）。
  Future<void> delete(int id);
}
