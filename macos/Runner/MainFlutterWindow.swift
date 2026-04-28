import Cocoa
import FlutterMacOS
import desktop_window_bootstrap

final class WindowAppearanceChannel {
  private static var shared: WindowAppearanceChannel?

  private weak var window: NSWindow?
  private weak var visualEffectView: NSVisualEffectView?
  private let channel: FlutterMethodChannel

  private init(
    window: NSWindow,
    visualEffectView: NSVisualEffectView,
    messenger: FlutterBinaryMessenger
  ) {
    self.window = window
    self.visualEffectView = visualEffectView
    self.channel = FlutterMethodChannel(
      name: "com.zcash.wallet/window_appearance",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  static func register(
    window: NSWindow,
    visualEffectView: NSVisualEffectView,
    messenger: FlutterBinaryMessenger
  ) {
    shared = WindowAppearanceChannel(
      window: window,
      visualEffectView: visualEffectView,
      messenger: messenger
    )
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "setBrightness":
      guard
        let arguments = call.arguments as? [String: Any],
        let brightness = arguments["brightness"] as? String
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected brightness argument.",
            details: nil
          )
        )
        return
      }
      setBrightness(brightness)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setBrightness(_ brightness: String) {
    let appearanceName: NSAppearance.Name =
      brightness == "dark" ? .darkAqua : .aqua
    let appearance = NSAppearance(named: appearanceName)

    NSApp.appearance = appearance
    window?.appearance = appearance
    window?.contentView?.appearance = appearance
    window?.contentViewController?.view.appearance = appearance
    visualEffectView?.appearance = appearance
    // Keep the blur chrome neutral; `.fullScreenUI` can render as a dark
    // sidebar/titlebar even when Flutter has resolved the app to light mode.
    visualEffectView?.material = .windowBackground
    visualEffectView?.state = .active
    window?.backgroundColor = .clear
    window?.invalidateShadow()
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let desktopWindowViewController = DesktopWindowBootstrapMacOS.start(
      mainFlutterWindow: self
    )
    let flutterViewController = desktopWindowViewController.flutterViewController
    WindowAppearanceChannel.register(
      window: self,
      visualEffectView: desktopWindowViewController.visualEffectView,
      messenger: flutterViewController.engine.binaryMessenger
    )
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
