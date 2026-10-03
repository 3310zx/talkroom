import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llm_chat_app/services/update_service.dart';

/// 可控的 GitHub API 假适配器：记录请求 URL，按给定 JSON 响应返回。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.statusCode, this.body);

  final int statusCode;
  final String body;
  String? lastUrl;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastUrl = options.uri.toString();
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {'content-type': ['application/json']},
    );
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
}
