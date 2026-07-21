import BackgroundTasks
import CoreHaptics
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var customHapticEngine: CHHapticEngine?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FreshInstallKeychainCleaner.runIfNeeded()
    BackgroundMigrationManager.shared.registerBackgroundTask()

    if #available(iOS 26.0, *) {
      BackgroundSyncManager.shared.registerBackgroundTask()
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: "com.keplr.vizor.txtrack"
      )
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let backgroundMigrationChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/background_migration",
      binaryMessenger: messenger
    )
    backgroundMigrationChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestNotificationAuthorization":
        BackgroundMigrationManager.shared.requestNotificationAuthorization {
          granted in result(granted)
        }
      case "schedule":
        result(BackgroundMigrationManager.shared.schedule())
      case "cancel":
        BackgroundMigrationManager.shared.cancelIfNoRunnableWork()
        result(true)
      case "quiesce":
        BackgroundMigrationManager.shared.quiesce {
          success in result(success)
        }
      case "resume":
        result(BackgroundMigrationManager.shared.resumeAfterFailedMutation())
      case "revokeAccount":
        guard let arguments = call.arguments as? [String: Any],
          let network = arguments["network"] as? String,
          let accountUuid = arguments["accountUuid"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Missing Ironwood migration account scope.",
              details: nil
            )
          )
          return
        }
        BackgroundMigrationManager.shared.revokeAccount(
          network: network,
          accountUuid: accountUuid,
          completion: { success in result(success) }
        )
      case "revokeAll":
        BackgroundMigrationManager.shared.revokeAll {
          success in result(success)
        }
      #if DEBUG || targetEnvironment(simulator)
      case "runOnceForTesting":
        DispatchQueue.global(qos: .utility).async {
          let outcome = BackgroundMigrationManager.shared.runOnceForTesting()
          DispatchQueue.main.async {
            result(self.backgroundMigrationResult(outcome))
          }
        }
      #endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }

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
      case "sendSuccess":
        result(self.performSendSuccessHaptic())
      case "sendFailure":
        result(self.performSendFailureHaptic())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let sensitiveClipboardChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/sensitive_clipboard",
      binaryMessenger: messenger
    )
    sensitiveClipboardChannel.setMethodCallHandler { (call, result) in
      SensitiveClipboardHandler.handle(call, result: result)
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

    let screenAwakeChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/screen_awake",
      binaryMessenger: messenger
    )
    screenAwakeChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setEnabled":
        guard
          let args = call.arguments as? [String: Any],
          let enabled = args["enabled"] as? Bool
        else {
          result(
            FlutterError(
              code: "bad_args",
              message: "Expected enabled argument.",
              details: nil
            )
          )
          return
        }
        UIApplication.shared.isIdleTimerDisabled = enabled
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

  private func backgroundMigrationResult(
    _ outcome: BackgroundMigrationRunOutcome
  ) -> [String: Any] {
    switch outcome {
    case .noWork:
      return ["outcome": "no_work"]
    case .temporarilyUnavailable:
      return ["outcome": "temporarily_unavailable"]
    case .preparing(let nextHeight, let observedHeight):
      return [
        "outcome": "preparing",
        "nextHeight": nextHeight as Any,
        "observedHeight": observedHeight,
      ]
    case .waiting(let nextHeight, let observedHeight):
      return [
        "outcome": "waiting",
        "nextHeight": nextHeight as Any,
        "observedHeight": observedHeight,
      ]
    case .synced(let nextHeight, let observedHeight):
      return [
        "outcome": "synced",
        "nextHeight": nextHeight as Any,
        "observedHeight": observedHeight,
      ]
    case .advanced(let nextHeight, let observedHeight):
      return [
        "outcome": "advanced",
        "nextHeight": nextHeight as Any,
        "observedHeight": observedHeight,
      ]
    case .complete:
      return ["outcome": "complete"]
    case .needsUserAction:
      return ["outcome": "needs_user_action"]
    case .failed:
      return ["outcome": "failed"]
    case .cancelled:
      return ["outcome": "cancelled"]
    }
  }

  private func performSendSuccessHaptic() -> Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      guard #available(iOS 13.0, *) else {
        return false
      }
      guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
        return false
      }

      do {
        let engine: CHHapticEngine
        if let existingEngine = customHapticEngine {
          engine = existingEngine
        } else {
          engine = try CHHapticEngine()
          customHapticEngine = engine
          engine.stoppedHandler = { [weak self] _ in
            self?.customHapticEngine = nil
          }
          engine.resetHandler = { [weak self] in
            try? self?.customHapticEngine?.start()
          }
        }

        try engine.start()
        let pattern = try CHHapticPattern(
          events: [
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [],
              relativeTime: 0,
              duration: 0.03
            ),
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.00),
              ],
              relativeTime: 0.06,
              duration: 0.04
            ),
          ],
          parameters: []
        )
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
        return true
      } catch {
        return false
      }
    #endif
  }

  private func performSendFailureHaptic() -> Bool {
    #if targetEnvironment(simulator)
      return false
    #else
      guard #available(iOS 13.0, *) else {
        return false
      }
      guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
        return false
      }

      do {
        let engine: CHHapticEngine
        if let existingEngine = customHapticEngine {
          engine = existingEngine
        } else {
          engine = try CHHapticEngine()
          customHapticEngine = engine
          engine.stoppedHandler = { [weak self] _ in
            self?.customHapticEngine = nil
          }
          engine.resetHandler = { [weak self] in
            try? self?.customHapticEngine?.start()
          }
        }

        try engine.start()
        let pattern = try CHHapticPattern(
          events: [
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.70),
              ],
              relativeTime: 0,
              duration: 0.04
            ),
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.70),
              ],
              relativeTime: 0.08,
              duration: 0.04
            ),
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.90),
              ],
              relativeTime: 0.16,
              duration: 0.04
            ),
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.60),
              ],
              relativeTime: 0.24,
              duration: 0.05
            ),
          ],
          parameters: []
        )
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
        return true
      } catch {
        return false
      }
    #endif
  }
}

private enum SensitiveClipboardHandler {
  private static let plainTextType = "public.utf8-plain-text"

  static func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "copyText":
      guard
        let args = call.arguments as? [String: Any],
        let text = args["text"] as? String
      else {
        result(
          FlutterError(
            code: "bad_args",
            message: "Expected text argument.",
            details: nil
          )
        )
        return
      }

      let expirationSeconds = max(1, seconds(from: args["expirationSeconds"]) ?? 60)
      UIPasteboard.general.setItems(
        [[plainTextType: text]],
        options: [
          .expirationDate: Date().addingTimeInterval(expirationSeconds),
          .localOnly: true,
        ]
      )
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func seconds(from value: Any?) -> TimeInterval? {
    if let number = value as? NSNumber {
      return number.doubleValue
    }
    if let int = value as? Int {
      return TimeInterval(int)
    }
    if let double = value as? Double {
      return double
    }
    return nil
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
