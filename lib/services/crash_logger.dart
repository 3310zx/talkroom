import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';

/// 崩溃/错误日志本地落盘（macOS 桌面端为重点，全平台通用）。
///
/// 写入应用数据目录（path_provider 的 ApplicationSupportDirectory）
/// 下的 `crashes/` 子目录，非系统临时目录，随应用卸载才清理。
///
/// 设计约束：
/// - 所有写入使用同步 IO + try/catch，崩溃钩子路径不抛异常、不异步，
///   保证最坏情况下日志也能落盘；
/// - 文件名带微秒时间戳，天然防覆盖（同秒多崩溃各自独立成文件）；
/// - 日志仅包含运行版本、时间、错误与堆栈，不采集任何用户敏感内容。
class CrashLogger {
  CrashLogger._();

  static Directory? _crashesDir;

  /// 启动时初始化崩溃目录（失败不阻断主流程）。
  static Future<void> initialize() async {
    try {
      final support = await getApplicationSupportDirectory();
      _crashesDir = Directory('${support.path}${Platform.pathSeparator}crashes');
      await _crashesDir!.create(recursive: true);
    } catch (_) {
      _crashesDir = null;
    }
  }

  /// 记录一次错误/崩溃。
  static void log(
    Object error,
    StackTrace? stack, {
    String? context,
  }) {
    final dir = _crashesDir;
    if (dir == null) return;
    try {
      final now = DateTime.now();
      final name = 'crash_${now.year}'
          '${_two(now.month)}${_two(now.day)}'
          '_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}'
          '_${now.millisecond}${now.microsecond}.log';
      final buffer = StringBuffer()
        ..writeln('[${now.toIso8601String()}] ${context ?? 'error'}')
        ..writeln('app: ${AppConstants.appName} v${AppConstants.appVersion}')
        ..writeln('platform: ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}')
        ..writeln('error: $error');
      if (stack != null) {
        buffer
          ..writeln('stack:')
          ..writeln(stack.toString());
      }
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      file.writeAsStringSync(buffer.toString(), flush: true);
    } catch (_) {
      // 日志写入自身失败时静默丢弃，避免崩溃钩子二次崩溃。
    }
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
