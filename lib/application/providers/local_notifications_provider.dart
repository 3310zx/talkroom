import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/local_notifications_service.dart';

/// 本地通知服务实例（由 main.dart 初始化后 override 注入）。
final localNotificationsServiceProvider =
    Provider<LocalNotificationsService>(
  (ref) => throw UnimplementedError(
    'localNotificationsServiceProvider 必须在 main.dart 中 override',
  ),
);
