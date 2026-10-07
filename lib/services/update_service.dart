import 'package:dio/dio.dart';

import '../core/constants.dart';

/// 检查更新错误类型（对原始 [DioException] 分类，供 UI 友好化展示）。
enum UpdateCheckErrorType {
  /// 403 且命中 GitHub 匿名限流（X-RateLimit-Remaining=0 或响应体含限流关键词）
  rateLimited,

  /// 403 但不属于限流（被拒绝/风控等）
  forbidden,

  /// 网络连接/超时类错误
  network,

  /// 其他错误（非 2xx 状态码、解析失败、冷却期等）
  other,
}

/// 检查更新失败时抛出的分类异常；UI 按 [type] 分类展示，不再暴露原始堆栈。
class UpdateCheckException implements Exception {
  const UpdateCheckException(this.type, this.message);

  final UpdateCheckErrorType type;
  final String message;

  @override
  String toString() => message;
}

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

  /// 成功缓存：最新 Release 结果与缓存时间戳（进程内共享）。
  static UpdateInfo? _cachedInfo;
  static DateTime? _cachedAt;

  /// 上次请求发起时间（无论成败），用于失败冷却。
  static DateTime? _lastAttemptAt;

  /// 成功缓存有效期：此时间内直接返回缓存，不发起网络请求。
  static const Duration cacheTtl = Duration(minutes: 10);

  /// 失败冷却期：此时间内不重复请求，避免再次触发限流。
  static const Duration cooldown = Duration(minutes: 10);

  /// 仅测试用：清空冷却与缓存状态。
  static void resetForTest() {
    _cachedInfo = null;
    _cachedAt = null;
    _lastAttemptAt = null;
  }

  /// GitHub Releases API 的最新 Release 地址
  static const String githubRepo = '3310zx/talkroom';
  static const String latestReleaseUrl =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  /// 拉取最新 Release 信息。
  ///
  /// - 成功结果在 [cacheTtl] 分钟内直接返回缓存，不发起网络请求；
  /// - 上次请求（无论成败）起 [cooldown] 分钟内不发起新请求，抛冷却异常；
  /// - 失败按类型抛出 [UpdateCheckException]（403 限流 / 403 其他 / 网络 / 其他）；
  /// - 数据格式异常仍抛 [FormatException]。
  Future<UpdateInfo> fetchLatestRelease() async {
    final now = DateTime.now();
    if (_cachedInfo != null &&
        _cachedAt != null &&
        now.difference(_cachedAt!) < cacheTtl) {
      return _cachedInfo!;
    }
    if (_lastAttemptAt != null && now.difference(_lastAttemptAt!) < cooldown) {
      throw const UpdateCheckException(
        UpdateCheckErrorType.other,
        '检查更新太频繁，请稍后再试',
      );
    }
    _lastAttemptAt = now;
    try {
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
      final info = UpdateInfo(
        version: tag,
        name: (data['name'] is String && (data['name'] as String).isNotEmpty)
            ? data['name'] as String
            : tag,
        body: (data['body'] is String ? data['body'] as String : '').trim(),
        apkUrl: apkUrl,
      );
      _cachedInfo = info;
      _cachedAt = now;
      return info;
    } on DioException catch (e) {
      throw _classify(e);
    }
  }

  /// 将原始 [DioException] 分类为 [UpdateCheckException]。
  UpdateCheckException _classify(DioException e) {
    final status = e.response?.statusCode;
    if (status == 403) {
      final remaining = e.response?.headers.value('x-ratelimit-remaining');
      final body = e.response?.data?.toString() ?? '';
      final lower = body.toLowerCase();
      final isRateLimit = remaining == '0' ||
          lower.contains('rate limit') ||
          lower.contains('api rate limit exceeded');
      return UpdateCheckException(
        isRateLimit
            ? UpdateCheckErrorType.rateLimited
            : UpdateCheckErrorType.forbidden,
        isRateLimit
            ? 'GitHub 接口触发频率限制，请稍后重试'
            : 'GitHub 拒绝本次请求，请稍后重试',
      );
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return const UpdateCheckException(
        UpdateCheckErrorType.network,
        '网络连接失败，请检查网络后重试',
      );
    }
    if (status != null) {
      return UpdateCheckException(
        UpdateCheckErrorType.other,
        '检查更新服务返回异常（$status），请稍后重试',
      );
    }
    return UpdateCheckException(
      UpdateCheckErrorType.other,
      (e.message == null || e.message!.isEmpty)
          ? '检查更新失败，请稍后重试'
          : '检查更新失败：${e.message}',
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
