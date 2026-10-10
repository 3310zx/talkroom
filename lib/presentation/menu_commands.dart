import 'package:flutter/foundation.dart';

/// 菜单栏命令（macOS PlatformMenuBar → HomePage）。
enum MenuAction {
  /// 关于对话框
  about,

  /// 打开设置（宽屏抽屉 / 窄屏设置 Tab）
  settings,

  /// 检查更新
  checkUpdate,

  /// 新建会话（清空当前选中，回到新会话状态）
  newConversation,

  /// 打开同步服务器页
  openSyncServer,
}

/// 全局菜单命令总线：菜单栏回调与 HomePage 状态解耦。
///
/// HomePage 在 initState 注册各动作回调，菜单 onSelected 调用 [fire]。
/// 若 HomePage 尚未就绪（注册表为空），动作被安全忽略。
class MenuCommandBus {
  MenuCommandBus._();

  static final Map<MenuAction, VoidCallback> _actions = {};

  static void register(MenuAction action, VoidCallback callback) {
    _actions[action] = callback;
  }

  static void unregister(MenuAction action) {
    _actions.remove(action);
  }

  static void fire(MenuAction action) {
    _actions[action]?.call();
  }
}
