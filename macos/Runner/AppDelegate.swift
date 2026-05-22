import Cocoa
import FlutterMacOS
#if SPARKLE_ENABLED
import Sparkle
#endif

@main
class AppDelegate: FlutterAppDelegate {
  @IBOutlet private weak var checkForUpdatesMenuItem: NSMenuItem!

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

  override func application(_ application: NSApplication, open urls: [URL]) {
    PaymentUriChannel.handle(urls: urls)
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
