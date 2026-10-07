import 'dart:io';

/// IO 平台：用系统默认浏览器 / 命令打开 URL。
Future<void> openExternalUrl(String url) async {
  if (Platform.isMacOS || Platform.isLinux) {
    await Process.run('open', [url]);
  } else if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', url]);
  }
  // Android / iOS：交由调用方决定或提示手动打开。
}
