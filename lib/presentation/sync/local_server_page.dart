import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../application/providers/database_provider.dart';
import '../../application/providers/local_server_provider.dart';
import '../../application/providers/settings_provider.dart';
import '../../application/providers/sync_provider.dart';
import '../../core/constants.dart';

/// 本地服务器管理页（PRD 第 7 章，电脑端）。
///
/// 显示运行状态、端口、局域网 IP（多网卡列表）、二维码占位、配对码、
/// 已配对设备列表（可移除）、自动启动开关。
class LocalServerPage extends ConsumerStatefulWidget {
  const LocalServerPage({super.key});

  @override
  ConsumerState<LocalServerPage> createState() => _LocalServerPageState();
}

class _LocalServerPageState extends ConsumerState<LocalServerPage> {
  bool _starting = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(localServerStatusProvider);
    final autoStart =
        ref.watch(settingsProvider)[AppConstants.settingServerAutoStart] == '1';

    return Scaffold(
      appBar: AppBar(title: const Text('本地服务器')),
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _statusHeader(status),
            const SizedBox(height: 16),
            if (status == null)
              FilledButton.icon(
                onPressed: _starting ? null : _startServer,
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(_starting ? '启动中...' : '启动服务器'),
              )
            else
              OutlinedButton.icon(
                onPressed: _stopServer,
                icon: const Icon(Icons.stop),
                label: const Text('停止服务器'),
              ),
            const SizedBox(height: 16),
            SwitchListTile(
              secondary: const Icon(Icons.power_settings_new),
              title: const Text('应用启动时自动拉起服务器'),
              subtitle: const Text('电脑端有效；首次开启会引导配置'),
              value: autoStart,
              onChanged: (v) async {
                await ref.read(settingsProvider.notifier).set(
                    AppConstants.settingServerAutoStart, v ? '1' : '0');
                if (v) await _startServer();
              },
            ),
            const Divider(),
            _section('配对信息'),
            _pairInfoTile(status),
            const Divider(),
            _section('局域网地址'),
            _lanIpsTile(status),
            const Divider(),
            _section('扫码连接'),
            _qrCard(status),
            const Divider(),
            // R15：实时同步状态与冲突提示（服务端同样参与合并，可检测冲突）。
            _section('同步状态'),
            const _SyncStatusCard(),
            const Divider(),
            _section('已配对设备'),
            const _PairedDevicesList(),
          ],
        ),
      ),
    );
  }

  Widget _statusHeader(dynamic status) {
    if (status == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.dns_outlined, size: 40),
          title: Text('服务器未启动'),
          subtitle: Text('启动后手机可在同一局域网内连接并同步'),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.dns, size: 40, color: Colors.green),
        title: Text('运行中 · 端口 ${status.port}'),
        subtitle: Text(
          '启动时间：${status.startedAt?.toLocal() ?? '--'}'
          '\n已配对设备：${status.pairedDevices} 台'
          '${status.pairLocked ? '\n⚠️ 配对码已锁定（错误次数过多）' : ''}',
        ),
      ),
    );
  }

  Widget _pairInfoTile(dynamic status) {
    final pairCode = status?.pairCode;
    final locked = status?.pairLocked == true;
    final remainingMs = status?.pairRemainingLockMs ?? 0;
    final serverDeviceId = status?.serverDeviceId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.password),
                const SizedBox(width: 8),
                Text(
                  pairCode == null || pairCode.isEmpty
                      ? '未生成配对码'
                      : '配对码：${pairCode[0]} ${pairCode[1]} ${pairCode[2]} ${pairCode[3]} ${pairCode[4]} ${pairCode[5]}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        letterSpacing: 4,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (locked)
              Text(
                '已锁定，剩余 ${(remainingMs / 60000).ceil()} 分钟解锁',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (pairCode != null && pairCode.isNotEmpty)
              const Text('配对码一次性有效，配对成功后自动失效'),
            if (serverDeviceId != null && serverDeviceId.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '服务器设备 ID：$serverDeviceId',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: status == null ? null : _regeneratePairCode,
                  child: const Text('重新生成配对码'),
                ),
                if (status != null)
                  TextButton(
                    onPressed: _copyPairCode,
                    child: const Text('复制配对码'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lanIpsTile(dynamic status) {
    final ips = status?.lanIps as List<String>? ?? const <String>[];
    if (ips.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.wifi_off),
          title: Text('未检测到局域网 IP'),
          subtitle: Text('请确认电脑已连接 Wi-Fi / 以太网'),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (final ip in ips)
            ListTile(
              leading: const Icon(Icons.lan_outlined),
              title: Text(ip),
              subtitle: Text('http://$ip:${status?.port ?? '--'}'),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                tooltip: '复制地址',
                onPressed: () => _copyText('http://$ip:${status?.port ?? ''}'),
              ),
            ),
        ],
      ),
    );
  }

  /// R15：扫码连接卡片。展示真实配对二维码（talkroom://pair 约定格式，
  /// 与手机端 ScanPairPage 解析逻辑一致），供手机「扫码配对」直接扫描。
  Widget _qrCard(dynamic status) {
    final ips = status?.lanIps as List<String>? ?? const <String>[];
    final code = status?.pairCode;
    final port = status?.port;
    if (status == null || code == null || code.isEmpty || ips.isEmpty || port == null) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.qr_code_2),
          title: Text('扫码连接'),
          subtitle: Text('启动服务器并生成配对码后，可展示配对二维码供手机扫码'),
        ),
      );
    }
    final payload = 'talkroom://pair?host=${ips.first}&port=$port&code=$code';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: QrImageView(
                data: payload,
                version: QrVersions.auto,
                size: 164,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square),
                dataModuleStyle:
                    const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square),
              ),
            ),
            const SizedBox(height: 12),
            const Text('手机端点击「扫码配对」扫描此二维码，即可自动填入 IP、端口与配对码'),
            const SizedBox(height: 8),
            Text(
              'http://${ips.first}:$port',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  Future<void> _startServer() async {
    setState(() => _starting = true);
    final service = ref.read(localServerServiceProvider);
    try {
      final settings = ref.read(settingsProvider);
      final lastPort =
          int.tryParse(settings[AppConstants.settingServerLastPort] ?? '') ??
              AppConstants.defaultServerPort;
      final port = await service.probePort(startPort: lastPort);
      await service.start(port: port);
      final ips = await service.getLanIpv4Addresses();
      final info = await service.pairInfo();
      await ref.read(settingsProvider.notifier)
          .set(AppConstants.settingServerLastPort, '$port');
      ref.read(localServerStatusProvider.notifier).state = LocalServerState(
        port: port,
        lanIps: ips,
        startedAt: DateTime.now(),
        pairCode: info['pair_code_set'] == true
            ? await service.getPairCode()
            : await service.ensurePairCode(),
        serverDeviceId: info['server_device_id'] as String?,
        pairedDevices: info['paired_devices'] as int? ?? 0,
        pairLocked: info['pair_locked'] == true,
        pairRemainingLockMs: info['pair_remaining_lock_ms'] as int? ?? 0,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '服务器已启动：${ips.isEmpty ? '0.0.0.0' : ips.first}:$port'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('启动失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopServer() async {
    await ref.read(localServerServiceProvider).stop();
    ref.read(localServerStatusProvider.notifier).state = null;
  }

  Future<void> _regeneratePairCode() async {
    final service = ref.read(localServerServiceProvider);
    final code = await service.ensurePairCode();
    final info = await service.pairInfo();
    ref.read(localServerStatusProvider.notifier).state =
        ref.read(localServerStatusProvider.notifier).state?.copyWith(
              pairCode: code,
              pairLocked: false,
              pairRemainingLockMs: 0,
              pairedDevices: info['paired_devices'] as int? ?? 0,
            );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('新配对码已生成：$code')));
  }

  Future<void> _copyPairCode() async {
    final status = ref.read(localServerStatusProvider.notifier).state;
    final code = status?.pairCode;
    if (code == null || code.isEmpty) return;
    await _copyText(code);
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已复制')));
  }

  Future<void> _refreshStatus() async {
    final service = ref.read(localServerServiceProvider);
    final status = ref.read(localServerStatusProvider.notifier).state;
    if (status == null) return;
    final info = await service.pairInfo();
    ref.read(localServerStatusProvider.notifier).state = status.copyWith(
      pairCode: await service.getPairCode(),
      serverDeviceId: info['server_device_id'] as String?,
      pairedDevices: info['paired_devices'] as int? ?? 0,
      pairLocked: info['pair_locked'] == true,
      pairRemainingLockMs: info['pair_remaining_lock_ms'] as int? ?? 0,
    );
    ref.invalidate(localServerDevicesProvider);
  }
}

/// 已配对设备列表（可移除）。
class _PairedDevicesList extends ConsumerWidget {
  const _PairedDevicesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(localServerDevicesProvider);
    return devices.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text('加载失败：$e'),
      ),
      data: (list) {
        if (list.isEmpty) {
          return const Card(
            child: ListTile(
              leading: Icon(Icons.devices_other),
              title: Text('暂无已配对设备'),
              subtitle: Text('手机端连接配置页输入配对码即可加入'),
            ),
          );
        }
        return Column(
          children: [
            for (final device in list)
              ListTile(
                leading: Icon(
                  device.deviceType == 'server'
                      ? Icons.desktop_windows
                      : Icons.smartphone,
                ),
                title: Text(device.deviceName),
                subtitle: Text(
                  '${device.deviceType} · 最后活跃 '
                  '${_formatTime(device.lastSeenAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.person_remove_outlined),
                  tooltip: '移除设备',
                  onPressed: () => _removeDevice(ref, device.deviceId),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatTime(int ms) {
    if (ms <= 0) return '未知';
    return DateTime.fromMillisecondsSinceEpoch(ms).toLocal().toString().substring(0, 19);
  }

  Future<void> _removeDevice(WidgetRef ref, String deviceId) async {
    final db = ref.read(appDatabaseProvider);
    await db.deviceRepository.removeByDeviceId(deviceId);
    ref.invalidate(localServerDevicesProvider);
  }
}

/// R15：实时同步状态卡片（电脑端「本地服务器」页）。
///
/// 展示本机作为权威源的连接状态、最后同步时间与双端写冲突提示；
/// 冲突提示与服务端合并逻辑联动（检测到覆盖即上报）。
class _SyncStatusCard extends ConsumerWidget {
  const _SyncStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncStatusProvider);
    final color = sync.connected
        ? Colors.green
        : (sync.enabled ? Colors.orange : Colors.grey);
    final lastSync = sync.lastSyncAtMs;
    final lastSyncText = lastSync == null
        ? '从未同步'
        : '最后同步：${DateTime.fromMillisecondsSinceEpoch(lastSync).toLocal()}';
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
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
          if (sync.pendingConflicts > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.deepOrange, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      sync.lastConflictText ?? '检测到双端写冲突，已按规则合并',
                      style: const TextStyle(color: Colors.deepOrange, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
