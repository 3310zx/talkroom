import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/utils.dart';

/// 扫码配对页（R15，v1.0.15）。
///
/// 扫描电脑端「本地服务器」页展示的配对二维码，自动解析出
/// 局域网 IP、端口与配对码，返回给连接配置页填充表单。
class ScanPairPage extends StatefulWidget {
  const ScanPairPage({super.key});

  @override
  State<ScanPairPage> createState() => _ScanPairPageState();
}

class _ScanPairPageState extends State<ScanPairPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue ?? '')
        .where((s) => s.isNotEmpty)
        .firstOrNull;
    if (raw == null) return;

    final parsed = _parsePairUrl(raw);
    if (parsed == null) {
      _toast('未识别到配对二维码，请对准电脑端「本地服务器」页的二维码');
      return;
    }
    _handled = true;
    Navigator.of(context).pop(parsed);
  }

  /// 解析约定格式：talkroom://pair?host=192.168.1.100&port=8787&code=123456
  Map<String, String>? _parsePairUrl(String raw) {
    if (!raw.startsWith('talkroom://pair')) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final host = uri.queryParameters['host']?.trim() ?? '';
    final port = uri.queryParameters['port']?.trim() ?? '';
    final code = uri.queryParameters['code']?.trim() ?? '';
    if (host.isEmpty || port.isEmpty || code.isEmpty) return null;
    return {'host': host, 'port': port, 'code': code};
  }

  void _toast(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码配对')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '使用说明：',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text(
                  '1. 在电脑端打开「本地服务器」页，展示配对二维码；\n'
                  '2. 将二维码放入取景框，自动识别并填入 IP、端口与配对码；\n'
                  '3. 确认设备名称后点击「配对并连接」即可完成。',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
