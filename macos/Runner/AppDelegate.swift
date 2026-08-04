import Cocoa
import FlutterMacOS
#if SPARKLE_ENABLED
import Sparkle
#endif

@main
class AppDelegate: FlutterAppDelegate {
  @IBOutlet private weak var checkForUpdatesMenuItem: NSMenuItem!

  /// Keeps App Nap from throttling the process while every window is hidden
  /// or occluded. Wallet sync polling and ZIP 318 scheduled migration
  /// broadcasts are Dart-timer driven and intentionally continue while the
  /// app is not visible; App Nap coalesces/suspends those timers, which would
  /// silently stall scheduled broadcasts.
  /// `.userInitiatedAllowingIdleSystemSleep` avoids App Nap without preventing
  /// idle system sleep — a closed lid still suspends the process, which the
  /// migration coordinator detects as an epoch restart.
  private var appNapActivity: NSObjectProtocol?

#if SPARKLE_ENABLED
  private var updaterController: SPUStandardUpdaterController?
#endif

  override init() {
    super.init()
#if SPARKLE_ENABLED
    if !Self.persistedTorEnabled() {
      startUpdaterIfAvailable()
    }
#endif
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    appNapActivity = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep,
      reason: "Wallet sync and scheduled shielded broadcasts run while hidden"
    )

#if SPARKLE_ENABLED
    configureUpdateMenu(torEnabled: Self.persistedTorEnabled())
#else
    checkForUpdatesMenuItem.isHidden = true
    checkForUpdatesMenuItem.isEnabled = false
#endif
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

#if SPARKLE_ENABLED
  func setTorEnabledForUpdates(_ enabled: Bool) {
    if enabled {
      updaterController?.updater.automaticallyChecksForUpdates = false
    } else {
      startUpdaterIfAvailable()
      updaterController?.updater.automaticallyChecksForUpdates = true
    }
    configureUpdateMenu(torEnabled: enabled)
  }

  private func startUpdaterIfAvailable() {
    guard updaterController == nil, Self.sparkleConfigurationIsValid() else {
      return
    }
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  private func configureUpdateMenu(torEnabled: Bool) {
    guard !torEnabled, let updaterController else {
      checkForUpdatesMenuItem.target = nil
      checkForUpdatesMenuItem.action = nil
      checkForUpdatesMenuItem.isEnabled = false
      return
    }
    checkForUpdatesMenuItem.target = updaterController
    checkForUpdatesMenuItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    checkForUpdatesMenuItem.isEnabled = true
  }

  private static func persistedTorEnabled() -> Bool {
    UserDefaults.standard.bool(forKey: "flutter.zcash_tor_enabled")
  }

  private static func sparkleConfigurationIsValid() -> Bool {
    let bundle = Bundle.main
    let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
    let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

    return !(feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
      !(publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }
#endif
}

final class NativeUpdatePrivacyChannel {
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/update_network_privacy",
      binaryMessenger: messenger
    )
    channel = methodChannel
    methodChannel.setMethodCallHandler { call, result in
      guard call.method == "setTorEnabled", let enabled = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
#if SPARKLE_ENABLED
      (NSApp.delegate as? AppDelegate)?.setTorEnabledForUpdates(enabled)
#endif
      result(nil)
    }
  }
}
