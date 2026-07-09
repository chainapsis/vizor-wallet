import Flutter
import UIKit
import WidgetKit

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
    FamiliarWidgetStore.purgeLegacyAccountName()
    FamiliarWidgetReloader.reload()
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

    let familiarWidgetChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/familiar_widget",
      binaryMessenger: messenger
    )
    familiarWidgetChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "updateFamiliar":
        let args = call.arguments as? [String: Any]
        let saved = FamiliarWidgetStore.save(
          profilePictureId: args?["profilePictureId"] as? String
        )
        FamiliarWidgetReloader.reload()
        result(saved)
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
}

private enum FamiliarWidgetStore {
  private static let defaults = UserDefaults(suiteName: "group.com.keplr.vizor")
  private static let profilePictureIdKey = "familiar_widget_profile_picture_id"
  private static let accountNameKey = "familiar_widget_account_name"
  private static let revisionKey = "familiar_widget_revision"

  static func save(profilePictureId: String?) -> Bool {
    guard let defaults else { return false }
    defaults.set(profilePictureId ?? "pfp-01", forKey: profilePictureIdKey)
    purgeLegacyAccountName()
    defaults.set(Date().timeIntervalSince1970, forKey: revisionKey)
    return defaults.synchronize()
  }

  /// The account name must never reach the unauthenticated widget surface.
  /// Remove any value written by an earlier build of this feature so it does
  /// not linger in the App Group plist at rest, even if the user never
  /// triggers another account mutation on this build.
  static func purgeLegacyAccountName() {
    defaults?.removeObject(forKey: accountNameKey)
  }
}

private enum FamiliarWidgetReloader {
  private static let kind = "SyncWidget"

  static func reload() {
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
    WidgetCenter.shared.reloadAllTimelines()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
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
