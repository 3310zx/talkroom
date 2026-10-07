import 'package:flutter/foundation.dart';

/// 跨平台（含 Web）平台判断工具，替代直接使用 dart:io Platform。
///
/// 设计约束：只依赖 kIsWeb / defaultTargetPlatform，避免 import dart:io
/// 导致 Flutter Web 编译失败。注意 defaultTargetPlatform 在 Web 端会返回
/// 浏览器所在桌面平台（如 macOS），因此所有桌面/移动判断必须叠加 !kIsWeb。
abstract final class AppPlatform {
  static bool get isWeb => kIsWeb;

  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  static bool get isFuchsia =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.fuchsia;

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.fuchsia);

  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 当前是否可承担局域网同步 server 角色。
  ///
  /// Web 浏览器无法监听端口，只能作为客户端；桌面端与 Android
  /// 均可作为 server（Android 手机可被 Web 客户端直连）。
  static bool get isServerCapable =>
      !kIsWeb &&
      (isDesktop || defaultTargetPlatform == TargetPlatform.android);
}
