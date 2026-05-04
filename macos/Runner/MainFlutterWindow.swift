import Cocoa
import CoreImage
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

private final class NativeLockIconView: NSView {
  var fillColor = NSColor(calibratedWhite: 0.88, alpha: 1) {
    didSet {
      needsDisplay = true
    }
  }

  override var isFlipped: Bool {
    true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    let scale = min(bounds.width / 24, bounds.height / 24)
    let xOffset = (bounds.width - 24 * scale) / 2
    let yOffset = (bounds.height - 24 * scale) / 2

    context.saveGState()
    context.translateBy(x: xOffset, y: yOffset)
    context.scaleBy(x: scale, y: scale)
    context.addPath(Self.iconPath)
    context.setFillColor(fillColor.cgColor)
    context.fillPath(using: .evenOdd)
    context.restoreGState()
  }

  private static let iconPath: CGPath = {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 12, y: 2.62207))
    path.addCurve(to: CGPoint(x: 7.22461, y: 7.51074), control1: CGPoint(x: 9.35362, y: 2.62207), control2: CGPoint(x: 7.22461, y: 4.82288))
    path.addLine(to: CGPoint(x: 7.22461, y: 9.80504))
    path.addLine(to: CGPoint(x: 6.5, y: 9.80504))
    path.addCurve(to: CGPoint(x: 4.34961, y: 12), control1: CGPoint(x: 5.3062, y: 9.80504), control2: CGPoint(x: 4.34961, y: 10.8025))
    path.addLine(to: CGPoint(x: 4.34961, y: 19.1829))
    path.addLine(to: CGPoint(x: 4.36133, y: 19.4051))
    path.addCurve(to: CGPoint(x: 6.5, y: 21.3779), control1: CGPoint(x: 4.47091, y: 20.5012), control2: CGPoint(x: 5.38094, y: 21.3779))
    path.addLine(to: CGPoint(x: 17.5, y: 21.3779))
    path.addCurve(to: CGPoint(x: 19.6387, y: 19.4051), control1: CGPoint(x: 18.6191, y: 21.3779), control2: CGPoint(x: 19.5291, y: 20.5012))
    path.addLine(to: CGPoint(x: 19.6504, y: 19.1829))
    path.addLine(to: CGPoint(x: 19.6504, y: 12))
    path.addCurve(to: CGPoint(x: 17.5, y: 9.80504), control1: CGPoint(x: 19.6504, y: 10.8025), control2: CGPoint(x: 18.6938, y: 9.80504))
    path.addLine(to: CGPoint(x: 16.7754, y: 9.80504))
    path.addLine(to: CGPoint(x: 16.7754, y: 7.51074))
    path.addCurve(to: CGPoint(x: 12, y: 2.62207), control1: CGPoint(x: 16.7754, y: 4.82288), control2: CGPoint(x: 14.6464, y: 2.62207))
    path.closeSubpath()

    path.move(to: CGPoint(x: 11.999, y: 12.8982))
    path.addCurve(to: CGPoint(x: 13.3076, y: 13.4311), control1: CGPoint(x: 12.5087, y: 12.8982), control2: CGPoint(x: 12.9473, y: 13.0761))
    path.addCurve(to: CGPoint(x: 13.8496, y: 14.722), control1: CGPoint(x: 13.668, y: 13.7861), control2: CGPoint(x: 13.8495, y: 14.2187))
    path.addLine(to: CGPoint(x: 13.8457, y: 14.8486))
    path.addCurve(to: CGPoint(x: 13.5908, y: 15.6621), control1: CGPoint(x: 13.8267, y: 15.1403), control2: CGPoint(x: 13.7421, y: 15.4123))
    path.addLine(to: CGPoint(x: 13.5225, y: 15.7663))
    path.addCurve(to: CGPoint(x: 12.9434, y: 16.2885), control1: CGPoint(x: 13.3706, y: 15.9823), control2: CGPoint(x: 13.1766, y: 16.1562))
    path.addLine(to: CGPoint(x: 13.3262, y: 18.3841))
    path.addCurve(to: CGPoint(x: 13.1943, y: 18.8585), control1: CGPoint(x: 13.3603, y: 18.5584), control2: CGPoint(x: 13.3126, y: 18.7192))
    path.addCurve(to: CGPoint(x: 12.7432, y: 19.0719), control1: CGPoint(x: 13.0753, y: 18.9984), control2: CGPoint(x: 12.9227, y: 19.0718))
    path.addLine(to: CGPoint(x: 11.2559, y: 19.0719))
    path.addCurve(to: CGPoint(x: 10.8047, y: 18.8585), control1: CGPoint(x: 11.0767, y: 19.0716), control2: CGPoint(x: 10.9236, y: 18.9983))
    path.addCurve(to: CGPoint(x: 10.6748, y: 18.3841), control1: CGPoint(x: 10.6863, y: 18.7189), control2: CGPoint(x: 10.6407, y: 18.5579))
    path.addLine(to: CGPoint(x: 11.0576, y: 16.2885))
    path.addCurve(to: CGPoint(x: 10.4092, y: 15.6621), control1: CGPoint(x: 10.7876, y: 16.1355), control2: CGPoint(x: 10.5698, y: 15.9268))
    path.addLine(to: CGPoint(x: 10.3486, y: 15.5539))
    path.addCurve(to: CGPoint(x: 10.1543, y: 14.8486), control1: CGPoint(x: 10.235, y: 15.3343), control2: CGPoint(x: 10.1706, y: 15.0988))
    path.addLine(to: CGPoint(x: 10.1504, y: 14.722))
    path.addCurve(to: CGPoint(x: 10.6914, y: 13.4311), control1: CGPoint(x: 10.1505, y: 14.219), control2: CGPoint(x: 10.3312, y: 13.7861))
    path.addCurve(to: CGPoint(x: 11.999, y: 12.8982), control1: CGPoint(x: 11.0515, y: 13.0763), control2: CGPoint(x: 11.4897, y: 12.8984))
    path.closeSubpath()

    path.move(to: CGPoint(x: 12, y: 5.21643))
    path.addCurve(to: CGPoint(x: 14.2246, y: 7.51074), control1: CGPoint(x: 13.2121, y: 5.21643), control2: CGPoint(x: 14.2246, y: 6.23883))
    path.addLine(to: CGPoint(x: 14.2246, y: 9.80504))
    path.addLine(to: CGPoint(x: 9.77539, y: 9.80504))
    path.addLine(to: CGPoint(x: 9.77539, y: 7.51074))
    path.addCurve(to: CGPoint(x: 12, y: 5.21643), control1: CGPoint(x: 9.77539, y: 6.23883), control2: CGPoint(x: 10.7879, y: 5.21643))
    path.closeSubpath()
    return path
  }()
}

private final class NativePrivacyShieldView: NSView {
  private static let paneCornerRadius = 8.0
  private static let blurRadius = 30.0

  private let blurView = NSView()
  private let scrimView = NSView()
  private let badge = NSView()
  private let icon = NativeLockIconView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = true
    wantsLayer = true
    layer?.cornerRadius = Self.paneCornerRadius
    layer?.masksToBounds = true

    blurView.translatesAutoresizingMaskIntoConstraints = false
    blurView.wantsLayer = true
    blurView.layer?.backgroundColor = NSColor.clear.cgColor
    blurView.layer?.masksToBounds = true
    if let blurFilter = CIFilter(name: "CIGaussianBlur") {
      blurFilter.setValue(Self.blurRadius, forKey: kCIInputRadiusKey)
      blurView.layer?.backgroundFilters = [blurFilter]
    }
    addSubview(blurView)

    scrimView.translatesAutoresizingMaskIntoConstraints = false
    scrimView.wantsLayer = true
    addSubview(scrimView)

    badge.translatesAutoresizingMaskIntoConstraints = false
    badge.wantsLayer = true
    badge.layer?.cornerRadius = 24
    badge.layer?.masksToBounds = true
    addSubview(badge)

    icon.translatesAutoresizingMaskIntoConstraints = false
    badge.addSubview(icon)

    NSLayoutConstraint.activate([
      blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
      blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
      blurView.topAnchor.constraint(equalTo: topAnchor),
      blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

      scrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
      scrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
      scrimView.topAnchor.constraint(equalTo: topAnchor),
      scrimView.bottomAnchor.constraint(equalTo: bottomAnchor),

      badge.widthAnchor.constraint(equalToConstant: 98),
      badge.heightAnchor.constraint(equalToConstant: 98),
      badge.centerXAnchor.constraint(equalTo: centerXAnchor),
      badge.centerYAnchor.constraint(equalTo: centerYAnchor),

      icon.widthAnchor.constraint(equalToConstant: 50),
      icon.heightAnchor.constraint(equalToConstant: 50),
      icon.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
    ])

    updateColors()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  private func updateColors() {
    let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    scrimView.layer?.backgroundColor =
      (isDark
        ? NSColor(calibratedRed: 98 / 255, green: 103 / 255, blue: 103 / 255, alpha: 0.20)
        : NSColor(calibratedRed: 20 / 255, green: 24 / 255, blue: 24 / 255, alpha: 0.20)
      ).cgColor
    badge.layer?.backgroundColor =
      (isDark ? NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.09, alpha: 1) : NSColor.white).cgColor
    icon.fillColor =
      isDark ? NSColor(calibratedWhite: 0.88, alpha: 1) : NSColor(calibratedRed: 0.08, green: 0.09, blue: 0.09, alpha: 1)
  }
}

final class PrivacyExposureChannel: NSObject, FlutterStreamHandler {
  private static var shared: PrivacyExposureChannel?

  private weak var window: NSWindow?
  private weak var containerView: NSView?
  private let methodChannel: FlutterMethodChannel
  private var eventSink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []
  private var sensitiveContentVisible = false
  private var nativeSafe = true
  private var shieldFrame: NSRect?
  private var shieldView: NativePrivacyShieldView?
  private var originalCollectionBehavior: NSWindow.CollectionBehavior?
  private var pendingSafeConfirmation: DispatchWorkItem?
  private var missionControlPolicySuspended = false

  private init(
    window: NSWindow,
    containerView: NSView,
    messenger: FlutterBinaryMessenger
  ) {
    self.window = window
    self.containerView = containerView
    self.methodChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/privacy_shield",
      binaryMessenger: messenger
    )
    super.init()

    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    let eventChannel = FlutterEventChannel(
      name: "com.zcash.wallet/privacy_exposure",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
    installObservers()
  }

  deinit {
    removeObservers()
    restoreMissionControlPolicy()
  }

  static func register(
    window: NSWindow,
    containerView: NSView,
    messenger: FlutterBinaryMessenger
  ) {
    shared = PrivacyExposureChannel(
      window: window,
      containerView: containerView,
      messenger: messenger
    )
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    publishCurrentState(reason: "listen")
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "setSensitiveContentVisible":
      guard
        let arguments = call.arguments as? [String: Any],
        let visible = arguments["visible"] as? Bool
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected visible argument.",
            details: nil
          )
        )
        return
      }
      sensitiveContentVisible = visible
      shieldFrame = visible ? parseShieldFrame(from: arguments["rect"]) : nil
      pendingSafeConfirmation?.cancel()
      pendingSafeConfirmation = nil
      updateMissionControlPolicy()
      if visible {
        publishCurrentState(reason: "sensitiveContentVisible")
      } else {
        nativeSafe = true
        missionControlPolicySuspended = false
      }
      updateNativeShield()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func installObservers() {
    let defaultCenter = NotificationCenter.default
    let workspaceCenter = NSWorkspace.shared.notificationCenter

    observe(defaultCenter, name: NSApplication.willResignActiveNotification, object: NSApp) { [weak self] _ in
      self?.publishUnsafe(reason: "appWillResignActive")
    }
    observe(defaultCenter, name: NSApplication.didResignActiveNotification, object: NSApp) { [weak self] _ in
      self?.publishUnsafe(reason: "appDidResignActive")
    }
    observe(defaultCenter, name: NSApplication.didBecomeActiveNotification, object: NSApp) { [weak self] _ in
      self?.publishCurrentState(reason: "appDidBecomeActive")
    }
    observe(defaultCenter, name: NSApplication.didHideNotification, object: NSApp) { [weak self] _ in
      self?.publishUnsafe(reason: "appDidHide")
    }
    observe(defaultCenter, name: NSApplication.didUnhideNotification, object: NSApp) { [weak self] _ in
      self?.publishCurrentState(reason: "appDidUnhide")
    }
    observe(defaultCenter, name: NSApplication.didChangeOcclusionStateNotification, object: NSApp) { [weak self] _ in
      self?.publishCurrentState(reason: "appOcclusionChanged")
    }
    observe(workspaceCenter, name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared) { [weak self] _ in
      self?.publishUnsafe(reason: "activeSpaceDidChange")
    }

    if let window {
      observe(defaultCenter, name: NSWindow.didResignKeyNotification, object: window) { [weak self] _ in
        self?.publishUnsafe(reason: "windowDidResignKey")
      }
      observe(defaultCenter, name: NSWindow.didBecomeKeyNotification, object: window) { [weak self] _ in
        self?.publishCurrentState(reason: "windowDidBecomeKey")
      }
      observe(defaultCenter, name: NSWindow.didMiniaturizeNotification, object: window) { [weak self] _ in
        self?.publishUnsafe(reason: "windowDidMiniaturize")
      }
      observe(defaultCenter, name: NSWindow.didDeminiaturizeNotification, object: window) { [weak self] _ in
        self?.publishCurrentState(reason: "windowDidDeminiaturize")
      }
      observe(defaultCenter, name: NSWindow.didChangeOcclusionStateNotification, object: window) { [weak self] _ in
        self?.publishCurrentState(reason: "windowOcclusionChanged")
      }
    }
  }

  private func observe(
    _ center: NotificationCenter,
    name: Notification.Name,
    object: Any?,
    using block: @escaping (Notification) -> Void
  ) {
    let observer = center.addObserver(
      forName: name,
      object: object,
      queue: .main,
      using: block
    )
    observers.append(observer)
  }

  private func removeObservers() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
    observers.removeAll()
  }

  private func publishCurrentState(reason: String) {
    guard let window else {
      publishUnsafe(reason: "\(reason):missingWindow")
      return
    }

    let appVisible = NSApp.occlusionState.contains(.visible)
    let windowVisible = window.occlusionState.contains(.visible)
    let safe =
      NSApp.isActive &&
      !NSApp.isHidden &&
      window.isKeyWindow &&
      !window.isMiniaturized &&
      appVisible &&
      windowVisible

    if !safe && sensitiveContentVisible {
      suspendMissionControlPolicy()
    }

    let details = [
      "appActive": NSApp.isActive,
      "appHidden": NSApp.isHidden,
      "frontmostIsUs": frontmostApplicationIsUs(),
      "windowKey": window.isKeyWindow,
      "windowMiniaturized": window.isMiniaturized,
      "appVisible": appVisible,
      "windowVisible": windowVisible,
      "missionControlPolicySuspended": missionControlPolicySuspended,
    ]

    if safe && sensitiveContentVisible && !nativeSafe {
      confirmSafeAfterWindowSettles(reason: reason)
      return
    }

    pendingSafeConfirmation?.cancel()
    pendingSafeConfirmation = nil
    nativeSafe = safe
    updateNativeShield()

    publish(
      isSafe: safe,
      reason: reason,
      details: details
    )
  }

  private func publishUnsafe(reason: String) {
    pendingSafeConfirmation?.cancel()
    pendingSafeConfirmation = nil
    if sensitiveContentVisible {
      suspendMissionControlPolicy()
    }
    nativeSafe = false
    updateNativeShield()
    publish(
      isSafe: false,
      reason: reason,
      details: windowStateDetails()
    )
  }

  private func confirmSafeAfterWindowSettles(reason: String) {
    pendingSafeConfirmation?.cancel()
    nativeSafe = false
    updateNativeShield()

    let confirmation = DispatchWorkItem { [weak self] in
      guard let self, let window = self.window else {
        return
      }

      let appVisible = NSApp.occlusionState.contains(.visible)
      let windowVisible = window.occlusionState.contains(.visible)
      let safe =
        NSApp.isActive &&
        !NSApp.isHidden &&
        window.isKeyWindow &&
        !window.isMiniaturized &&
        appVisible &&
        windowVisible
      let details = [
        "appActive": NSApp.isActive,
        "appHidden": NSApp.isHidden,
        "frontmostIsUs": self.frontmostApplicationIsUs(),
        "windowKey": window.isKeyWindow,
        "windowMiniaturized": window.isMiniaturized,
        "appVisible": appVisible,
        "windowVisible": windowVisible,
      ]

      self.pendingSafeConfirmation = nil
      self.nativeSafe = safe
      self.updateNativeShield()

      if safe && self.sensitiveContentVisible {
        self.missionControlPolicySuspended = false
        self.updateMissionControlPolicy()
      }
      self.publish(
        isSafe: safe,
        reason: safe ? "\(reason):confirmed" : "\(reason):notStable",
        details: details
      )
    }

    pendingSafeConfirmation = confirmation
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: confirmation)
  }

  private func updateNativeShield() {
    let shouldShow = sensitiveContentVisible && !nativeSafe && currentShieldFrame() != nil
    if shouldShow {
      showNativeShield()
    } else {
      hideNativeShield()
    }
  }

  private func showNativeShield() {
    guard let containerView, let frame = currentShieldFrame() else {
      return
    }

    let shieldView = self.shieldView ?? NativePrivacyShieldView(frame: frame)
    shieldView.frame = frame
    if shieldView.superview == nil {
      containerView.addSubview(shieldView)
    }
    self.shieldView = shieldView
    containerView.layoutSubtreeIfNeeded()
    containerView.displayIfNeeded()
    window?.displayIfNeeded()
  }

  private func hideNativeShield() {
    shieldView?.removeFromSuperview()
    shieldView = nil
  }

  private func updateMissionControlPolicy() {
    guard let window else {
      return
    }

    if sensitiveContentVisible {
      guard !missionControlPolicySuspended else {
        return
      }
      if originalCollectionBehavior == nil {
        originalCollectionBehavior = window.collectionBehavior
      }
      var behavior = window.collectionBehavior
      behavior.remove(.managed)
      behavior.insert(.transient)
      window.collectionBehavior = behavior
    } else {
      restoreMissionControlPolicy()
    }
  }

  private func suspendMissionControlPolicy() {
    missionControlPolicySuspended = true
    restoreMissionControlPolicy()
  }

  private func restoreMissionControlPolicy() {
    guard let window, let originalCollectionBehavior else {
      return
    }
    window.collectionBehavior = originalCollectionBehavior
    self.originalCollectionBehavior = nil
  }

  private func windowStateDetails() -> [String: Bool]? {
    guard let window else {
      return nil
    }
    return [
      "appActive": NSApp.isActive,
      "appHidden": NSApp.isHidden,
      "frontmostIsUs": frontmostApplicationIsUs(),
      "windowKey": window.isKeyWindow,
      "windowMiniaturized": window.isMiniaturized,
      "appVisible": NSApp.occlusionState.contains(.visible),
      "windowVisible": window.occlusionState.contains(.visible),
      "missionControlPolicySuspended": missionControlPolicySuspended,
    ]
  }

  private func parseShieldFrame(from rawRect: Any?) -> NSRect? {
    guard
      let rect = rawRect as? [String: Any],
      let left = doubleValue(rect["left"]),
      let top = doubleValue(rect["top"]),
      let width = doubleValue(rect["width"]),
      let height = doubleValue(rect["height"]),
      width > 0,
      height > 0
    else {
      return nil
    }
    return NSRect(x: left, y: top, width: width, height: height)
  }

  private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    return value as? Double
  }

  private func frontmostApplicationIsUs() -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier ==
      ProcessInfo.processInfo.processIdentifier
  }

  private func currentShieldFrame() -> NSRect? {
    guard let containerView, let shieldFrame else {
      return nil
    }

    let frame = NSRect(
      x: shieldFrame.minX,
      y: containerView.bounds.height - shieldFrame.minY - shieldFrame.height,
      width: shieldFrame.width,
      height: shieldFrame.height
    )
    let clipped = frame.intersection(containerView.bounds)
    if clipped.isNull || clipped.width <= 0 || clipped.height <= 0 {
      return nil
    }
    return clipped
  }

  private func publish(isSafe: Bool, reason: String, details: [String: Bool]?) {
    var payload: [String: Any] = [
      "isSafe": isSafe,
      "reason": reason,
    ]
    if let details {
      payload["details"] = details
    }
    eventSink?(payload)
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
    PrivacyExposureChannel.register(
      window: self,
      containerView: flutterViewController.view,
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
