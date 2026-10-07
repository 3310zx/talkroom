import 'package:sqflite_common/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web 平台数据库工厂：IndexedDB（sqlite3 wasm，sqflite_common_ffi_web）。
void initDatabaseFactory() {
  databaseFactory = databaseFactoryFfiWeb;
}
