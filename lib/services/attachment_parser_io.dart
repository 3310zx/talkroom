import 'dart:io';
import 'dart:typed_data';

import 'attachment_parser_core.dart';

/// IO 平台（移动 / 桌面）文件解析入口：按路径读字节后交给核心解析。
///
/// 读取失败（文件不存在 / 无权限等）标记 failed，与核心解析错误同语义。
Future<AttachmentParseResult> parseInBackground(
  String path,
  String name,
) async {
  Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } catch (e) {
    return AttachmentParseResult.failed('$e');
  }
  return AttachmentParserCore.parseInBackgroundBytes(bytes, name);
}
