import 'package:dio/dio.dart';

import '../core/constants.dart';

/// GitHub Release 信息（从 releases/latest 接口解析）。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.name,
    required this.body,
    this.apkUrl,
  });

  /// 最新版本号（GitHub tag_name，如 v1.0.9）
  final String version;
  /// Release 名称
  final String name;
  /// 更新说明（Markdown 原文）
  final String body;
  /// APK 资产下载链接（assets 中第一个 .apk 的 browser_download_url，可为空）
  final String? apkUrl;
}

/// 检查更新服务：通过 GitHub Releases API 拉取最新版本并与当前版本比对。
///
/// 仓库按公开仓库匿名访问实现（无需 Token）；私有仓库场景需配置
/// Authorization 头，当前按全局任务约定（3310zx/talkroom 公开可读）处理。
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// GitHub Releases API 的最新 Release 地址
  static const String githubRepo = '3310zx/talkroom';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  /// 拉取最新 Release 信息；非 2xx 或解析失败抛 [DioException]/[FormatException]。
  Future<UpdateInfo> fetchLatestRelease() async {
    final response = await _dio.get<dynamic>(
      latestReleaseUrl,
      options: Options(
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'talkroom-update-check',
        },
      ),
    );
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const FormatException('GitHub 返回的数据格式异常');
    }
    final tag = data['tag_name'];
    if (tag is! String || tag.isEmpty) {
      throw const FormatException('Release 缺少 tag_name');
    }
    String? apkUrl;
    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = asset['name'];
          final url = asset['browser_download_url'];
          if (name is String &&
              name.toLowerCase().endsWith('.apk') &&
              url is String) {
            apkUrl = url;
            break;
          }
        }
      }
    }
    return UpdateInfo(
      version: tag,
      name: (data['name'] is String && (data['name'] as String).isNotEmpty)
          ? data['name'] as String
          : tag,
      body: (data['body'] is String ? data['body'] as String : '').trim(),
      apkUrl: apkUrl,
    );
  }

  /// 当前应用版本号（来自 AppConstants.appVersion，与 pubspec version 保持一致）。
  static Future<String> currentVersion() async => AppConstants.appVersion;

  /// 语义化版本比较：a > b 返回正数，相等返回 0，a < b 返回负数。
  /// 兼容 "v1.0.9" / "1.0.9" / "1.0" 等写法；非数字段按 0 处理。
  static int compareVersions(String a, String b) {
    final pa = _parts(a);
    final pb = _parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static List<int> _parts(String version) {
    return version
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('.')
        .map((s) => int.tryParse(s.trim()) ?? 0)
        .toList();
  }
}
