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
  /// silently stall scheduled broadcasts. `.background` avoids App Nap
  /// without preventing idle system sleep — a closed lid still suspends the
  /// process, which the migration coordinator detects as an epoch restart.
  private var appNapActivity: NSObjectProtocol?

#if SPARKLE_ENABLED
  private let updaterController: SPUStandardUpdaterController?
#endif

  override init() {
#if SPARKLE_ENABLED
    if Self.sparkleConfigurationIsValid() {
      updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
      )
    } else {
      updaterController = nil
    }
#endif

    super.init()
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    appNapActivity = ProcessInfo.processInfo.beginActivity(
      options: .background,
      reason: "Wallet sync and scheduled shielded broadcasts run while hidden"
    )

#if SPARKLE_ENABLED
    guard let updaterController else {
      checkForUpdatesMenuItem.isEnabled = false
      return
    }

    checkForUpdatesMenuItem.target = updaterController
    checkForUpdatesMenuItem.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
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
  private static func sparkleConfigurationIsValid() -> Bool {
    let bundle = Bundle.main
    let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
    let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

    return !(feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) &&
      !(publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
  }
#endif
}
