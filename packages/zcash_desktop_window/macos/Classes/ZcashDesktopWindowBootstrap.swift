import Cocoa
import FlutterMacOS

public enum ZcashDesktopWindowBootstrap {
  private static weak var mainWindow: NSWindow?
  private static var fullscreenObservers: [NSObjectProtocol] = []

  @discardableResult
  public static func start(mainFlutterWindow: NSWindow) -> ZcashDesktopWindowViewController {
    let controller = ZcashDesktopWindowViewController()
    let windowFrame = mainFlutterWindow.frame
    mainFlutterWindow.contentViewController = controller
    mainFlutterWindow.setFrame(windowFrame, display: true)

    mainWindow = mainFlutterWindow
    applyWindowedAppearance()
    installFullscreenObservers()

    return controller
  }

  public static func titlebarInset() -> Double {
    guard let window = mainWindow else {
      return 0
    }

    let windowFrameHeight = window.contentView?.frame.height ?? 0
    let contentLayoutRectHeight = window.contentLayoutRect.height
    return max(0, windowFrameHeight - contentLayoutRectHeight)
  }

  private static func installFullscreenObservers() {
    guard fullscreenObservers.isEmpty, let window = mainWindow else {
      return
    }

    let center = NotificationCenter.default
    fullscreenObservers.append(
      center.addObserver(
        forName: NSWindow.willEnterFullScreenNotification,
        object: window,
        queue: .main
      ) { _ in
        applyFullscreenAppearance()
      }
    )
    fullscreenObservers.append(
      center.addObserver(
        forName: NSWindow.willExitFullScreenNotification,
        object: window,
        queue: .main
      ) { _ in
        applyWindowedAppearance()
      }
    )
  }

  private static func applyWindowedAppearance() {
    guard let window = mainWindow,
          let controller = window.contentViewController as? ZcashDesktopWindowViewController
    else {
      return
    }

    window.backgroundColor = .clear
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    window.standardWindowButton(.zoomButton)?.isEnabled = false
    controller.visualEffectView.state = .active
    if #available(macOS 10.14, *) {
      controller.visualEffectView.material = .fullScreenUI
    }
    window.invalidateShadow()
  }

  private static func applyFullscreenAppearance() {
    guard let window = mainWindow,
          let controller = window.contentViewController as? ZcashDesktopWindowViewController
    else {
      return
    }

    window.backgroundColor = .windowBackgroundColor
    if #available(macOS 10.14, *) {
      controller.visualEffectView.material = .windowBackground
    }
    window.invalidateShadow()
  }
}
