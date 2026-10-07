import 'package:dio/dio.dart';

/// Web 平台 APK 下载 stub：浏览器场景无 APK 安装需求，明确失败。
class ApkDownloader {
  ApkDownloader({Dio? dio});

  Future<String> downloadApk({
    required String url,
    required String fileName,
    required void Function(int received, int? total) onProgress,
    CancelToken? cancelToken,
  }) =>
      throw UnsupportedError('Web 平台不支持 APK 下载');
}

/// Web 平台 APK 安装 stub。
class ApkInstaller {
  static Future<bool> canRequestInstall() async => false;

  static Future<bool> install(String apkPath) async => false;
}
