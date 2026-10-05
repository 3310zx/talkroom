import 'dart:convert';

/// System Prompt 模板实体（对应 PRD 6.1.2 `prompt_templates` 表，v1.0.13 R13）。
///
/// 模板可创建/编辑/保存/切换；内置模板（[builtin] = true）仅允许切换与复制，
/// 不允许删除；自定义模板支持导入导出（JSON / 文本）。
class PromptTemplate {
  final int? id;
  final String name;
  final String content;
  final bool builtin;
  final int createdAt;

  const PromptTemplate({
    this.id,
    required this.name,
    required this.content,
    this.builtin = false,
    required this.createdAt,
  });

  PromptTemplate copyWith({
    int? id,
    String? name,
    String? content,
    bool? builtin,
    int? createdAt,
  }) {
    return PromptTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      content: content ?? this.content,
      builtin: builtin ?? this.builtin,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'content': content,
      'builtin': builtin ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory PromptTemplate.fromMap(Map<String, Object?> map) {
    return PromptTemplate(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '未命名模板',
      content: map['content'] as String? ?? '',
      builtin: (map['builtin'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as int? ?? 0,
    );
  }

  /// 导出 JSON 文本（含名称与内容，供「导出 JSON」功能使用）。
  String toJsonText() {
    return jsonEncode({'name': name, 'content': content});
  }

  /// 导出纯文本内容（供「导出文本」功能使用）。
  String toText() => content;

  /// 从 JSON 文本解析模板（导入「JSON」功能）；解析失败返回 null。
  static PromptTemplate? fromJsonText(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return null;
      final name = decoded['name'];
      final content = decoded['content'];
      if (name is! String || content is! String) return null;
      return PromptTemplate(
        name: name,
        content: content,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      return null;
    }
  }
}
