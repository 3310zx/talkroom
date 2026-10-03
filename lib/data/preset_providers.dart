/// 预设服务商清单（独立数据文件，不依赖 UI 层）。
///
/// 用于「添加服务商」时快速填充接口地址与常用模型，用户只需填写
/// API Key 即可使用。数据只读，不会写入 SQLite；真实配置仍由用户
/// 在 [ApiConfigDetailPage] 中确认后通过 [apiConfigsProvider] 保存。
///
/// 字段说明：
/// - [name]：服务商名称（也用于 UI 徽标首字母）。
/// - [baseUrl]：OpenAI 兼容接口地址，选中预设后自动填充。
/// - [modelIds]：常用模型 ID，选中预设后作为默认模型列表（可再编辑）。
/// - [requiresApiKey]：是否需要 API Key；false 表示本地/免密钥服务。
/// - [brandColorArgb]：品牌色 ARGB 整数值，UI 层转为 [Color]。
class PresetProvider {
  final String name;
  final String baseUrl;
  final List<String> modelIds;
  final bool requiresApiKey;
  final int brandColorArgb;

  const PresetProvider({
    required this.name,
    required this.baseUrl,
    required this.modelIds,
    required this.requiresApiKey,
    required this.brandColorArgb,
  });
}

/// 内置预设服务商清单（按任务给定数据）。
const List<PresetProvider> presetProviders = [
  PresetProvider(
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    modelIds: ['gpt-4o', 'gpt-4o-mini', 'gpt-4.1', 'gpt-4.1-mini', 'o3-mini'],
    requiresApiKey: true,
    brandColorArgb: 0xFF10A37F, // OpenAI 绿
  ),
  PresetProvider(
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com/v1',
    modelIds: ['deepseek-chat', 'deepseek-reasoner'],
    requiresApiKey: true,
    brandColorArgb: 0xFF4D6BFE, // DeepSeek 蓝紫
  ),
  PresetProvider(
    name: 'SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    modelIds: [
      'deepseek-ai/DeepSeek-V3',
      'Qwen/Qwen2.5-72B-Instruct',
      'THUDM/GLM-4-9B-Chat',
      'meta-llama/Llama-3.3-70B-Instruct',
    ],
    requiresApiKey: true,
    brandColorArgb: 0xFF00A8E8, // 硅基流动天蓝
  ),
  PresetProvider(
    name: 'Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    modelIds: [
      'kimi-k2-0711-preview',
      'moonshot-v1-128k',
      'moonshot-v1-32k',
      'moonshot-v1-8k',
    ],
    requiresApiKey: true,
    brandColorArgb: 0xFF6C5CE7, // 月之暗面紫
  ),
  PresetProvider(
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    modelIds: ['glm-4-plus', 'glm-4-air', 'glm-4-flash'],
    requiresApiKey: true,
    brandColorArgb: 0xFF3B82F6, // 智谱蓝
  ),
  PresetProvider(
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    modelIds: ['qwen-max', 'qwen-plus', 'qwen-turbo', 'qwen-long'],
    requiresApiKey: true,
    brandColorArgb: 0xFFFF6A00, // 通义橙红
  ),
  PresetProvider(
    name: 'Ollama 本地',
    baseUrl: 'http://localhost:11434/v1',
    modelIds: ['llama3.1', 'qwen2.5', 'qwen2.5-coder', 'deepseek-r1'],
    requiresApiKey: false, // 本地服务，无需密钥
    brandColorArgb: 0xFF1E1E1E, // Ollama 黑
  ),
  PresetProvider(
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    modelIds: [
      'llama-3.3-70b-versatile',
      'llama-3.1-8b-instant',
      'mixtral-8x7b-32768',
    ],
    requiresApiKey: true,
    brandColorArgb: 0xFFF55036, // Groq 橙红
  ),
  PresetProvider(
    name: '火山方舟豆包',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    modelIds: ['doubao-pro-32k', 'doubao-pro-4k', 'doubao-lite-32k', 'doubao-lite-4k'],
    requiresApiKey: true,
    brandColorArgb: 0xFF165DFF, // 火山引擎蓝
  ),
];

/// 按名称查找预设（用于判断某服务商是否来自预设）。
PresetProvider? presetProviderByName(String name) {
  for (final p in presetProviders) {
    if (p.name == name) return p;
  }
  return null;
}
