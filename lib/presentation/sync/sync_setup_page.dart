import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers/settings_provider.dart';
import '../../application/providers/sync_provider.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import 'scan_pair_page.dart';

/// 客户端连接配置页（PRD 第 7 章 7.3）。
///
/// 输入电脑局域网 IP / 端口 / 6 位配对码完成配对；展示连接状态。
class SyncSetupPage extends ConsumerStatefulWidget {
  const SyncSetupPage({super.key});

  @override
  ConsumerState<SyncSetupPage> createState() => _SyncSetupPageState();
}

class _SyncSetupPageState extends ConsumerState<SyncSetupPage> {
  final _hostCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _pairing = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _hostCtrl.text = settings[AppConstants.settingSyncHost] ?? '';
    _portCtrl.text =
        settings[AppConstants.settingSyncPort] ?? '${AppConstants.defaultServerPort}';
    _nameCtrl.text = settings[AppConstants.settingLocalDeviceName] ?? '我的手机';
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  /// R15：扫码配对入口，进入相机扫码页。
  void _scanPair() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScanPairPage()),
    );
  }

  Future<void> _pair() async {
    final host = _hostCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim());
    final code = _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (host.isEmpty || port == null) {
      _toast('请填写电脑局域网 IP 与端口');
      return;
    }
    if (code.length != AppConstants.pairCodeLength) {
      _toast('配对码需为 ${AppConstants.pairCodeLength} 位数字');
      return;
    }
    setState(() => _pairing = true);
    final engine = ref.read(syncEngineProvider);
    final (ok, message) = await engine.pair(
      host: host,
      port: port,
      pairCode: code,
      deviceName: name.isEmpty ? '我的手机' : name,
    );
    if (!mounted) return;
    setState(() => _pairing = false);
    await ref.read(settingsProvider.notifier).load();
    ref.read(syncStatusProvider.notifier).setEnabled(ok);
    ref.read(syncStatusProvider.notifier).setError(ok ? null : message);
    _toast(message);
    if (ok) {
      _codeCtrl.clear();
    }
  }

  Future<void> _disableSync() async {
    await ref.read(syncEngineProvider).stop();
    await ref.read(settingsProvider.notifier).set(AppConstants.settingSyncEnabled, '0');
    ref.read(syncStatusProvider.notifier).setEnabled(false);
    ref.read(syncStatusProvider.notifier).setConnected(false);
    if (!mounted) return;
    _toast('已关闭局域网同步');
  }

  void _toast(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('局域网同步')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(sync),
          const SizedBox(height: 16),
          TextField(
            controller: _hostCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '电脑局域网 IP',
              hintText: '如 192.168.1.100',
              prefixIcon: Icon(Icons.lan_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '端口',
              hintText: '默认 8787',
              prefixIcon: Icon(Icons.numbers),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            maxLength: AppConstants.pairCodeLength,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '配对码（6 位数字）',
              hintText: '在电脑端「本地服务器」页查看',
              prefixIcon: Icon(Icons.password),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '设备名称',
              hintText: '如 我的手机',
              prefixIcon: Icon(Icons.smartphone),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          // R15：扫码配对入口。
          FilledButton.tonalIcon(
            onPressed: _scanPair,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('扫码配对（扫描电脑端二维码）'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _pairing ? null : _pair,
            icon: _pairing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.link),
            label: Text(_pairing ? '配对中...' : '手动输入并配对'),
          ),
          if (sync.enabled) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _disableSync,
              icon: const Icon(Icons.link_off),
              label: const Text('关闭同步'),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            '使用说明：\n'
            '1. 在电脑端设置 → 本地服务器中启动服务器，展示配对二维码与配对码；\n'
            '2. 手机与本机处于同一局域网，推荐点击「扫码配对」直接扫描二维码；\n'
            '3. 也可手动输入电脑 IP、端口与 6 位配对码完成配对；\n'
            '4. 配对成功后消息自动双向同步，电脑为权威源；\n'
            '5. 双端同时修改同一条消息时按「电脑优先」规则合并，并在状态卡提示冲突。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _statusCard(SyncState sync) {
    final color = sync.connected
        ? Colors.green
        : (sync.enabled ? Colors.orange : Colors.grey);
    final lastSync = sync.lastSyncAtMs;
    final lastSyncText = lastSync == null
        ? '从未同步'
        : '最后同步：${DateTime.fromMillisecondsSinceEpoch(lastSync).toLocal()}';
    return Card(
      child: ListTile(
        leading: Icon(
          sync.connected ? Icons.cloud_done : Icons.cloud_queue,
          color: color,
          size: 36,
        ),
        title: Text(sync.enabled
            ? (sync.connected ? '已连接' : '已配对，等待连接')
            : '未配对'),
        subtitle: Text(
          '${sync.host.isEmpty ? '--' : sync.host}:${sync.port == 0 ? '--' : sync.port}\n'
          '$lastSyncText${sync.lastError == null ? '' : '\n${sync.lastError}'}',
        ),
      ),
    );
  }
}
