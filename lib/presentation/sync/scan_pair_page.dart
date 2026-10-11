import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  DateTime _lastZoomAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // 问题②：mobile_scanner 5.x 在 iOS 端将摄像头预览方向固定为竖屏
    // （connection.videoOrientation = .portrait），App 若不锁定向，
    // iPad 横屏时预览与应用界面方向不匹配。进入扫码页锁定竖屏、
    // 离开时恢复，保证预览方向与界面一致（Android 端同样生效）。
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue ?? '')
        .where((s) => s.isNotEmpty)
        .firstOrNull;
    if (raw == null) {
      // 检测到二维码但内容未读出（距离远/画面太小）：自动放大镜头后重试。
      _autoZoom();
      return;
    }

    final parsed = _parsePairUrl(raw);
    if (parsed == null) {
      _toast('未识别到配对二维码，请对准电脑端「本地服务器」页的二维码');
      _autoZoom();
      return;
    }
    _handled = true;
    Navigator.of(context).pop(parsed);
  }

  /// 问题③：二维码距离较远时自动放大镜头。
  ///
  /// mobile_scanner 的 zoomScale 为 0.0~1.0 的相对变焦（1.0 为最大），
  /// 每次 +0.15 并做 350ms 节流，避免高频调用把相机变焦 API 打爆。
  Future<void> _autoZoom() async {
    final now = DateTime.now();
    if (now.difference(_lastZoomAt) < const Duration(milliseconds: 350)) return;
    _lastZoomAt = now;
    final current = _controller.value.zoomScale;
    if (current >= 0.95) return;
    await _controller.setZoomScale((current + 0.15).clamp(0.0, 1.0));
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
              // 问题④：相机打不开/权限被拒时给出明确失败提示，而非静默黑屏。
              errorBuilder: (context, error, child) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.no_photography_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        '摄像头不可用：$error',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '请检查相机权限后重试',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
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
