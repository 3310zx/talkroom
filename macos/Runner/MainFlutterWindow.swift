import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSWindowDelegate {
  private enum Persistence {
    static let frameKey = "llm_chat_window_frame"
    static let defaultWidth: CGFloat = 1280
    static let defaultHeight: CGFloat = 800
    static let minWidth: CGFloat = 1200
    static let minHeight: CGFloat = 800
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController
    self.setFrame(self.frame, display: true)
    RegisterGeneratedPlugins(registry: flutterViewController)

    // 最小尺寸约束：避免宽屏三栏布局被压垮
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
