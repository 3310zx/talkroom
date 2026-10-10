import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';

/// R21 关于页：版本号、更新日志、开源信息与 GitHub Releases 跳转。
///
/// 入口：设置页「关于」区段、macOS 菜单「关于 LLM Chat」。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String _repoUrl = 'https://github.com/3310zx/talkroom';

  static const String _releaseUrl = '$_repoUrl/releases/latest';

  /// 内置更新日志（中文）：最新版本在前，历史版本简列。
  static const List<({String version, String notes})> kChangelog = [
    (
      version: 'v1.2.17',
      notes:
          '修复：暗色模式下提示文字对比度过低不可读；性能图表 no such column: '
          'duration_ms（数据库 v11 迁移）；手机端会话长按编辑菜单与桌面端一致。',
    ),
    (
      version: 'v1.2.16',
      notes:
          '新增：跨会话消息搜索支持标题命中；会话导出 Markdown/PDF（桌面端可选保存目录）；'
          '启动直达新会话；请求耗时与 Token 用量性能图表；关于页；模型服务商收藏置顶。',
    ),
    (
      version: 'v1.2.15',
      notes: '会话列表长按/右键菜单：置顶、重命名、默认模板、归档、删除。',
    ),
    (
      version: 'v1.2.14',
      notes: '局域网双端同步、主动消息、增量备份等基础设施完善。',
    ),
    (
      version: 'v1.2.0',
      notes: '自适应界面：宽屏双栏/三栏布局、移动端底部导航。',
    ),
    (
      version: 'v1.0.0',
      notes: '首个版本：OpenAI 兼容 API 对话、多服务商配置、会话与全文搜索、PDF 导出。',
    ),
  ];

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // 打不开链接时静默失败，桌面端一般由系统浏览器接管。
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        children: [
          // 应用标识
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF07C160),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.chat_bubble, color: Colors.white, size: 40),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              AppConstants.appName,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '版本 ${AppConstants.appVersion}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '跨平台第三方 LLM 对话客户端\nmacOS / Android / Web',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 24),
          // 版本与更新日志
          _sectionTitle(context, '更新日志'),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in kChangelog) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.version,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.notes,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (item != kChangelog.last)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 开源信息
          _sectionTitle(context, '开源信息'),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.code),
              title: const Text('GitHub 仓库'),
              subtitle: const Text('3310zx/talkroom\n基于 Flutter 开源生态构建，欢迎 Star 与反馈'),
              isThreeLine: true,
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launch(_repoUrl),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.update),
              title: const Text('版本发布页'),
              subtitle: const Text('查看 Releases 与安装包（APK / macOS dmg）'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => _launch(_releaseUrl),
            ),
          ),
          const SizedBox(height: 24),
          // 跳转按钮
          FilledButton.icon(
            onPressed: () => _launch(_releaseUrl),
            icon: const Icon(Icons.download),
            label: const Text('前往 GitHub Releases 下载'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.bold),
    );
  }
}
