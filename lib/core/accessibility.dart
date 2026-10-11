import 'package:flutter/services.dart';

import 'platform.dart';

/// 系统辅助功能偏好（macOS Liquid Glass 回退依据）。
///
/// - [increaseContrast]：系统「增加对比度」开启 → 主题切换到高对比变体；
/// - [reduceTransparency]：系统「降低透明度」开启 → 界面减少依赖玻璃质感。
///
/// 仅 macOS 生效；其他平台保持默认值（false），不影响移动/平板端。
class AppAccessibility {
  /// 系统「增加对比度」偏好（读取成功后缓存）。
  static bool increaseContrast = false;

  /// 系统「降低透明度」偏好（读取成功后缓存）。
  static bool reduceTransparency = false;

  static bool _loaded = false;

  /// 加载系统偏好（幂等：只执行一次；失败静默保持默认值，不阻塞启动）。
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (!AppPlatform.isMacOS) return;
    try {
      final result = await const MethodChannel('talkroom/accessibility')
          .invokeMethod<Map<Object?, Object?>>('getAccessibilityPrefs');
      increaseContrast = result?['increaseContrast'] == true;
      reduceTransparency = result?['reduceTransparency'] == true;
    } catch (_) {
      // 读取失败（旧版系统/权限差异）保持默认，界面不因偏好读取异常崩溃。
    }
  }
}
