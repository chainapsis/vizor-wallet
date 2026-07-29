import Cocoa
import FlutterMacOS
import LocalAuthentication
import Security
import desktop_window_bootstrap
#if DEBUG
import ScreenCaptureKit
#endif

private func appWindowBackgroundColor(for brightness: String) -> NSColor {
  if brightness == "dark" {
    return NSColor(
      srgbRed: 15.0 / 255.0,
      green: 15.0 / 255.0,
      blue: 15.0 / 255.0,
      alpha: 1
    )
  }
  return NSColor(
    srgbRed: 245.0 / 255.0,
    green: 245.0 / 255.0,
    blue: 245.0 / 255.0,
    alpha: 1
  )
}

private func currentSystemBrightness() -> String {
  let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
  return match == .darkAqua ? "dark" : "light"
}

private final class VizorWindowToolbarDelegate: NSObject, NSToolbarDelegate {
  func toolbarAllowedItemIdentifiers(
    _ toolbar: NSToolbar
  ) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace]
  }

  func toolbarDefaultItemIdentifiers(
    _ toolbar: NSToolbar
  ) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace]
  }
}

final class WindowAppearanceChannel {
  private static var shared: WindowAppearanceChannel?

  private weak var window: NSWindow?
  private weak var visualEffectView: NSVisualEffectView?
  private let channel: FlutterMethodChannel
  private var appearanceFrameRestoreToken = 0

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
    case "showInactive":
      guard let window else {
        result(
          FlutterError(
            code: "missing_window",
            message: "The main window is unavailable.",
            details: nil
          )
        )
        return
      }
      window.orderFrontRegardless()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func setBrightness(_ brightness: String) {
    let frameBeforeAppearance = window?.frame
    let appearanceName: NSAppearance.Name =
      brightness == "dark" ? .darkAqua : .aqua
    let appearance = NSAppearance(named: appearanceName)

    NSApp.appearance = appearance
    window?.appearance = appearance
    window?.contentView?.appearance = appearance
    window?.contentViewController?.view.appearance = appearance
    visualEffectView?.appearance = appearance
    DesktopWindowBootstrapMacOS.setOpaqueBackgroundColor(
      appWindowBackgroundColor(for: brightness)
    )
    window?.invalidateShadow()
    restoreWindowFrameAfterAppearanceChange(frameBeforeAppearance)
  }

  private func restoreWindowFrameAfterAppearanceChange(_ expectedFrame: NSRect?) {
    guard
      let expectedFrame,
      let window,
      !window.styleMask.contains(.fullScreen)
    else {
      return
    }

    appearanceFrameRestoreToken += 1
    let token = appearanceFrameRestoreToken

    DispatchQueue.main.async { [weak self] in
      self?.restoreWindowFrame(expectedFrame, token: token)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
      self?.restoreWindowFrame(expectedFrame, token: token)
    }
  }

  private func restoreWindowFrame(_ expectedFrame: NSRect, token: Int) {
    guard
      token == appearanceFrameRestoreToken,
      let window,
      !window.styleMask.contains(.fullScreen),
      frameDiffersVisibly(window.frame, expectedFrame)
    else {
      return
    }

    window.setFrame(expectedFrame, display: true, animate: false)
  }

  private func frameDiffersVisibly(_ current: NSRect, _ expected: NSRect) -> Bool {
    abs(current.origin.x - expected.origin.x) > 0.5 ||
      abs(current.origin.y - expected.origin.y) > 0.5 ||
      abs(current.size.width - expected.size.width) > 0.5 ||
      abs(current.size.height - expected.size.height) > 0.5
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

#if DEBUG
/// Development-only capture bridge used by `lib/figma_compare.dart`.
///
/// Capture is a transaction: the bridge records the current app/window state,
/// restores and activates a minimized window, captures that exact NSWindow,
/// and then returns focus and visibility to their prior state.
final class FigmaComparisonCaptureChannel {
  private static var shared: FigmaComparisonCaptureChannel?
  private static let readyTimeout = DispatchTimeInterval.seconds(3)

  private struct CaptureSession {
    let token: String
    let wasHidden: Bool
    let wasVisible: Bool
    let wasMiniaturized: Bool
    let animationBehavior: NSWindow.AnimationBehavior
    let previousFrontmostApplication: NSRunningApplication?
  }

  private weak var window: NSWindow?
  private let channel: FlutterMethodChannel
  private var session: CaptureSession?

  private init(window: NSWindow, messenger: FlutterBinaryMessenger) {
    self.window = window
    channel = FlutterMethodChannel(
      name: "com.zcash.wallet/figma_compare_capture",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  static func register(window: NSWindow, messenger: FlutterBinaryMessenger) {
    shared = FigmaComparisonCaptureChannel(window: window, messenger: messenger)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "beginCapture":
      beginCapture(result: result)
    case "captureWindow":
      guard
        let arguments = call.arguments as? [String: Any],
        let token = arguments["token"] as? String,
        let path = arguments["path"] as? String
      else {
        result(captureError("bad_args", "Expected capture token and output path."))
        return
      }
      captureWindow(token: token, path: path, result: result)
    case "endCapture":
      guard
        let arguments = call.arguments as? [String: Any],
        let token = arguments["token"] as? String
      else {
        result(captureError("bad_args", "Expected capture token."))
        return
      }
      endCapture(token: token, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func beginCapture(result: @escaping FlutterResult) {
    guard session == nil else {
      result(captureError("capture_in_progress", "A comparison capture is already active."))
      return
    }
    guard let window else {
      result(captureError("missing_window", "The comparison window is unavailable."))
      return
    }

    let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
    let previousFrontmostApplication = NSWorkspace.shared.frontmostApplication
    let captureSession = CaptureSession(
      token: UUID().uuidString,
      wasHidden: NSApp.isHidden,
      wasVisible: window.isVisible,
      wasMiniaturized: window.isMiniaturized,
      animationBehavior: window.animationBehavior,
      previousFrontmostApplication:
        previousFrontmostApplication?.processIdentifier == currentProcessIdentifier
          ? nil
          : previousFrontmostApplication
    )
    session = captureSession

    window.animationBehavior = .none
    presentForCapture(window)

    waitUntilReady(
      token: captureSession.token,
      deadline: DispatchTime.now() + Self.readyTimeout,
      result: result
    )
  }

  private func waitUntilReady(
    token: String,
    deadline: DispatchTime,
    result: @escaping FlutterResult
  ) {
    guard let session, session.token == token, let window else {
      result(captureError("capture_cancelled", "The comparison capture was cancelled."))
      return
    }

    let ready =
      NSApp.isActive &&
      !NSApp.isHidden &&
      window.isKeyWindow &&
      window.isVisible &&
      !window.isMiniaturized &&
      window.occlusionState.contains(.visible)
    if ready {
      result([
        "token": token,
        "windowNumber": window.windowNumber,
        "backingScaleFactor": window.backingScaleFactor,
      ])
      return
    }

    // Activation is asynchronous and another app can win focus between the
    // first request and AppKit publishing the new state. Reassert the entire
    // debug-only capture state on every poll instead of merely waiting for a
    // one-shot activation that may already have been superseded.
    presentForCapture(window)

    if DispatchTime.now() >= deadline {
      restoreSession(session)
      self.session = nil
      result(
        captureError(
          "window_not_ready",
          "The comparison window did not become active, key, and visible."
        )
      )
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
      self?.waitUntilReady(token: token, deadline: deadline, result: result)
    }
  }

  private func presentForCapture(_ window: NSWindow) {
    if NSApp.isHidden {
      NSApp.unhide(nil)
    }
    if window.isMiniaturized {
      window.deminiaturize(nil)
    }
    window.setIsVisible(true)

    // `activate()` is cooperative on current macOS releases. This bridge is
    // DEBUG-only and must put the exact comparison window in the foreground
    // before collecting evidence, so retain the force-activation fallback.
    if #available(macOS 14.0, *) {
      NSApp.activate()
    }
    if !NSApp.isActive || !window.isKeyWindow {
      NSApp.activate(ignoringOtherApps: true)
    }
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  private func captureWindow(
    token: String,
    path: String,
    result: @escaping FlutterResult
  ) {
    guard let session, session.token == token else {
      result(captureError("invalid_token", "The comparison capture token is invalid."))
      return
    }
    guard let window else {
      result(captureError("missing_window", "The comparison window is unavailable."))
      return
    }

    if #available(macOS 14.0, *) {
      captureWithScreenCaptureKit(window: window, path: path, result: result)
    } else {
      captureWithCoreGraphics(window: window, path: path, result: result)
    }
  }

  @available(macOS 14.0, *)
  private func captureWithScreenCaptureKit(
    window: NSWindow,
    path: String,
    result: @escaping FlutterResult
  ) {
    let windowID = CGWindowID(window.windowNumber)
    SCShareableContent.getExcludingDesktopWindows(
      false,
      onScreenWindowsOnly: false
    ) { [weak self] content, error in
      guard let self else { return }
      if let error {
        result(self.captureError("shareable_content_failed", error.localizedDescription))
        return
      }
      guard
        let capturedWindow = content?.windows.first(where: { $0.windowID == windowID })
      else {
        result(self.captureError("window_not_shareable", "The comparison window was not shareable."))
        return
      }

      let filter = SCContentFilter(desktopIndependentWindow: capturedWindow)
      let configuration = SCStreamConfiguration()
      let scale = window.backingScaleFactor
      configuration.width = Int(window.frame.width * scale)
      configuration.height = Int(window.frame.height * scale)
      configuration.showsCursor = false
      configuration.ignoreShadowsSingleWindow = true

      SCScreenshotManager.captureImage(
        contentFilter: filter,
        configuration: configuration
      ) { image, captureError in
        if let captureError {
          result(self.captureError("window_capture_failed", captureError.localizedDescription))
          return
        }
        guard let image else {
          result(self.captureError("window_capture_failed", "ScreenCaptureKit returned no image."))
          return
        }
        self.write(image: image, path: path, backend: "ScreenCaptureKit", result: result)
      }
    }
  }

  private func captureWithCoreGraphics(
    window: NSWindow,
    path: String,
    result: @escaping FlutterResult
  ) {
    guard
      let image = CGWindowListCreateImage(
        .null,
        .optionIncludingWindow,
        CGWindowID(window.windowNumber),
        [.boundsIgnoreFraming, .bestResolution]
      )
    else {
      result(captureError("window_capture_failed", "Core Graphics returned no image."))
      return
    }
    write(image: image, path: path, backend: "CoreGraphics", result: result)
  }

  private func write(
    image: CGImage,
    path: String,
    backend: String,
    result: @escaping FlutterResult
  ) {
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
      result(captureError("png_encoding_failed", "The window image could not be encoded."))
      return
    }

    do {
      try data.write(to: URL(fileURLWithPath: path), options: .atomic)
      result([
        "path": path,
        "width": image.width,
        "height": image.height,
        "backend": backend,
      ])
    } catch {
      result(captureError("png_write_failed", error.localizedDescription))
    }
  }

  private func endCapture(token: String, result: @escaping FlutterResult) {
    guard let session, session.token == token else {
      result(captureError("invalid_token", "The comparison capture token is invalid."))
      return
    }
    restoreSession(session)
    self.session = nil
    // AppKit publishes minimize/hide state on the next run-loop turns. Do not
    // let a capture-and-exit caller terminate before that restoration settles.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
      result([
        "windowMiniaturized": self?.window?.isMiniaturized ?? false,
        "windowVisible": self?.window?.isVisible ?? false,
        "appHidden": NSApp.isHidden,
      ])
    }
  }

  private func restoreSession(_ session: CaptureSession) {
    guard let window else { return }

    window.animationBehavior = .none
    if session.wasHidden {
      NSApp.hide(nil)
    } else if session.wasMiniaturized {
      window.miniaturize(nil)
    } else if !session.wasVisible {
      window.orderOut(nil)
    }
    window.animationBehavior = session.animationBehavior

    guard
      let previousApplication = session.previousFrontmostApplication,
      !previousApplication.isTerminated,
      NSWorkspace.shared.frontmostApplication?.processIdentifier ==
        ProcessInfo.processInfo.processIdentifier
    else {
      return
    }
    _ = previousApplication.activate(options: [])
  }

  private func captureError(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}
#endif

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

final class DeviceOwnerAuthChannel {
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/device_owner_auth",
      binaryMessenger: messenger
    )
    channel = methodChannel
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "verify":
        let arguments = call.arguments as? [String: Any]
        // Fallback mirrors the Dart canonical `kWalletResetDeviceAuthReason`;
        // the Dart side always sends `reason`, so this default is defensive only.
        let reason = (arguments?["reason"] as? String) ?? "Confirm reset Vizor"
        verify(reason: reason, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func verify(reason: String, result: @escaping FlutterResult) {
    // Passcode-only by design: this destructive gate must never be satisfied
    // by a Touch ID glance. There is no LAPolicy that accepts the device
    // passcode while skipping biometry, so instead of
    // `.deviceOwnerAuthentication` (biometry-first) we evaluate a
    // `.devicePasscode`-constrained access control, which only ever presents
    // the device password entry.
    var accessControlError: Unmanaged<CFError>?
    guard let accessControl = SecAccessControlCreateWithFlags(
      nil,
      kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
      .devicePasscode,
      &accessControlError
    ) else {
      // Consume the +1-retained CFError so the failure path doesn't leak it.
      _ = accessControlError?.takeRetainedValue()
      result(FlutterError(
        code: "unavailable",
        message: "Device passcode is not configured.",
        details: nil
      ))
      return
    }

    let context = LAContext()
    context.evaluateAccessControl(
      accessControl,
      operation: .useItem,
      localizedReason: reason
    ) { success, error in
      DispatchQueue.main.async {
        if success {
          result(true)
          return
        }

        guard let laError = error as? LAError else {
          result(FlutterError(code: "failed", message: error?.localizedDescription, details: nil))
          return
        }

        switch laError.code {
        case .userCancel, .systemCancel, .appCancel:
          result(false)
        case .passcodeNotSet, .biometryNotAvailable, .biometryNotEnrolled:
          result(FlutterError(code: "unavailable", message: laError.localizedDescription, details: nil))
        default:
          result(FlutterError(code: "failed", message: laError.localizedDescription, details: nil))
        }
      }
    }
  }
}

class MainFlutterWindow: NSWindow {
  private let vizorWindowToolbarDelegate = VizorWindowToolbarDelegate()
  private var vizorWindowToolbar: NSToolbar?
  private var vizorWindowToolbarObservers: [NSObjectProtocol] = []

  deinit {
    for observer in vizorWindowToolbarObservers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  override func awakeFromNib() {
    let desktopWindowViewController = DesktopWindowBootstrapMacOS.start(
      mainFlutterWindow: self,
      visualStyle: .opaque,
      backgroundColor: appWindowBackgroundColor(for: currentSystemBrightness())
    )
    title = ""
    installVizorWindowToolbarObservers()
    applyAndScheduleVizorWindowToolbarForCurrentState()
    let flutterViewController = desktopWindowViewController.flutterViewController
    WindowAppearanceChannel.register(
      window: self,
      visualEffectView: desktopWindowViewController.visualEffectView,
      messenger: flutterViewController.engine.binaryMessenger
    )
    PrivacyExposureChannel.register(
      window: self,
      messenger: flutterViewController.engine.binaryMessenger
    )
#if DEBUG
    FigmaComparisonCaptureChannel.register(
      window: self,
      messenger: flutterViewController.engine.binaryMessenger
    )
#endif
    CameraPermissionSettingsChannel.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    DeviceOwnerAuthChannel.register(
      messenger: flutterViewController.engine.binaryMessenger
    )
    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    super.order(place, relativeTo: otherWin)
    hiddenWindowAtLaunch()
    applyAndScheduleVizorWindowToolbarForCurrentState()
  }

  private func installVizorWindowToolbarObservers() {
    guard vizorWindowToolbarObservers.isEmpty else {
      return
    }

    let center = NotificationCenter.default
    let hideToolbarEvents: [Notification.Name] = [
      NSWindow.willEnterFullScreenNotification,
      NSWindow.didEnterFullScreenNotification,
    ]
    for name in hideToolbarEvents {
      vizorWindowToolbarObservers.append(
        center.addObserver(
          forName: name,
          object: self,
          queue: .main
        ) { [weak self] _ in
          self?.hideVizorWindowToolbar()
        }
      )
    }

    vizorWindowToolbarObservers.append(
      center.addObserver(
        forName: NSWindow.didExitFullScreenNotification,
        object: self,
        queue: .main
      ) { [weak self] _ in
        self?.applyAndScheduleVizorWindowToolbarForCurrentState()
      }
    )

    let reapplyToolbarEvents: [Notification.Name] = [
      NSWindow.didBecomeKeyNotification,
      NSWindow.didEndLiveResizeNotification,
    ]
    for name in reapplyToolbarEvents {
      vizorWindowToolbarObservers.append(
        center.addObserver(
          forName: name,
          object: self,
          queue: .main
        ) { [weak self] _ in
          self?.applyAndScheduleVizorWindowToolbarForCurrentState()
        }
      )
    }
  }

  private func applyAndScheduleVizorWindowToolbarForCurrentState() {
    applyVizorWindowToolbarForCurrentState()
    DispatchQueue.main.async { [weak self] in
      self?.applyVizorWindowToolbarForCurrentState()
    }
  }

  private func applyVizorWindowToolbarForCurrentState() {
    configureVizorWindowToolbar(
      isVisible: !styleMask.contains(.fullScreen)
    )
  }

  private func hideVizorWindowToolbar() {
    configureVizorWindowToolbar(isVisible: false)
  }

  private func configureVizorWindowToolbar(isVisible: Bool) {
    let vizorToolbar = vizorWindowToolbar ?? makeVizorWindowToolbar()
    vizorToolbar.allowsUserCustomization = false
    vizorToolbar.autosavesConfiguration = false
    vizorToolbar.delegate = vizorWindowToolbarDelegate
    vizorToolbar.displayMode = .iconOnly
    vizorToolbar.sizeMode = .regular
    vizorToolbar.showsBaselineSeparator = false
    if toolbar !== vizorToolbar {
      self.toolbar = vizorToolbar
    }
    vizorToolbar.isVisible = isVisible
    toolbarStyle = .unified
    titleVisibility = .hidden
    titlebarSeparatorStyle = .none
  }

  private func makeVizorWindowToolbar() -> NSToolbar {
    let toolbar = NSToolbar(identifier: "com.zcash.wallet.window-toolbar")
    vizorWindowToolbar = toolbar
    return toolbar
  }
}
