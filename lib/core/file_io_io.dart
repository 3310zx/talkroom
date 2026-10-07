import 'dart:io';
import 'dart:typed_data';

/// IO 平台（移动端 / 桌面端）：按路径读取本地文件字节。
Future<Uint8List> readFileBytes(String path) => File(path).readAsBytes();

/// IO 平台（移动端 / 桌面端）：返回本地文件字节数。
Future<int> fileLength(String path) => File(path).length();
