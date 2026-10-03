import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/database_provider.dart';
import '../../domain/models/message.dart';

/// 命中缓存页（设置 → 命中缓存）。
///
/// 展示历史请求的缓存命中记录：时间、模型、缓存命中 token、总 token、
/// 命中率；点击条目查看详情；支持清空全部记录（仅清 cache_hits 表，
/// 不影响聊天历史）。
class CacheHitsPage extends ConsumerStatefulWidget {
  const CacheHitsPage({super.key});

  @override
  ConsumerState<CacheHitsPage> createState() => _CacheHitsPageState();
}

class _CacheHitsPageState extends ConsumerState<CacheHitsPage> {
  List<CacheHitRecord> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo =
        ref.read(appDatabaseProvider).messageRepository;
    final records = await repo.listCacheHits();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空命中缓存记录'),
        content: const Text('将删除全部缓存命中记录（仅影响该记录列表，不会删除聊天消息）。确定继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(appDatabaseProvider).messageRepository.clearCacheHits();
    if (!mounted) return;
    setState(() => _records = const []);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已清空命中缓存记录')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('命中缓存'),
        actions: [
          if (!_loading && _records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清空记录',
              onPressed: _clear,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(child: Text('暂无缓存命中记录'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _records.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) {
                    final record = _records[index];
                    return _CacheHitTile(
                      record: record,
                      onTap: () => _showDetail(record),
                    );
                  },
                ),
    );
  }

  void _showDetail(CacheHitRecord record) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('缓存命中详情'),
        content: _DetailRows(record: record),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _CacheHitTile extends StatelessWidget {
  const _CacheHitTile({required this.record, required this.onTap});

  final CacheHitRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hitRate = record.hitRate;
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(
          Icons.speed,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(
        record.modelId == null || record.modelId!.isEmpty
            ? '未知模型'
            : record.modelId!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatTime(record.createdAt)),
          const SizedBox(height: 2),
          Text(
            hitRate == null
                ? '缓存 ${record.cachedTokens} tokens（命中率未知）'
                : '命中 ${record.cachedTokens} / ${record.promptTokens} tokens'
                    ' · ${(hitRate * 100).toStringAsFixed(1)}%',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.record});

  final CacheHitRecord record;

  @override
  Widget build(BuildContext context) {
    final total = (record.promptTokens ?? 0) + (record.completionTokens ?? 0);
    final rows = <(String, String)>[
      ('时间', _formatTime(record.createdAt)),
      ('模型', record.modelId == null || record.modelId!.isEmpty
          ? '未知模型'
          : record.modelId!),
      ('缓存命中 token', record.cachedTokens.toString()),
      ('Prompt token', record.promptTokens?.toString() ?? '未知'),
      ('Completion token', record.completionTokens?.toString() ?? '未知'),
      ('总 token', record.promptTokens == null ? '未知' : total.toString()),
      (
        '命中率',
        record.hitRate == null
            ? '未知（无 prompt_tokens）'
            : '${(record.hitRate! * 100).toStringAsFixed(1)}%',
      ),
    ];
    return SingleChildScrollView(
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 时间格式化：MM-dd HH:mm（跨年时带年份）。
String _formatTime(int millis) {
  final dt = DateTime.fromMillisecondsSinceEpoch(millis);
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(dt.hour)}:${two(dt.minute)}';
  if (dt.year == now.year) {
    return '${two(dt.month)}-${two(dt.day)} $hm';
  }
  return '${dt.year}-${two(dt.month)}-${two(dt.day)} $hm';
}
