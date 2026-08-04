import Cocoa
import FlutterMacOS
#if SPARKLE_ENABLED
import Sparkle
#endif

@main
class AppDelegate: FlutterAppDelegate {
  @IBOutlet private weak var checkForUpdatesMenuItem: NSMenuItem!

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
  func setTorEnabledForUpdates(_ enabled: Bool) -> Bool {
    if enabled, updaterController?.updater.sessionInProgress == true {
      return false
    }
    if enabled {
      updaterController?.updater.automaticallyChecksForUpdates = false
    } else {
      startUpdaterIfAvailable()
      updaterController?.updater.automaticallyChecksForUpdates = true
    }
    configureUpdateMenu(torEnabled: enabled)
    return true
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
      if (NSApp.delegate as? AppDelegate)?.setTorEnabledForUpdates(enabled) == false {
        result(FlutterError(
          code: "update_in_progress",
          message: "Wait for the current software update operation to finish before enabling Tor.",
          details: nil
        ))
        return
      }
#endif
      result(nil)
    }
  }
}
