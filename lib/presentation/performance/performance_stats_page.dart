import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/database_provider.dart';
import '../../domain/models/message.dart';

/// R19 性能图表：展示最近请求耗时与 Token 用量统计（简单柱状图）。
///
/// 数据来源：messageRepository.listPerformanceStats —— 最近 N 条已完成的
/// 助手回复（含 duration_ms / prompt_tokens / completion_tokens /
/// cached_tokens）。旧数据缺失 duration_ms 时按「暂无」处理。
class PerformanceStatsPage extends ConsumerStatefulWidget {
  const PerformanceStatsPage({super.key, this.limit = 30});

  /// 图表采样条数（对应最近 N 条已完成助手回复）。
  final int limit;

  @override
  ConsumerState<PerformanceStatsPage> createState() =>
      _PerformanceStatsPageState();
}

class _PerformanceStatsPageState extends ConsumerState<PerformanceStatsPage> {
  List<ChatMessage> _stats = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo =
          ref.read(appDatabaseProvider).messageRepository;
      final stats = await repo.listPerformanceStats(limit: widget.limit);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('性能图表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(context)
              : _stats.isEmpty
                  ? _buildEmpty(context)
                  : _buildContent(context),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 8),
            Text(_error ?? ''),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart,
                size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 8),
            const Text(
              '暂无统计数据\n完成至少一次对话后，这里会展示最近请求的耗时与 Token 用量',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final durations = _stats
        .map((m) => m.durationMs)
        .whereType<int>()
        .toList()
        .reversed
        .toList();
    final tokens = _stats.reversed.map((m) => m).toList();

    final avgDuration = durations.isEmpty
        ? null
        : durations.reduce((a, b) => a + b) / durations.length;
    final totalTokens = tokens.fold<int>(
      0,
      (sum, m) =>
          sum +
          (m.promptTokens ?? 0) +
          (m.completionTokens ?? 0) +
          (m.cachedTokens ?? 0),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // 概要统计卡
        Row(
          children: [
            Expanded(
              child: _StatCard(
                label: '统计请求数',
                value: '${_stats.length}',
                icon: Icons.message,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: '平均耗时',
                value: avgDuration == null ? '—' : '${avgDuration.round()} ms',
                icon: Icons.timer_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _StatCard(
                label: '总 Token',
                value: '$totalTokens',
                icon: Icons.data_usage,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('最近 ${durations.length} 次请求耗时（ms）',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _BarChart(
          values: durations,
          labelBuilder: (v) => '$v',
          emptyHint: '暂无耗时数据（旧记录未记录耗时）',
        ),
        const SizedBox(height: 24),
        Text('最近 ${tokens.length} 次 Token 用量',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _BarChart(
          values: tokens
              .map((m) =>
                  (m.promptTokens ?? 0) +
                  (m.completionTokens ?? 0) +
                  (m.cachedTokens ?? 0))
              .toList(),
          labelBuilder: (v) => '$v',
          emptyHint: '暂无 Token 数据',
          maxLabel: 'max: ${tokens.map((m) => (m.promptTokens ?? 0) + (m.completionTokens ?? 0) + (m.cachedTokens ?? 0)).reduce((a, b) => a > b ? a : b)}',
        ),
        const SizedBox(height: 12),
        Text(
          '说明：图表展示最近 ${widget.limit} 条已完成的助手回复；'
          '耗时单位为毫秒，Token 为提示词 + 生成 + 缓存用量合计。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

/// 概要统计小卡片。
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}

/// 简易柱状图：横向滚动展示最多 30 根柱子，高度按最大值归一化。
class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.values,
    required this.labelBuilder,
    this.emptyHint = '暂无数据',
    this.maxLabel,
  });

  final List<int> values;
  final String Function(int value) labelBuilder;
  final String emptyHint;
  final String? maxLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (values.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          emptyHint,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      );
    }
    final max = values.reduce((a, b) => a > b ? a : b);
    final maxDisplay = max <= 0 ? 1 : max;
    final shown = values.length > 30
        ? values.sublist(values.length - 30)
        : values;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in shown)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labelBuilder(v),
                    style: const TextStyle(fontSize: 10),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 18,
                    height: (v / maxDisplay * 120).clamp(2.0, 120.0),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(217),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(3)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('·', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          if (maxLabel != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                maxLabel!,
                style: TextStyle(
                    fontSize: 10, color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
