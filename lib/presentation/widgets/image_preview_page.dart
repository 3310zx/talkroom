import 'dart:convert';

import 'package:flutter/material.dart';

/// 图片全屏预览页（PRD 2.4 / R5）：
///
/// - 消息内图片点击后全屏打开，黑色背景、支持双指/双击缩放平移；
/// - 支持网络图片（[url]）与本地附件图片（[base64Data]，不含 data: 前缀）；
/// - 点击空白区域或左上角关闭按钮退出。
class ImagePreviewPage extends StatelessWidget {
  const ImagePreviewPage({super.key, this.url, this.base64Data, this.title});

  /// 网络图片地址（Markdown 图片链接）。
  final String? url;

  /// 本地附件图片 Base64 数据（不含 `data:` 前缀）。
  final String? base64Data;

  /// 预览标题（如文件名），为空不显示。
  final String? title;

  @override
  Widget build(BuildContext context) {
    // M5：按数据来源分支构造 Image；cacheWidth 仅存在专有构造上，
    // 统一按屏幕宽度降采样解码，避免全尺寸解码超大图 OOM。
    final Widget? imageWidget;
    if (base64Data != null && base64Data!.isNotEmpty) {
      imageWidget = Image.memory(
        base64Decode(base64Data!),
        fit: BoxFit.contain,
        cacheWidth: _decodeTargetWidth(context),
        errorBuilder: (_, __, ___) => const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 56),
            SizedBox(height: 12),
            Text('图片加载失败', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    } else if (url != null && url!.isNotEmpty) {
      imageWidget = Image.network(
        url!,
        fit: BoxFit.contain,
        cacheWidth: _decodeTargetWidth(context),
        errorBuilder: (_, __, ___) => const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined,
                color: Colors.white54, size: 56),
            SizedBox(height: 12),
            Text('图片加载失败', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    } else {
      imageWidget = null;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: title == null
            ? null
            : Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          tooltip: '关闭预览',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: GestureDetector(
        // 点击空白区域关闭（R5：全屏可关闭）。
        onTap: () => Navigator.of(context).pop(),
        child: Center(
          child: imageWidget == null
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: Colors.white54, size: 56),
                    SizedBox(height: 12),
                    Text('图片无法加载', style: TextStyle(color: Colors.white70)),
                  ],
                )
              : InteractiveViewer(maxScale: 6, child: imageWidget),
        ),
      ),
    );
  }

  /// M5：解码目标宽度 = 屏幕物理像素宽，作为 Image 降采样上限。
  /// 超过该宽度的原图在解码阶段即被缩小，内存占用大幅下降。
  int _decodeTargetWidth(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return (size.width * dpr).round().clamp(512, 4096);
  }
}
