import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';

/// 数据库实例（由 main.dart 在 ProviderScope overrides 注入）。
final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('appDatabaseProvider 必须在 main.dart 中 override'),
);
