import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'application/providers/database_provider.dart';
import 'application/providers/local_notifications_provider.dart';
import 'data/database/app_database.dart';
import 'data/secure_storage/api_key_store.dart';
import 'services/local_notifications_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 桌面端（macOS / Windows / Linux）使用 FFI 版 SQLite；移动端走原生 sqflite
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Hive（key-value 设置/轻量缓存）初始化
  final supportDir = await getApplicationSupportDirectory();
  Hive.init(supportDir.path);

  // 打开本地 SQLite（建表 / 迁移）
  final appDatabase = AppDatabase.instance;
  await appDatabase.open();

  // 初始化 API Key 安全存储封装（预留）
  await ApiKeyStore.initialize();

  // 初始化本地通知服务（主动消息结果提醒；首次启动请求系统权限）
  final notifications = LocalNotificationsService();
  await notifications.initialize();

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(appDatabase),
        localNotificationsServiceProvider.overrideWithValue(notifications),
      ],
      child: const LlmChatApp(),
    ),
  );
}
