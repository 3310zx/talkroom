import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/services/update_service.dart';

/// 可控的 GitHub API 假适配器：记录请求 URL 与调用次数，按给定 JSON 响应返回。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(
    this.statusCode,
    this.body, {
    Map<String, List<String>>? headers,
  }) : headers = headers ?? {'content-type': ['application/json']};

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
  String? lastUrl;
  int callCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    callCount++;
    lastUrl = options.uri.toString();
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 直接抛出指定类型 [DioException] 的适配器（模拟网络层错误）。
class _ThrowingAdapter implements HttpClientAdapter {
  _ThrowingAdapter(this.type);

  final DioExceptionType type;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(requestOptions: options, type: type);
  }

  @override
  void close({bool force = false}) {}
}

UpdateService _service(String json) {
  final dio = Dio()..httpClientAdapter = _FakeAdapter(200, json);
  return UpdateService(dio: dio);
}

const _releaseJson = '''
{
  "tag_name": "v1.0.9",
  "name": "Talkroom 1.0.9",
  "body": "修复 SSE 解析\\n新增检查更新",
  "assets": [
    {"name": "llm_chat_app_v1.0.9.apk", "browser_download_url": "https://github.com/3310zx/talkroom/releases/download/v1.0.9/llm_chat_app_v1.0.9.apk"}
  ]
}
''';

void main() {
  // 每个用例前清空 UpdateService 静态冷却/缓存，避免跨用例污染。
  setUp(UpdateService.resetForTest);
  tearDown(UpdateService.resetForTest);

  group('UpdateService.compareVersions', () {
    test('相同版本返回 0', () {
      expect(UpdateService.compareVersions('1.0.9', '1.0.9'), 0);
      expect(UpdateService.compareVersions('v1.0.9', '1.0.9'), 0);
    });

    test('新版本大于当前版本返回正数', () {
      expect(UpdateService.compareVersions('1.0.9', '1.0.8'), greaterThan(0));
      expect(UpdateService.compareVersions('1.1.0', '1.0.9'), greaterThan(0));
      expect(UpdateService.compareVersions('v1.0.9', '1.0.8'), greaterThan(0));
    });

    test('旧版本返回负数', () {
      expect(UpdateService.compareVersions('1.0.7', '1.0.8'), lessThan(0));
    });

    test('缺位段按 0 处理', () {
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('1.0.9', '1.0'), greaterThan(0));
    });
  });

  group('UpdateService.fetchLatestRelease', () {
    test('解析 tag_name / name / body / APK 资产下载链接', () async {
      final service = _service(_releaseJson);
      final info = await service.fetchLatestRelease();

      expect(info.version, 'v1.0.9');
      expect(info.name, 'Talkroom 1.0.9');
      expect(info.body, contains('检查更新'));
      expect(
        info.apkUrl,
        'https://github.com/3310zx/talkroom/releases/download/v1.0.9/llm_chat_app_v1.0.9.apk',
      );
    });

    test('无 APK 资产时 apkUrl 为 null', () async {
      final service = _service('''
{
  "tag_name": "v1.0.9",
  "name": "",
  "body": "仅说明",
  "assets": []
}
''');
      final info = await service.fetchLatestRelease();

      expect(info.version, 'v1.0.9');
      expect(info.name, 'v1.0.9');
      expect(info.apkUrl, isNull);
    });

    test('非对象响应抛 FormatException', () async {
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter(200, '"just a string"');
      final service = UpdateService(dio: dio);

      expect(
        () => service.fetchLatestRelease(),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('UpdateService.fetchLatestRelease 403 分类 / 冷却 / 缓存', () {
    UpdateService serviceWith(
      int statusCode,
      String body, {
      Map<String, List<String>>? headers,
    }) {
      final dio = Dio()
        ..httpClientAdapter = _FakeAdapter(statusCode, body, headers: headers);
      return UpdateService(dio: dio);
    }

    Future<UpdateCheckException> expectException(
        Future<UpdateInfo> future) async {
      try {
        await future;
      } on UpdateCheckException catch (e) {
        return e;
      }
      fail('应抛出 UpdateCheckException');
    }

    test('403 且 X-RateLimit-Remaining=0 分类为 rateLimited', () async {
      final service = serviceWith(
        403,
        '',
        headers: {
          'content-type': ['application/json'],
          'x-ratelimit-remaining': ['0'],
        },
      );
      final e = await expectException(service.fetchLatestRelease());
      expect(e.type, UpdateCheckErrorType.rateLimited);
      expect(e.message, contains('稍后重试'));
    });

    test('403 且响应体含限流关键词分类为 rateLimited', () async {
      final service = serviceWith(
        403,
        '{"message": "API rate limit exceeded for 60.0.0.0"}',
      );
      final e = await expectException(service.fetchLatestRelease());
      expect(e.type, UpdateCheckErrorType.rateLimited);
    });

    test('403 非限流分类为 forbidden', () async {
      final service = serviceWith(403, '{"message": "Not Found"}');
      final e = await expectException(service.fetchLatestRelease());
      expect(e.type, UpdateCheckErrorType.forbidden);
    });

    test('网络连接错误分类为 network', () async {
      final dio = Dio()
        ..httpClientAdapter = _ThrowingAdapter(DioExceptionType.connectionError);
      final service = UpdateService(dio: dio);
      final e = await expectException(service.fetchLatestRelease());
      expect(e.type, UpdateCheckErrorType.network);
    });

    test('非 403 状态码分类为 other 且不暴露堆栈', () async {
      final service = serviceWith(500, '{"message": "boom"}');
      final e = await expectException(service.fetchLatestRelease());
      expect(e.type, UpdateCheckErrorType.other);
      expect(e.message, contains('500'));
      expect(e.message, isNot(contains('DioException')));
    });

    test('冷却生效：失败后短时间内不重复请求', () async {
      final adapter = _FakeAdapter(403, '{"message": "Not Found"}');
      final service = UpdateService(dio: Dio()..httpClientAdapter = adapter);
      final first = await expectException(service.fetchLatestRelease());
      expect(first.type, UpdateCheckErrorType.forbidden);

      final callsBefore = adapter.callCount;
      final second = await expectException(service.fetchLatestRelease());
      expect(second.type, UpdateCheckErrorType.other);
      expect(second.message, contains('太频繁'));
      expect(adapter.callCount, callsBefore);
    });

    test('缓存生效：成功后新实例直接返回缓存且不发起网络请求', () async {
      final service = serviceWith(200, _releaseJson);
      final first = await service.fetchLatestRelease();
      expect(first.version, 'v1.0.9');

      final failedAdapter = _FakeAdapter(500, 'boom');
      final secondService = UpdateService(dio: Dio()..httpClientAdapter = failedAdapter);
      final second = await secondService.fetchLatestRelease();
      expect(second.version, 'v1.0.9');
      expect(failedAdapter.callCount, 0);
    });

    test('成功路径版本比对：最新 v1.0.9 小于当前 1.2.4 返回负数', () async {
      expect(UpdateService.compareVersions('v1.0.9', '1.2.4'), lessThan(0));
    });
  });
}
