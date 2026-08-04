import Cocoa
import FlutterMacOS
#if SPARKLE_ENABLED
import Sparkle

private final class TorUpdateFeedDelegate: NSObject, SPUUpdaterDelegate {
  var feedURL: String?
  var resourceProxyURL: URL?
  private var failClosedPauseCompletions: [() -> Void] = []

  func feedURLString(for updater: SPUUpdater) -> String? {
    return feedURL
  }

  func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
    return resourceProxyURL == nil
  }

  func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
    guard let resourceProxyURL else { return }
    guard let upstreamURL = request.url,
          var components = URLComponents(url: resourceProxyURL, resolvingAgainstBaseURL: false) else {
      request.url = URL(string: "http://127.0.0.1:1/blocked")
      return
    }
    components.queryItems = [URLQueryItem(name: "url", value: upstreamURL.absoluteString)]
    request.url = components.url ?? URL(string: "http://127.0.0.1:1/blocked")
  }

  func awaitCurrentUpdateCycleBeforeFailClosedPause(
    updater: SPUUpdater,
    completion: @escaping () -> Void
  ) {
    guard updater.sessionInProgress else {
      completion()
      return
    }
    failClosedPauseCompletions.append(completion)
  }

  func updater(
    _ updater: SPUUpdater,
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: Error?
  ) {
    let completions = failClosedPauseCompletions
    failClosedPauseCompletions.removeAll()
    completions.forEach { $0() }
  }
}
#endif

@main
class AppDelegate: FlutterAppDelegate {
  @IBOutlet private weak var checkForUpdatesMenuItem: NSMenuItem!

#if SPARKLE_ENABLED
  private var updaterController: SPUStandardUpdaterController?
  private let updateFeedDelegate = TorUpdateFeedDelegate()
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
    configureUpdateMenu(enabled: !Self.persistedTorEnabled())
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
      updateFeedDelegate.feedURL = nil
      updateFeedDelegate.resourceProxyURL = nil
      configureUpdateMenu(enabled: false)
    } else {
      updateFeedDelegate.feedURL = nil
      updateFeedDelegate.resourceProxyURL = nil
      startUpdaterIfAvailable()
      updaterController?.updater.automaticallyChecksForUpdates = true
      configureUpdateMenu(enabled: true)
    }
    return true
  }

  func pauseUpdatesForFailClosedStartup(completion: @escaping () -> Void) {
    updaterController?.updater.automaticallyChecksForUpdates = false
    updateFeedDelegate.feedURL = nil
    updateFeedDelegate.resourceProxyURL = nil
    configureUpdateMenu(enabled: false)

    guard let updater = updaterController?.updater else {
      completion()
      return
    }
    // An already-running Sparkle transfer cannot be rerouted. Delay the
    // fail-closed startup result until that session has fully quiesced, so the
    // Flutter layer cannot report paused traffic while Sparkle is still direct.
    updateFeedDelegate.awaitCurrentUpdateCycleBeforeFailClosedPause(
      updater: updater,
      completion: completion
    )
  }

  func resumeUpdatesThroughTor(feedURL: String, resourceURL: URL) {
    updateFeedDelegate.feedURL = feedURL
    updateFeedDelegate.resourceProxyURL = resourceURL
    startUpdaterIfAvailable()
    updaterController?.updater.automaticallyChecksForUpdates = true
    configureUpdateMenu(enabled: true)
  }

  private func startUpdaterIfAvailable() {
    guard updaterController == nil, Self.sparkleConfigurationIsValid() else {
      return
    }
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: updateFeedDelegate,
      userDriverDelegate: nil
    )
  }

  private func configureUpdateMenu(enabled: Bool) {
    guard enabled, let updaterController else {
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

  static func configuredUpdateFeedURL() -> String? {
    guard sparkleConfigurationIsValid() else { return nil }
    return Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
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
      switch call.method {
      case "setTorEnabled":
        guard let enabled = call.arguments as? Bool else {
          result(FlutterError(code: "invalid_arguments", message: "Expected a Boolean.", details: nil))
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
      case "getUpdateFeedUrl":
#if SPARKLE_ENABLED
        result(AppDelegate.configuredUpdateFeedURL())
#else
        result(nil)
#endif
      case "pauseForFailClosedStartup":
#if SPARKLE_ENABLED
        guard let delegate = NSApp.delegate as? AppDelegate else {
          result(nil)
          return
        }
        delegate.pauseUpdatesForFailClosedStartup {
          result(nil)
        }
#else
        result(nil)
#endif
      case "resumeUpdatesThroughTor":
        guard let arguments = call.arguments as? [String: Any],
              let feedURL = arguments["feedUrl"] as? String,
              let resourceURLString = arguments["resourceUrl"] as? String,
              let url = URL(string: feedURL),
              url.scheme == "http",
              url.host == "127.0.0.1",
              let resourceURL = URL(string: resourceURLString),
              resourceURL.scheme == "http",
              resourceURL.host == "127.0.0.1" else {
          result(FlutterError(
            code: "invalid_proxy_url",
            message: "Expected a loopback HTTP update feed URL.",
            details: nil
          ))
          return
        }
#if SPARKLE_ENABLED
        (NSApp.delegate as? AppDelegate)?.resumeUpdatesThroughTor(
          feedURL: feedURL,
          resourceURL: resourceURL
        )
#endif
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
