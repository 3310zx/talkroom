import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/database_provider.dart';
import '../../core/param_presets.dart';
import '../../domain/models/conversation.dart';

/// 会话参数编辑页（R14：每个会话可单独覆盖全局默认参数）。
///
/// 支持 temperature / max_tokens / top_p / frequency_penalty /
/// presence_penalty 五项覆盖；提供「创意 / 严谨 / 代码」参数预设一键填充；
/// 支持一键「恢复默认」清除本会话的全部参数覆盖。
class ConversationParamPage extends ConsumerStatefulWidget {
  const ConversationParamPage({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ConversationParamPage> createState() => _ConversationParamPageState();
}

class _ConversationParamPageState extends ConsumerState<ConversationParamPage> {
  late final TextEditingController _temperature;
  late final TextEditingController _maxTokens;
  late final TextEditingController _topP;
  late final TextEditingController _frequencyPenalty;
  late final TextEditingController _presencePenalty;
  String _selectedPresetName = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _temperature = TextEditingController(text: _fmt(widget.conversation.temperature));
    _maxTokens = TextEditingController(text: widget.conversation.maxTokens?.toString() ?? '');
    _topP = TextEditingController(text: _fmt(widget.conversation.topP));
    _frequencyPenalty = TextEditingController(text: _fmt(widget.conversation.frequencyPenalty));
    _presencePenalty = TextEditingController(text: _fmt(widget.conversation.presencePenalty));
  }

  @override
  void dispose() {
    _temperature.dispose();
    _maxTokens.dispose();
    _topP.dispose();
    _frequencyPenalty.dispose();
    _presencePenalty.dispose();
    super.dispose();
  }

  String _fmt(double? v) => v == null ? '' : v.toString();

  void _applyPreset(ParamPreset preset) {
    setState(() {
      _selectedPresetName = preset.name;
      _temperature.text = preset.temperature.toString();
      _maxTokens.text = preset.maxTokens.toString();
      _topP.text = preset.topP.toString();
      _frequencyPenalty.text = preset.frequencyPenalty.toString();
      _presencePenalty.text = preset.presencePenalty.toString();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final repo = ref.read(appDatabaseProvider).conversationRepository;
      await repo.update(Conversation(
        id: widget.conversation.id,
        title: widget.conversation.title,
        apiConfigId: widget.conversation.apiConfigId,
        modelId: widget.conversation.modelId,
        systemPrompt: widget.conversation.systemPrompt,
        temperature: _parseDouble(_temperature.text),
        maxTokens: _parseInt(_maxTokens.text),
        topP: _parseDouble(_topP.text),
        frequencyPenalty: _parseDouble(_frequencyPenalty.text),
        presencePenalty: _parseDouble(_presencePenalty.text),
        pinned: widget.conversation.pinned,
        archived: widget.conversation.archived,
        promptTemplateId: widget.conversation.promptTemplateId,
        lastMessage: widget.conversation.lastMessage,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        createdAt: widget.conversation.createdAt,
      ));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetOverrides() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认'),
        content: const Text('将清除本会话的全部参数覆盖，改用全局默认参数。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final repo = ref.read(appDatabaseProvider).conversationRepository;
    await repo.update(widget.conversation.clearedParamOverrides());
    if (mounted) Navigator.of(context).pop(true);
  }

  double? _parseDouble(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  int? _parseInt(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('会话参数')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '参数覆盖仅对本会话生效；留空表示使用全局默认值。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          // 参数预设一键切换（R14）。
          Text('参数预设', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final preset in kParamPresets)
                ChoiceChip(
                  label: Text(preset.name),
                  selected: _selectedPresetName == preset.name,
                  onSelected: (_) => _applyPreset(preset),
                  tooltip: preset.description,
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (_selectedPresetName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                kParamPresets
                    .firstWhere((p) => p.name == _selectedPresetName)
                    .description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          const Divider(height: 24),
          _field('temperature', '随机性（越高越发散）', _temperature,
              keyboard: TextInputType.numberWithOptions(decimal: true)),
          _field('max_tokens', '最大输出长度', _maxTokens,
              keyboard: TextInputType.number),
          _field('top_p', '核采样', _topP,
              keyboard: TextInputType.numberWithOptions(decimal: true)),
          _field('frequency_penalty', '频率惩罚（抑制重复，-2~2）',
              _frequencyPenalty,
              keyboard: TextInputType.numberWithOptions(decimal: true, signed: true)),
          _field('presence_penalty', '存在惩罚（鼓励新话题，-2~2）',
              _presencePenalty,
              keyboard: TextInputType.numberWithOptions(decimal: true, signed: true)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _resetOverrides,
                  icon: const Icon(Icons.restore),
                  label: const Text('恢复默认'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.check),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    String hint,
    TextEditingController controller, {
    required TextInputType keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
