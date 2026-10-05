import 'package:flutter/foundation.dart';

/// 参数预设（R14）：一键切换常用生成参数组合。
///
/// 预设同时用于「全局默认参数」编辑与「会话参数覆盖」编辑，
/// 选中后自动填充 temperature / max_tokens / top_p /
/// frequency_penalty / presence_penalty 五个字段。
@immutable
class ParamPreset {
  const ParamPreset({
    required this.name,
    required this.description,
    required this.temperature,
    required this.maxTokens,
    required this.topP,
    required this.frequencyPenalty,
    required this.presencePenalty,
  });

  final String name;
  final String description;
  final double temperature;
  final int maxTokens;
  final double topP;
  final double frequencyPenalty;
  final double presencePenalty;
}

/// 内置预设列表：创意 / 严谨 / 代码。
const List<ParamPreset> kParamPresets = [
  ParamPreset(
    name: '创意',
    description: '发散联想，适合头脑风暴、故事写作',
    temperature: 1.0,
    maxTokens: 4096,
    topP: 0.95,
    frequencyPenalty: 0.0,
    presencePenalty: 0.6,
  ),
  ParamPreset(
    name: '严谨',
    description: '稳定聚焦，适合事实问答、分析总结',
    temperature: 0.2,
    maxTokens: 2048,
    topP: 0.6,
    frequencyPenalty: 0.5,
    presencePenalty: 0.0,
  ),
  ParamPreset(
    name: '代码',
    description: '精确输出，适合代码生成与调试',
    temperature: 0.1,
    maxTokens: 4096,
    topP: 0.5,
    frequencyPenalty: 0.3,
    presencePenalty: 0.0,
  ),
];
