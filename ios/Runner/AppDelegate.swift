import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FreshInstallKeychainCleaner.runIfNeeded()

    if #available(iOS 26.0, *) {
      BackgroundSyncManager.shared.registerBackgroundTask()
      TxTrackManager.shared.registerTask()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    // MethodChannel for background sync control
    let methodChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/background_sync",
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "isAvailable":
        #if targetEnvironment(simulator)
          result(false)
        #else
          if #available(iOS 26.0, *) {
            result(true)
          } else {
            result(false)
          }
        #endif
      case "startBackgroundSync":
        if #available(iOS 26.0, *) {
          let args = call.arguments as? [String: Any]
          let lightwalletdUrl = args?["lightwalletdUrl"] as? String
          let network = args?["network"] as? String
          let presetId = args?["presetId"] as? String
          let success = BackgroundSyncManager.shared.startBackgroundSync(
            lightwalletdUrl: lightwalletdUrl,
            network: network,
            presetId: presetId
          )
          result(success)
        } else {
          result(false)
        }
      case "stopBackgroundSync":
        if #available(iOS 26.0, *) {
          let success = BackgroundSyncManager.shared.stopBackgroundSync()
          result(success)
        } else {
          result(false)
        }
      case "updateEndpoint":
        let args = call.arguments as? [String: Any]
        let lightwalletdUrl = args?["lightwalletdUrl"] as? String
        let network = args?["network"] as? String
        let presetId = args?["presetId"] as? String
        RpcEndpointConfigStore.save(
          lightwalletdUrl: lightwalletdUrl,
          network: network,
          presetId: presetId
        )
        result(true)
      case "startTxTracking":
        if #available(iOS 26.0, *) {
          let args = call.arguments as? [String: Any]
          let lightwalletdUrl = args?["lightwalletdUrl"] as? String
          let network = args?["network"] as? String
          let presetId = args?["presetId"] as? String
          let success = TxTrackManager.shared.startTxTracking(
            lightwalletdUrl: lightwalletdUrl,
            network: network,
            presetId: presetId
          )
          result(success)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let hapticsChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/haptics",
      binaryMessenger: messenger
    )
    hapticsChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "error":
        // The system's error notification haptic — the triple knock
        // users know from failed Face ID / wrong system passcode.
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let biometricUnlockChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/biometric_unlock",
      binaryMessenger: messenger
    )
    biometricUnlockChannel.setMethodCallHandler { (call, result) in
      BiometricUnlockHandler.shared.handle(call, result: result)
    }

    let deviceOwnerAuthChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/device_owner_auth",
      binaryMessenger: messenger
    )
    deviceOwnerAuthChannel.setMethodCallHandler { (call, result) in
      DeviceOwnerAuthHandler.shared.handle(call, result: result)
    }

    let datePickerChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/date_picker",
      binaryMessenger: messenger
    )
    datePickerChannel.setMethodCallHandler { (call, result) in
      DatePickerHandler.shared.handle(call, result: result)
    }

    let windowAppearanceChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/window_appearance",
      binaryMessenger: messenger
    )
    windowAppearanceChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setBrightness":
        guard
          let args = call.arguments as? [String: Any],
          let brightness = args["brightness"] as? String
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
        WindowAppearanceHandler.setBrightness(brightness)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let cameraPermissionChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/camera_permission",
      binaryMessenger: messenger
    )
    cameraPermissionChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "openSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { success in
          result(success)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // MethodChannel for the native screenshot/recording privacy shield —
    // mirrors the macOS `PrivacyExposureChannel` contract on the shared
    // `privacy_shield` channel. iOS only needs the window-blanking half.
    let privacyShieldChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/privacy_shield",
      binaryMessenger: messenger
    )
    privacyShieldChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setSensitiveContentVisible":
        guard
          let args = call.arguments as? [String: Any],
          let visible = args["visible"] as? Bool
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
        SecureScreenshotShield.shared.setSensitiveContentVisible(visible)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // EventChannel for sync progress (Swift → Dart)
    let eventChannel = FlutterEventChannel(
      name: "com.zcash.wallet/sync_progress",
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(SyncProgressStreamHandler.shared)

    // EventChannel for screenshot detection — sensitive screens (secret
    // passphrase) warn when the user captures them.
    let screenshotChannel = FlutterEventChannel(
      name: "com.zcash.wallet/screenshots",
      binaryMessenger: messenger
    )
    screenshotChannel.setStreamHandler(ScreenshotStreamHandler())
  }
}

private enum WindowAppearanceHandler {
  static func setBrightness(_ brightness: String) {
    let style: UIUserInterfaceStyle
    switch brightness {
    case "dark":
      style = .dark
    case "system":
      style = .unspecified
    default:
      style = .light
    }

    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .forEach { window in
        window.overrideUserInterfaceStyle = style
        window.rootViewController?.overrideUserInterfaceStyle = style
      }
  }
}

/// Streams a tick to Dart whenever iOS reports a user screenshot.
/// Lives in this file so it doesn't need a project.pbxproj entry.
class ScreenshotStreamHandler: NSObject, FlutterStreamHandler {
  private var observer: NSObjectProtocol?

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    observer = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { _ in
      events(true)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
      self.observer = nil
    }
    return nil
  }
}

/// Blanks the whole app window in OS screenshots and screen recordings while a
/// sensitive screen (secret passphrase / import) is showing.
///
/// Uses the canonical `isSecureTextEntry` layer trick: the key window's layer
/// is re-parented into a hidden secure `UITextField`'s canvas layer, which
/// iOS excludes from any capture. Toggling `isSecureTextEntry` then blanks or
/// reveals the window without touching the layer tree again.
///
/// Every step is a defensive no-op on failure (no key window yet, missing
/// superlayer, missing canvas layer). If the private UIKit layout this relies
/// on changes in a future iOS release, the app degrades to its prior behavior
/// (the post-capture screenshot warning sheet) instead of crashing.
///
/// Lives in this file so it needs no `project.pbxproj` entry, matching
/// `ScreenshotStreamHandler`.
final class SecureScreenshotShield {
  static let shared = SecureScreenshotShield()

  // Ported from no_screenshot's open-source iOS-26 technique. The secure-canvas
  // capture exclusion already worked (stills came out black); only geometry was
  // broken on iOS 26.5. Two fixes vs the old code: (1) find the canvas by the
  // secure field's private CANVAS SUBVIEW class name instead of sublayer index
  // (index `.last` grabbed a small offset aux layer on iOS 26.5), and (2) re-pin
  // the reparented window layer to full window bounds so it no longer collapses
  // into a corner. The flag stays as the single kill switch, and the screenshot
  // warning sheet remains the permanent fallback if a future iOS breaks the
  // private-layer layout this relies on.
  private static let isNativeBlankingEnabled = true

  private let secureField = UITextField()
  private var isLayerAttached = false
  private weak var shieldedWindow: UIWindow?
  private weak var canvasLayer: CALayer?
  private var geometryObservers: [NSObjectProtocol] = []

  private init() {}

  /// Idempotent: repeated calls with the same value only toggle the flag, and
  /// the one-time layer setup runs at most once even across Dart hot restarts.
  func setSensitiveContentVisible(_ visible: Bool) {
    guard Self.isNativeBlankingEnabled else { return }
    // MethodChannel callbacks land on the main thread, but never assume it for
    // UIKit access — hop explicitly.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.attachLayerIfNeeded()
      // If the layer could not be attached (no window yet), a later call
      // retries; nothing is toggled until the trick is wired up.
      guard self.isLayerAttached else { return }
      self.reassertWindowGeometry()
      self.secureField.isSecureTextEntry = visible
    }
  }

  private func attachLayerIfNeeded() {
    // Re-graft if not attached, or if the window we grafted into is gone or is
    // no longer the key window — a UIScene can reconnect and hand us a fresh
    // UIWindow. Without this, `isLayerAttached` would latch to a dead window and
    // silently stop blanking: a screenshot would then capture the secret in
    // plaintext with no error and no fallback.
    if isLayerAttached {
      if let attached = shieldedWindow, attached === Self.keyWindow() {
        return
      }
      removeGeometryObservers()
      isLayerAttached = false
      shieldedWindow = nil
      canvasLayer = nil
    }
    guard let window = Self.keyWindow() else { return }

    secureField.isUserInteractionEnabled = false
    secureField.translatesAutoresizingMaskIntoConstraints = false
    // Stop a rightward shift under RTL device languages.
    secureField.semanticContentAttribute = .forceLeftToRight
    secureField.textAlignment = .left

    // Build the field's internal (canvas) layer tree, then detach the field as a
    // SUBVIEW so we never create a circular view hierarchy (an iOS 26 crash
    // trap); only the LAYERS are grafted below.
    window.addSubview(secureField)
    secureField.layoutIfNeeded()
    secureField.removeFromSuperview()

    // Only re-parent once every dependency is present, so a partial failure
    // leaves the window untouched.
    guard let superlayer = window.layer.superlayer else { return }
    guard let canvas = Self.secureCanvasLayer(of: secureField) else { return }

    // Zero the container so the reparented window layer inherits no offset.
    secureField.layer.frame = .zero
    secureField.layer.masksToBounds = false
    canvas.masksToBounds = false

    superlayer.addSublayer(secureField.layer)
    canvas.addSublayer(window.layer)

    shieldedWindow = window
    canvasLayer = canvas
    isLayerAttached = true

    reassertWindowGeometry()
    installGeometryObservers()
  }

  /// Robust canvas identification: prefer the private secure-text canvas subview
  /// by class name (stable across iOS 15..26, unlike the sublayer index), then
  /// the largest-frame sublayer, then the historical index heuristic.
  private static func secureCanvasLayer(of field: UITextField) -> CALayer? {
    if let byName = field.subviews.first(where: {
      String(describing: type(of: $0)).contains("CanvasView")
    }) {
      return byName.layer
    }
    if let biggest = field.layer.sublayers?.max(by: {
      ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
    }) {
      return biggest
    }
    if #available(iOS 17.0, *) { return field.layer.sublayers?.last }
    return field.layer.sublayers?.first
  }

  /// Force the reparented window layer (and the canvas above it) back to full
  /// window bounds at origin zero. UIKit re-lays the window layer on
  /// rotation/scene changes, so this is re-run from the observers and before
  /// each visibility toggle.
  private func reassertWindowGeometry() {
    guard let window = shieldedWindow, let canvas = canvasLayer else { return }
    let full = CGRect(origin: .zero, size: window.bounds.size)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    canvas.frame = full
    canvas.masksToBounds = false
    window.layer.frame = full
    CATransaction.commit()
  }

  private func installGeometryObservers() {
    guard geometryObservers.isEmpty else { return }
    let nc = NotificationCenter.default
    let reassert: (Notification) -> Void = { [weak self] _ in
      DispatchQueue.main.async {
        guard let self else { return }
        // A scene reconnect can swap in a fresh key window while a secret is
        // still on screen, and Dart will not re-send setSensitiveContentVisible
        // (the token set is unchanged). Re-graft to the live window here — a
        // no-op when the window is unchanged — before re-pinning geometry, so
        // the new window is inside the secure canvas and stays blanked.
        if self.isLayerAttached { self.attachLayerIfNeeded() }
        self.reassertWindowGeometry()
      }
    }
    geometryObservers = [
      nc.addObserver(
        forName: UIDevice.orientationDidChangeNotification,
        object: nil, queue: .main, using: reassert
      ),
      nc.addObserver(
        forName: UIScene.didActivateNotification,
        object: nil, queue: .main, using: reassert
      ),
      nc.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil, queue: .main, using: reassert
      ),
    ]
  }

  private func removeGeometryObservers() {
    let nc = NotificationCenter.default
    for observer in geometryObservers {
      nc.removeObserver(observer)
    }
    geometryObservers.removeAll()
  }

  private static func keyWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }
}
