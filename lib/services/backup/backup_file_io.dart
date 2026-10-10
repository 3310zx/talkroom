import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/platform.dart';

/// 备份文件读写（桌面 / 移动端 IO 平台）。
///
/// - 导出：桌面端用 file_picker 保存对话框选择路径；移动端写入临时目录后
///   走系统分享面板（可保存到文件 App 或发送到其它应用）。
/// - 导入：file_picker 选择任意文件后读字节（支持本应用备份 JSON 与
///   Chatbox 备份 zip）。
abstract final class BackupFileIO {
  static const String kMimeJson = 'application/json';
  static const String kMimeZip = 'application/zip';

  /// 导出备份 JSON 到用户指定位置（桌面）或临时目录后分享（移动端）。
  ///
  /// 返回最终落盘路径；用户取消保存对话框时返回 null。
  static Future<String?> exportBackup(
    String jsonContent, {
    required String suggestedName,
  }) async {
    if (AppPlatform.isDesktop) {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '导出备份',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null) return null; // 用户取消
      await File(path).writeAsString(jsonContent, flush: true);
      return path;
    }
    // 移动端：临时文件 + 系统分享面板
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$suggestedName');
    await file.writeAsString(jsonContent, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: kMimeJson)],
      subject: 'LLM Chat 数据备份',
      text: '软件设置与记忆备份（不含 API Key 与同步凭据）',
    );
    return file.path;
  }

  /// 选择备份文件并读取字节；用户取消时返回 null。
  static Future<Uint8List?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return bytes;
    }
    final path = picked.path;
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }
}
