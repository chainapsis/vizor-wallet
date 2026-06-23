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

    // MethodChannel for ZIP-321 payment URIs (zcash:). Mirrors the desktop
    // com.zcash.wallet/payment_uri contract (takePendingUris / ready / onUris).
    // The scene delegate feeds inbound URLs into PaymentUriChannelBridge; this
    // app uses the UIScene lifecycle, so application(_:open:) is never called.
    let paymentUriChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/payment_uri",
      binaryMessenger: messenger
    )
    PaymentUriChannelBridge.shared.attach(channel: paymentUriChannel)
    paymentUriChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "takePendingUris":
        result(PaymentUriChannelBridge.shared.takePending())
      case "ready":
        PaymentUriChannelBridge.shared.markReady()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
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

/// Buffers inbound `zcash:` payment URIs until Dart signals readiness, then
/// flushes them over `com.zcash.wallet/payment_uri`. Mirrors the macOS
/// `PaymentUriChannel`. Fed by `SceneDelegate` (this app uses the UIScene
/// lifecycle, so `application(_:open:)` never fires). Lives in this file so it
/// needs no project.pbxproj entry. All access is on the main thread.
final class PaymentUriChannelBridge {
  static let shared = PaymentUriChannelBridge()
  private init() {}

  private var channel: FlutterMethodChannel?
  private var pendingUris: [String] = []
  private var dartReady = false

  func attach(channel: FlutterMethodChannel) {
    self.channel = channel
    // Re-tie readiness to this channel's lifetime: a fresh Flutter engine (new
    // implicit engine -> didInitializeImplicitFlutterEngine -> attach) means the
    // new Dart isolate will register its handler and call `ready` again. The
    // other platforms gate the ready flag on channel/engine lifetime; matching
    // that here keeps a URI that arrives before the new Dart handler is set up
    // buffered (delivered via takePendingUris) instead of pushed via onUris and
    // lost.
    dartReady = false
  }

  func markReady() {
    dartReady = true
    flush()
  }

  func takePending() -> [String] {
    let uris = pendingUris
    pendingUris.removeAll()
    return uris
  }

  /// Extracts `zcash:` URLs from the contexts, buffers them, and flushes if
  /// Dart is ready. Returns `true` when at least one `zcash:` URL was consumed.
  @discardableResult
  func handle(urlContexts: Set<UIOpenURLContext>) -> Bool {
    let strings = urlContexts.compactMap { context -> String? in
      let url = context.url
      guard url.scheme?.lowercased() == "zcash" else { return nil }
      return url.absoluteString
    }
    guard !strings.isEmpty else { return false }
    pendingUris.append(contentsOf: strings)
    flush()
    return true
  }

  private func flush() {
    guard dartReady, let channel, !pendingUris.isEmpty else { return }
    let uris = pendingUris
    pendingUris.removeAll()
    channel.invokeMethod("onUris", arguments: uris)
  }
}
