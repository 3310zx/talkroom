import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var instanceLockFD: Int32 = -1

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // 单实例守卫：文件锁（NSLock + flock 非阻塞）。
    // 多开进程共享同一 SQLite 与本地端口，会导致锁冲突与端口漂移；
    // 检测到已有实例时弹窗提示并退出本进程。
    guard let appSupport = NSSearchPathForDirectoriesInDomains(
      .applicationSupportDirectory, .userDomainMask, true).first else {
      return
    }
    let dir = (appSupport as NSString).appendingPathComponent("LLM Chat")
    try? FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true)
    let lockPath = (dir as NSString).appendingPathComponent("instance.lock")
    let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
    if fd == -1 {
      // 锁文件创建失败：保守放行，避免误伤正常使用
      return
    }
    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
      // 已有实例持有锁：提示并退出
      let alert = NSAlert()
      alert.messageText = "LLM Chat 已在运行"
      alert.informativeText = "检测到已有实例在运行。为避免数据冲突，请切换到已打开的窗口。"
      alert.alertStyle = .warning
      alert.runModal()
      close(fd)
      NSApp.terminate(nil)
      return
    }
    instanceLockFD = fd
  }

  deinit {
    if instanceLockFD != -1 {
      flock(instanceLockFD, LOCK_UN)
      close(instanceLockFD)
      instanceLockFD = -1
    }
  }
}
