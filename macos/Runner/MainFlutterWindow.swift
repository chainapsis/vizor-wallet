import Cocoa
import FlutterMacOS
import desktop_window_bootstrap

private func titlebarTitleColor(for brightness: String) -> NSColor {
  if brightness == "dark" {
    return NSColor.white.withAlphaComponent(0.8)
  }
  return NSColor.black.withAlphaComponent(0.8)
}

private func currentSystemBrightness() -> String {
  let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
  return match == .darkAqua ? "dark" : "light"
}

private func appTitle() -> String {
  Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Vizor"
}

final class WindowAppearanceChannel {
  private static var shared: WindowAppearanceChannel?

  private weak var window: NSWindow?
  private weak var visualEffectView: NSVisualEffectView?
  private weak var titleLabel: NSTextField?
  private let channel: FlutterMethodChannel

  private init(
    window: NSWindow,
    visualEffectView: NSVisualEffectView,
    titleLabel: NSTextField,
    messenger: FlutterBinaryMessenger
  ) {
    self.window = window
    self.visualEffectView = visualEffectView
    self.titleLabel = titleLabel
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
    titleLabel: NSTextField,
    messenger: FlutterBinaryMessenger
  ) {
    shared = WindowAppearanceChannel(
      window: window,
      visualEffectView: visualEffectView,
      titleLabel: titleLabel,
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
    titleLabel?.appearance = appearance
    titleLabel?.textColor = titlebarTitleColor(for: brightness)
    visualEffectView?.material = .fullScreenUI
    visualEffectView?.state = .active
    window?.backgroundColor = .clear
    window?.invalidateShadow()
  }
}

private final class TitlebarTitleLabel: NSTextField {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let desktopWindowViewController = DesktopWindowBootstrapMacOS.start(
      mainFlutterWindow: self
    )
    let flutterViewController = desktopWindowViewController.flutterViewController
    let titleLabel = makeTitleLabel()
    installTitleLabel(
      titleLabel,
      in: desktopWindowViewController.visualEffectView,
      above: flutterViewController.view
    )
    WindowAppearanceChannel.register(
      window: self,
      visualEffectView: desktopWindowViewController.visualEffectView,
      titleLabel: titleLabel,
      messenger: flutterViewController.engine.binaryMessenger
    )
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func makeTitleLabel() -> NSTextField {
    let label = TitlebarTitleLabel(labelWithString: appTitle())
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = NSFont.systemFont(ofSize: 15, weight: .bold)
    label.textColor = titlebarTitleColor(for: currentSystemBrightness())
    label.lineBreakMode = .byClipping
    label.usesSingleLineMode = true
    return label
  }

  private func installTitleLabel(
    _ label: NSTextField,
    in visualEffectView: NSVisualEffectView,
    above flutterView: NSView
  ) {
    visualEffectView.addSubview(label, positioned: .above, relativeTo: flutterView)
    let verticalConstraint =
      titleCenterYConstraint(for: label, in: visualEffectView) ??
      label.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 6)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 84),
      verticalConstraint,
    ])
  }

  private func titleCenterYConstraint(
    for label: NSTextField,
    in visualEffectView: NSVisualEffectView
  ) -> NSLayoutConstraint? {
    guard
      let closeButton = standardWindowButton(.closeButton),
      let closeButtonSuperview = closeButton.superview
    else {
      return nil
    }

    closeButtonSuperview.layoutSubtreeIfNeeded()
    visualEffectView.layoutSubtreeIfNeeded()

    let closeFrame = closeButtonSuperview.convert(closeButton.frame, to: visualEffectView)
    guard closeFrame.height > 0, visualEffectView.bounds.height > 0 else {
      return nil
    }

    let closeCenterYFromTop = visualEffectView.bounds.height - closeFrame.midY
    return label.centerYAnchor.constraint(
      equalTo: visualEffectView.topAnchor,
      constant: closeCenterYFromTop
    )
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
  }
}
