import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/platform.dart';

/// 本地通知封装（PRD 5.3：主动消息生成完成/失败提醒，点击跳转对应会话）。
///
/// 平台说明：
/// - iOS/macOS：首次启动请求通知权限（alert/badge/sound）；沙盒应用无需额外
///   entitlement，权限由系统弹窗管理。
/// - Android：需要 POST_NOTIFICATIONS 运行时权限（Android 13+），插件提供
///   `requestNotificationsPermission()`；渠道在 initialize 时创建。
class LocalNotificationsService {
  LocalNotificationsService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 通知点击回调：payload 中携带 conversationId。
  Future<void> Function(int conversationId)? _onOpenConversation;

  /// 注册「点击通知跳转会话」处理器（由调度器/UI 层注入）。
  void setOnOpenConversation(Future<void> Function(int conversationId)? handler) {
    _onOpenConversation = handler;
  }

  /// 初始化插件并请求各平台通知权限。
  Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // 请求权限（各平台在需要时弹出系统授权）
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    if (AppPlatform.isMacOS) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    final conversationId = int.tryParse(payload ?? '');
    if (conversationId != null) {
      _onOpenConversation?.call(conversationId);
    }
  }

  /// 发送主动消息结果通知。payload 为 conversationId，点击后跳转会话。
  Future<void> showActiveTaskResult({
    required String taskName,
    required String body,
    required int conversationId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'active_tasks',
      '主动消息',
      channelDescription: 'LLM 定时任务生成结果提醒',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const macosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      macOS: macosDetails,
    );
    await _plugin.show(
      conversationId,
      'LLM 提醒：$taskName',
      body,
      details,
      payload: '$conversationId',
    );
  }
}
