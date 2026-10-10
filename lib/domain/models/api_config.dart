/// API 配置实体（对应 PRD 6.1.2 `api_configs` 表）。
class ApiConfig {
  final int? id;
  final String name;
  final String baseUrl;
  final String apiKeyRef;
  final List<String> modelIds;
  final bool enabled;
  // R22：模型收藏标记（列表页置顶展示，便于快速切换）。
  final bool favorite;
  final int createdAt;
  final int updatedAt;

  const ApiConfig({
    this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKeyRef,
    required this.modelIds,
    this.enabled = true,
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  ApiConfig copyWith({
    int? id,
    String? name,
    String? baseUrl,
    String? apiKeyRef,
    List<String>? modelIds,
    bool? enabled,
    bool? favorite,
    int? createdAt,
    int? updatedAt,
  }) {
    return ApiConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKeyRef: apiKeyRef ?? this.apiKeyRef,
      modelIds: modelIds ?? this.modelIds,
      enabled: enabled ?? this.enabled,
      favorite: favorite ?? this.favorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'api_key_ref': apiKeyRef,
      'model_ids': _encodeModelIds(modelIds),
      'enabled': enabled ? 1 : 0,
      'favorite': favorite ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ApiConfig.fromMap(Map<String, Object?> map) {
    return ApiConfig(
      id: map['id'] as int?,
      name: map['name'] as String? ?? '',
      baseUrl: map['base_url'] as String? ?? '',
      apiKeyRef: map['api_key_ref'] as String? ?? '',
      modelIds: _decodeModelIds(map['model_ids'] as String?),
      enabled: (map['enabled'] as int? ?? 1) == 1,
      favorite: (map['favorite'] as int? ?? 0) == 1,
      createdAt: map['created_at'] as int? ?? 0,
      updatedAt: map['updated_at'] as int? ?? 0,
    );
  }

  static String _encodeModelIds(List<String> ids) {
    // JSON 数组字符串，如 '["deepseek-chat"]'
    return '["${ids.join('","')}"]';
  }

  static List<String> _decodeModelIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final cleaned = raw.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '');
    if (cleaned.trim().isEmpty) return const [];
    return cleaned.split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}
