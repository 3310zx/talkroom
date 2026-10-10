import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'application/providers/database_provider.dart';
import 'application/providers/local_notifications_provider.dart';
import 'data/database/app_database.dart';
import 'data/database/db_factory_io.dart'
    if (dart.library.html) 'data/database/db_factory_web.dart' as db_factory;
import 'data/secure_storage/api_key_store.dart';
import 'services/crash_logger.dart';
import 'services/local_notifications_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 数据库工厂：桌面 FFI / 移动端原生 sqflite / Web IndexedDB(wasm)
  db_factory.initDatabaseFactory();

  // Hive（key-value 设置/轻量缓存）初始化；Web 无文件系统，跳过
  if (!kIsWeb) {
    final supportDir = await getApplicationSupportDirectory();
    Hive.init(supportDir.path);
  }

  // 崩溃日志目录（写入应用数据目录，非系统临时目录；Web 无文件系统静默跳过）
  await CrashLogger.initialize();

  // 崩溃/未捕获错误钩子：错误落盘而非仅控制台打印。
  FlutterError.onError = (details) {
    CrashLogger.log(details.exception, details.stack, context: 'FlutterError');
    if (kReleaseMode) {
      FlutterError.presentError(details);
    } else {
      FlutterError.dumpErrorToConsole(details);
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLogger.log(error, stack, context: 'PlatformDispatcher');
    return true;
  };

  // 打开本地 SQLite（建表 / 迁移）
  final appDatabase = AppDatabase.instance;
  await appDatabase.open();

  // 初始化 API Key 安全存储封装（macOS Keychain 可用性探测）
  await ApiKeyStore.initialize();

  // 本地通知：Web 不支持，跳过初始化（相关入口已在 UI 隐藏）
  if (!kIsWeb) {
    final notifications = LocalNotificationsService();
    await notifications.initialize();
    runZonedGuarded(
      () => runApp(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(appDatabase),
            localNotificationsServiceProvider.overrideWithValue(notifications),
          ],
          child: const LlmChatApp(),
        ),
      ),
      (error, stack) =>
          CrashLogger.log(error, stack, context: 'Zone'),
    );
    return;
  }

  runZonedGuarded(
    () => runApp(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(appDatabase),
        ],
        child: const LlmChatApp(),
      ),
    ),
    (error, stack) =>
        CrashLogger.log(error, stack, context: 'Zone'),
  );
}
