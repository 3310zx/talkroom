import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private enum Persistence {
    static let frameKey = "llm_chat_window_frame"
    static let defaultWidth: CGFloat = 1280
    static let defaultHeight: CGFloat = 800
    // Talkroom macOS 重构：桌面端默认两栏（会话列表 | 聊天区），
    // 最小宽度从 1200 放宽到 1000；详情面板需窗口 >= 1000 才可展开。
    static let minWidth: CGFloat = 1000
    static let minHeight: CGFloat = 700
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(self.frame, display: true)
    RegisterGeneratedPlugins(registry: flutterViewController)

    // Talkroom macOS：原生窗口样式（非自绘模糊）。
    // - 隐藏标题文字、透明标题栏：Flutter 工具栏内容延伸至标题栏区域，
    //   与系统红绿灯按钮共存，形成「工具栏与内容」自然层次；
    // - macOS Tahoe 上由系统对标题栏应用原生液态玻璃材质，旧版系统
    //   自动回退为普通标题栏（无需自绘透明层冒充）。
    self.title = "Talkroom"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    // 引擎（Flutter 3.47）未暴露内容延伸标题栏 API，采用原生透明标题栏 +
    // 窗口背景与主题表面同色（深色 0x111111），使红绿灯与工具栏、内容
    // 形成统一层次；不使用自绘透明层冒充系统材质，旧版 macOS 同样适用。
    self.backgroundColor = NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
      return NSColor(
        calibratedRed: isDark ? 0.067 : 1.0,
        green: isDark ? 0.067 : 1.0,
        blue: isDark ? 0.067 : 1.0,
        alpha: 1.0)
    }

    // 暴露系统辅助功能偏好（增加对比度 / 降低透明度），供 Flutter 侧
    // 在玻璃材质弱化/不可用时切换到高对比回退主题（保证深色可读性）。
    let accessibilityChannel = FlutterMethodChannel(
      name: "talkroom/accessibility",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    accessibilityChannel.setMethodCallHandler { call, result in
      guard call.method == "getAccessibilityPrefs" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let ws = NSWorkspace.shared
      result([
        "increaseContrast": ws.accessibilityDisplayShouldIncreaseContrast,
        "reduceTransparency": ws.accessibilityDisplayShouldReduceTransparency,
      ])
    }

    // 最小尺寸约束：避免宽屏两栏布局被压垮
    self.contentMinSize = NSSize(
      width: Persistence.minWidth, height: Persistence.minHeight)

    // 窗口尺寸记忆：优先恢复上次保存的 frame，否则默认 1280x800 居中
    let screen = NSScreen.main?.visibleFrame
      ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    var targetFrame: NSRect? = nil
    if let frameString = UserDefaults.standard.string(
      forKey: Persistence.frameKey)
    {
      let saved = NSRectFromString(frameString)
      if saved.width >= Persistence.minWidth,
        saved.height >= Persistence.minHeight
      {
        // 将窗口钳制到主屏可见区域内，避免分辨率变化后窗口跑到屏幕外
        var clamped = saved
        clamped.size.width = min(saved.width, screen.width)
        clamped.size.height = min(saved.height, screen.height)
        clamped.origin.x = min(
          max(saved.origin.x, screen.minX),
          max(screen.minX, screen.maxX - clamped.width))
        clamped.origin.y = min(
          max(saved.origin.y, screen.minY),
          max(screen.minY, screen.maxY - clamped.height))
        targetFrame = clamped
      }
    }
    if targetFrame == nil {
      let width = min(Persistence.defaultWidth, screen.width)
      let height = min(Persistence.defaultHeight, screen.height)
      targetFrame = NSRect(
        x: screen.minX + (screen.width - width) / 2,
        y: screen.minY + (screen.height - height) / 2,
        width: width,
        height: height)
    }
    self.setFrame(targetFrame!, display: true)

    self.delegate = self
    super.awakeFromNib()
  }

  // MARK: - 尺寸记忆

  func windowDidMove(_ notification: Notification) { persistFrame() }
  func windowDidEndLiveResize(_ notification: Notification) { persistFrame() }

  private func persistFrame() {
    UserDefaults.standard.set(
      NSStringFromRect(self.frame), forKey: Persistence.frameKey)
  }
}
