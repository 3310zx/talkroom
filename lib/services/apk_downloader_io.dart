import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// APK 应用内下载服务。
///
/// 在应用私有目录（Android 为内部 files/updates，已被 FileProvider
/// `files-path` 覆盖）下载 APK，支持进度回调与取消，避免跳转外部浏览器
/// 导致「下载完成但无安装入口」的体验断裂。
class ApkDownloader {
  ApkDownloader({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// 下载 APK 到应用私有目录。
  ///
  /// [url] 为 GitHub Release 资产下载链接；[fileName] 为落盘文件名；
  /// [onProgress] 回调已接收字节数与总字节数（总字节数可能为 null）；
  /// 传入 [cancelToken] 可中断下载（中断抛 [DioExceptionType.cancel]）。
  /// 返回最终 APK 绝对路径。
  Future<String> downloadApk({
    required String url,
    required String fileName,
    required void Function(int received, int? total) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _updateDir();
    final savePath = '${dir.path}/$fileName';
    final response = await _dio.download(
      url,
      savePath,
      cancelToken: cancelToken,
      options: Options(
        headers: {'User-Agent': 'talkroom-update-download'},
        followRedirects: true,
        responseType: ResponseType.stream,
      ),
      onReceiveProgress: (received, total) => onProgress(received, total),
    );
    if (response.statusCode != null &&
        (response.statusCode! < 200 || response.statusCode! >= 300)) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }
    final file = File(savePath);
    if (!await file.exists() || await file.length() == 0) {
      throw StateError('APK 下载结果为空文件：$savePath');
    }
    return savePath;
  }

  Future<Directory> _updateDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/updates');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}

/// APK 安装器：通过系统安装器打开已下载的 APK。
///
/// Android 走原生 MethodChannel（FileProvider + ACTION_VIEW，见
/// MainActivity.kt）；非 Android 平台返回 false，由界面提示文件位置。
class ApkInstaller {
  static const MethodChannel _channel = MethodChannel('talkroom/apk_install');

  /// 当前是否已具备「安装未知应用」权限（Android 8+ 需要）。
  static Future<bool> canRequestInstall() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('canRequestInstall');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 发起安装；返回 true 表示已拉起系统安装器（或已引导开启权限）。
  /// Android 8+ 未授权未知来源时会先跳转系统设置，返回 false 并附带提示。
  static Future<bool> install(String apkPath) async {
    if (!Platform.isAndroid) return false;
    try {
      final result =
          await _channel.invokeMethod<String>('installApk', {'path': apkPath});
      return result == 'OK';
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }
}
