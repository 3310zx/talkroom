import 'attachment_parser_core.dart';

/// Web 平台文件解析入口：无文件系统，仅支持字节解析。
Future<AttachmentParseResult> parseInBackground(
  String path,
  String name,
) =>
    throw UnsupportedError('Web 平台不支持按路径解析文件，请传入文件字节');
