import 'dart:typed_data';

/// Web 平台：浏览器沙箱无文件系统路径访问，调用即抛错（调用方须走 bytes 分支）。
Future<Uint8List> readFileBytes(String path) async {
  throw UnsupportedError('Web 平台不支持通过路径读取文件，请使用 bytes 上传');
}

/// Web 平台：浏览器沙箱无文件系统路径访问，调用即抛错（调用方须走 bytes 分支）。
Future<int> fileLength(String path) async {
  throw UnsupportedError('Web 平台不支持通过路径读取文件大小');
}
