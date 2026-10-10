import 'dart:typed_data';

/// Web 平台备份文件读写 stub：浏览器文件系统能力有限，明确提示不支持。
abstract final class BackupFileIO {
  static Future<String?> exportBackup(
    String jsonContent, {
    required String suggestedName,
  }) =>
      throw UnsupportedError('Web 平台暂不支持备份导出');

  static Future<Uint8List?> pickBackupFile() =>
      throw UnsupportedError('Web 平台暂不支持备份导入');
}
