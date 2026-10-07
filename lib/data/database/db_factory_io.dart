import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// IO 平台数据库工厂：
/// - 桌面端（macOS / Windows / Linux）使用 FFI 版 SQLite（无需系统依赖）；
/// - 移动端（Android / iOS）走原生 sqflite 通道。
///
/// Web 平台请走 db_factory_web.dart（IndexedDB + wasm）。
void initDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // 移动端（Android / iOS）：使用 sqflite 默认原生 factory，无需显式设置。
}
