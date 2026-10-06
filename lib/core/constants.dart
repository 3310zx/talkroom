/// 全局常量与默认值（对齐 PRD 附录「默认值」）。
abstract final class AppConstants {
  /// 应用名
  static const String appName = 'LLM Chat';

  /// 当前应用版本号（与 pubspec.yaml 的 version 保持一致；检查更新时与远端 tag 比对）
  static const String appVersion = '1.2.2';

  /// 未绑定 API 配置时的会话标题
  static const String defaultConversationTitle = '新会话';

  /// 默认端口（PRD 第 7 章：局域网服务器端口 8787）
  static const int defaultServerPort = 8787;

  /// 端口探测最大尝试次数
  static const int maxPortProbeAttempts = 10;

  /// 设置项 key（对应 PRD 6.1 settings 表）
  static const String settingTemperature = 'temperature';
  static const String settingMaxTokens = 'max_tokens';
  static const String settingTopP = 'top_p';
  static const String settingFrequencyPenalty = 'frequency_penalty';
  static const String settingPresencePenalty = 'presence_penalty';
  static const String settingSystemPrompt = 'system_prompt';
  static const String settingQuietStart = 'quiet_start';
  static const String settingQuietEnd = 'quiet_end';

  // ---- 局域网同步（PRD 第 7 章） ----
  /// 本机设备唯一标识（uuid；电脑与手机各自生成）
  static const String settingLocalDeviceId = 'sync_local_device_id';

  /// 本机设备展示名
  static const String settingLocalDeviceName = 'sync_local_device_name';

  /// 服务器端设备唯一标识（服务器在配对时下发给客户端，同时写入自身 settings）
  static const String settingServerDeviceId = 'sync_server_device_id';

  /// 是否启用同步（'1'/'0'）
  static const String settingSyncEnabled = 'sync_enabled';

  /// 服务器地址（客户端连接用）
  static const String settingSyncHost = 'sync_host';

  /// 服务器端口（客户端连接用）
  static const String settingSyncPort = 'sync_port';

  /// 客户端配对后获得的访问令牌
  static const String settingSyncToken = 'sync_device_token';

  /// 最后成功同步时间（毫秒）
  static const String settingSyncLastSyncAt = 'sync_last_sync_at';

  /// 服务器端配对码（一次性，配对成功后清空）
  static const String settingServerPairCode = 'server_pair_code';

  /// 服务器端配对防猜：连续失败计数
  static const String settingServerPairFailCount = 'server_pair_fail_count';

  /// 服务器端配对防猜：锁定截止时间（毫秒）
  static const String settingServerPairLockUntil = 'server_pair_lock_until';

  /// 应用启动时是否自动拉起本地服务器（'1'/'0'，仅电脑端生效）
  static const String settingServerAutoStart = 'server_auto_start';

  /// 最近一次服务器使用的端口
  static const String settingServerLastPort = 'server_last_port';

  // ---- 外观主题 ----
  /// 主题模式（'system' 跟随系统 / 'light' 浅色 / 'dark' 深色）
  static const String settingThemeMode = 'theme_mode';

  /// 主题取色源（'preset' 默认微信绿 / 'custom' 自定义取色 / 'monet' 莫奈壁纸动态）
  static const String settingThemeSeedMode = 'theme_seed_mode';

  /// 自定义取色 seed（HEX 色值字符串，如 '#FF0000'；仅在 custom 模式生效）
  static const String settingThemeCustomSeed = 'theme_custom_seed';

  // ---- 启动行为 ----
  /// 启动行为（'last' 回到退出时的对话 / 'new' 创建新对话，默认 'new'）
  static const String settingStartupBehavior = 'startup_behavior';

  /// 启动行为：回到退出时的对话
  static const String startupBehaviorLast = 'last';

  /// 启动行为：创建新对话
  static const String startupBehaviorNew = 'new';

  /// 配对码位数
  static const int pairCodeLength = 6;

  /// 配对码连续失败锁定阈值（PRD 7.5：连续错误锁定）
  static const int pairMaxFailures = 5;

  /// 锁定时长（毫秒）：10 分钟
  static const int pairLockDurationMs = 10 * 60 * 1000;

  /// 增量同步单批上限
  static const int syncBatchLimit = 500;

  /// 服务器端同步周期兜底间隔（秒）：电脑端新消息固化 + 广播
  static const int serverFinalizeIntervalSeconds = 30;

  /// 默认参数
  static const double defaultTemperature = 0.7;
  static const int defaultMaxTokens = 2048;
  static const double defaultTopP = 1.0;
  static const double defaultFrequencyPenalty = 0.0;
  static const double defaultPresencePenalty = 0.0;
}
