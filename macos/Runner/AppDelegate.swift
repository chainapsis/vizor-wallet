import Cocoa
import FlutterMacOS
#if SPARKLE_ENABLED
import Sparkle
#endif

@main
class AppDelegate: FlutterAppDelegate, NSMenuItemValidation {
  @IBOutlet private weak var checkForUpdatesMenuItem: NSMenuItem!

#if SPARKLE_ENABLED
  private var updaterController: SPUStandardUpdaterController?
  private var canCheckForUpdatesObservation: NSKeyValueObservation?
  private var lastCanCheckForUpdates: Bool?
#endif

  override init() {
    super.init()

#if SPARKLE_ENABLED
    if Self.sparkleConfigurationIsValid() {
      updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: nil,
        userDriverDelegate: nil
      )
    } else {
      updaterController = nil
      Self.logInvalidSparkleConfiguration()
    }
#endif
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)

#if SPARKLE_ENABLED
    guard let updaterController else {
      checkForUpdatesMenuItem.isEnabled = false
      return
    }

    checkForUpdatesMenuItem.target = self
    checkForUpdatesMenuItem.action = #selector(checkForUpdates(_:))
    observeSparkleCanCheckForUpdates(updaterController: updaterController)
    updaterController.startUpdater()
    logSparkleState(reason: "started updater")
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

  @objc private func checkForUpdates(_ sender: Any?) {
#if SPARKLE_ENABLED
    guard let updaterController else {
      NSLog("[Sparkle] Ignoring manual update check because the updater is not configured")
      return
    }

    logSparkleState(reason: "manual check requested")
    updaterController.checkForUpdates(sender)
#else
    checkForUpdatesMenuItem?.isEnabled = false
#endif
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
#if SPARKLE_ENABLED
    if menuItem.action == #selector(checkForUpdates(_:)) {
      return updaterController?.updater.canCheckForUpdates ?? false
    }
#endif

    return true
  }

#if SPARKLE_ENABLED
  private func observeSparkleCanCheckForUpdates(updaterController: SPUStandardUpdaterController) {
    canCheckForUpdatesObservation = updaterController.updater.observe(
      \.canCheckForUpdates,
      options: [.initial, .new]
    ) { [weak self] updater, _ in
      DispatchQueue.main.async {
        self?.updateCheckForUpdatesMenuItem(
          canCheckForUpdates: updater.canCheckForUpdates,
          reason: "canCheckForUpdates changed"
        )
      }
    }
  }

  private func updateCheckForUpdatesMenuItem(canCheckForUpdates: Bool, reason: String) {
    checkForUpdatesMenuItem?.isEnabled = canCheckForUpdates

    guard lastCanCheckForUpdates != canCheckForUpdates else {
      return
    }

    lastCanCheckForUpdates = canCheckForUpdates
    NSLog(
      "[Sparkle] Check for Updates menu %@ (%@)",
      canCheckForUpdates ? "enabled" : "disabled",
      reason
    )
  }

  private func logSparkleState(reason: String) {
    guard let updaterController else {
      NSLog("[Sparkle] %@: updater is not configured", reason)
      return
    }

    let updater = updaterController.updater
    NSLog(
      "[Sparkle] %@: feedURL=%@ canCheckForUpdates=%@ sessionInProgress=%@ automaticallyChecksForUpdates=%@",
      reason,
      updater.feedURL?.absoluteString ?? "<nil>",
      updater.canCheckForUpdates ? "true" : "false",
      updater.sessionInProgress ? "true" : "false",
      updater.automaticallyChecksForUpdates ? "true" : "false"
    )
  }

  private static func logInvalidSparkleConfiguration() {
    let bundle = Bundle.main
    let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
    let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

    NSLog(
      "[Sparkle] Updater disabled because configuration is incomplete: hasSUFeedURL=%@ hasSUPublicEDKey=%@",
      (feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? "true" : "false",
      (publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? "true" : "false"
    )
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
