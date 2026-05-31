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

final class PrivacyExposureChannel: NSObject, FlutterStreamHandler {
  private static var shared: PrivacyExposureChannel?
  // Mission Control and occlusion notifications can arrive before the window is
  // fully key/visible again; wait briefly before marking sensitive content safe.
  private static let safeConfirmationDelay = DispatchTimeInterval.milliseconds(300)

  private struct ObserverRegistration {
    let center: NotificationCenter
    let observer: NSObjectProtocol
  }

  private weak var window: NSWindow?
  private let methodChannel: FlutterMethodChannel
  private var eventSink: FlutterEventSink?
  private var observers: [ObserverRegistration] = []
  private var sensitiveContentVisible = false
  private var nativeSafe = true
  private var originalCollectionBehavior: NSWindow.CollectionBehavior?
  private var pendingSafeConfirmation: DispatchWorkItem?
  private var missionControlPolicySuspended = false

  private init(
    window: NSWindow,
    messenger: FlutterBinaryMessenger
  ) {
    self.window = window
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
    messenger: FlutterBinaryMessenger
  ) {
    shared = PrivacyExposureChannel(
      window: window,
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
      pendingSafeConfirmation?.cancel()
      pendingSafeConfirmation = nil
      updateMissionControlPolicy()
      if visible {
        publishCurrentState(reason: "sensitiveContentVisible")
      } else {
        // Dart gates the visual overlay on sensitiveContentVisible as well as
        // nativeSafe, so clearing sensitive content only needs to restore local
        // state and Mission Control policy.
        nativeSafe = true
        missionControlPolicySuspended = false
      }
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
    observers.append(ObserverRegistration(center: center, observer: observer))
  }

  private func removeObservers() {
    for registration in observers {
      registration.center.removeObserver(registration.observer)
    }
    observers.removeAll()
  }

  private func publishCurrentState(reason: String) {
    guard let window else {
      publishUnsafe(reason: "\(reason):missingWindow")
      return
    }

    let safe = computeIsSafe(window: window)

    if !safe && sensitiveContentVisible {
      suspendMissionControlPolicy()
    }

    let details = windowStateDetails(for: window)

    if safe && sensitiveContentVisible && !nativeSafe {
      confirmSafeAfterWindowSettles(reason: reason)
      return
    }

    pendingSafeConfirmation?.cancel()
    pendingSafeConfirmation = nil
    nativeSafe = safe

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
    publish(
      isSafe: false,
      reason: reason,
      details: windowStateDetails()
    )
  }

  private func confirmSafeAfterWindowSettles(reason: String) {
    pendingSafeConfirmation?.cancel()
    nativeSafe = false

    let confirmation = DispatchWorkItem { [weak self] in
      guard let self, let window = self.window else {
        return
      }

      let safe = self.computeIsSafe(window: window)

      self.pendingSafeConfirmation = nil
      self.nativeSafe = safe

      if safe && self.sensitiveContentVisible {
        self.missionControlPolicySuspended = false
        self.updateMissionControlPolicy()
      }
      let details = self.windowStateDetails(for: window)
      self.publish(
        isSafe: safe,
        reason: safe ? "\(reason):confirmed" : "\(reason):notStable",
        details: details
      )
    }

    pendingSafeConfirmation = confirmation
    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.safeConfirmationDelay,
      execute: confirmation
    )
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
    // `.transient` keeps the window out of Mission Control, but keeping that
    // collection behavior through the return transition can leave Vizor behind
    // another app after Mission Control closes. Once macOS reports an unsafe
    // transition, restore the original behavior so AppKit can order the window
    // normally; the Dart privacy overlay remains responsible for the visible
    // cover during that unsafe interval.
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
    return windowStateDetails(for: window)
  }

  private func windowStateDetails(for window: NSWindow) -> [String: Bool] {
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

  private func computeIsSafe(window: NSWindow) -> Bool {
    return
      NSApp.isActive &&
      !NSApp.isHidden &&
      window.isKeyWindow &&
      !window.isMiniaturized &&
      NSApp.occlusionState.contains(.visible) &&
      window.occlusionState.contains(.visible)
  }

  private func frontmostApplicationIsUs() -> Bool {
    NSWorkspace.shared.frontmostApplication?.processIdentifier ==
      ProcessInfo.processInfo.processIdentifier
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

final class CameraPermissionSettingsChannel {
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/camera_permission",
      binaryMessenger: messenger
    )
    channel = methodChannel
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "openSettings":
        guard
          let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
          )
        else {
          result(false)
          return
        }
        result(NSWorkspace.shared.open(url))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private final class TitlebarTitleLabel: NSTextField {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

class MainFlutterWindow: NSWindow {
  private static let fullscreenTitleFallbackDelay = DispatchTimeInterval.seconds(2)

  private var fullscreenTitleObservers: [NSObjectProtocol] = []
  private var fullscreenTitleTransitionGeneration = 0
  deinit {
    for observer in fullscreenTitleObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

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
    installFullscreenTitleObservers(for: titleLabel)
    WindowAppearanceChannel.register(
      window: self,
      visualEffectView: desktopWindowViewController.visualEffectView,
      titleLabel: titleLabel,
      messenger: flutterViewController.engine.binaryMessenger
    )
    PrivacyExposureChannel.register(
      window: self,
      messenger: flutterViewController.engine.binaryMessenger
    )
    CameraPermissionSettingsChannel.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  private func installFullscreenTitleObservers(for titleLabel: NSTextField) {
    guard fullscreenTitleObservers.isEmpty else {
      return
    }

    syncTitleVisibilityWithFullscreenState(titleLabel)
    scheduleInitialFullscreenTitleSync(for: titleLabel)

    let center = NotificationCenter.default
    fullscreenTitleObservers.append(
      center.addObserver(
        forName: NSWindow.willEnterFullScreenNotification,
        object: self,
        queue: .main
      ) { [weak self, weak titleLabel] _ in
        guard let self, let titleLabel else {
          return
        }
        self.setTitleHidden(true, titleLabel: titleLabel)
        self.scheduleFullscreenTitleFallback(for: titleLabel)
      }
    )
    fullscreenTitleObservers.append(
      center.addObserver(
        forName: NSWindow.didEnterFullScreenNotification,
        object: self,
        queue: .main
      ) { [weak self, weak titleLabel] _ in
        self?.finishFullscreenTitleTransition()
        self?.setTitleHidden(true, titleLabel: titleLabel)
      }
    )
    fullscreenTitleObservers.append(
      center.addObserver(
        forName: NSWindow.willExitFullScreenNotification,
        object: self,
        queue: .main
      ) { [weak self, weak titleLabel] _ in
        guard let self, let titleLabel else {
          return
        }
        self.setTitleHidden(true, titleLabel: titleLabel)
        self.scheduleFullscreenTitleFallback(for: titleLabel)
      }
    )
    fullscreenTitleObservers.append(
      center.addObserver(
        forName: NSWindow.didExitFullScreenNotification,
        object: self,
        queue: .main
      ) { [weak self, weak titleLabel] _ in
        guard let self, let titleLabel else {
          return
        }
        self.finishFullscreenTitleTransition()
        self.syncTitleVisibilityWithFullscreenState(titleLabel)
      }
    )
  }

  private func scheduleInitialFullscreenTitleSync(for titleLabel: NSTextField) {
    DispatchQueue.main.async { [weak self, weak titleLabel] in
      guard let self, let titleLabel else {
        return
      }

      self.syncTitleVisibilityWithFullscreenState(titleLabel)
    }
  }

  private func scheduleFullscreenTitleFallback(for titleLabel: NSTextField) {
    fullscreenTitleTransitionGeneration += 1
    let generation = fullscreenTitleTransitionGeneration

    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.fullscreenTitleFallbackDelay
    ) { [weak self, weak titleLabel] in
      guard
        let self,
        let titleLabel,
        self.fullscreenTitleTransitionGeneration == generation
      else {
        return
      }

      self.syncTitleVisibilityWithFullscreenState(titleLabel)
    }
  }

  private func finishFullscreenTitleTransition() {
    fullscreenTitleTransitionGeneration += 1
  }

  private func setTitleHidden(_ hidden: Bool, titleLabel: NSTextField?) {
    titleVisibility = .hidden
    titleLabel?.isHidden = hidden
  }

  private func syncTitleVisibilityWithFullscreenState(_ titleLabel: NSTextField) {
    setTitleHidden(styleMask.contains(.fullScreen), titleLabel: titleLabel)
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
