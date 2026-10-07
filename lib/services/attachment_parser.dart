import 'dart:typed_data';

import 'attachment_parser_core.dart' as core;
import 'attachment_parser_io.dart'
    if (dart.library.html) 'attachment_parser_web.dart' as platform;

export 'attachment_parser_core.dart'
    show AttachmentParseRequest, AttachmentParseResult;

/// 文件解析器（v1.2.1）：发送本地文档前提取文本内容，节省 token。
///
/// IO 平台按路径解析；Web 平台无文件系统，使用 [parseInBackgroundBytes]。
class AttachmentParser {
  AttachmentParser._();

  /// 解析文本截断上限（字符数），约 2000 token（按 4 字符/token 保守估算）。
  static const int kMaxParsedChars = core.AttachmentParserCore.kMaxParsedChars;

  /// 在 compute isolate 中解析（IO 平台：按路径读文件）。
  static Future<core.AttachmentParseResult> parseInBackground(
    String path,
    String name,
  ) =>
      platform.parseInBackground(path, name);

  /// 在 compute isolate 中解析字节（Web 平台：浏览器选择器读入的 bytes）。
  static Future<core.AttachmentParseResult> parseInBackgroundBytes(
    Uint8List bytes,
    String name,
  ) =>
      core.AttachmentParserCore.parseInBackgroundBytes(bytes, name);

  /// 判断扩展名是否属于可解析文本类（用于 pick 后立即决定是否触发解析）。
  static bool isParsableName(String name) =>
      core.AttachmentParserCore.isParsableName(name);
}
