import Cocoa
import FlutterMacOS
#if SPARKLE_ENABLED
import ObjectiveC.runtime
import Sparkle

private let torUpdateTransferTimeout: TimeInterval = 2 * 60 * 60

private final class TorUpdateReleaseNotesURLProtocol: URLProtocol, URLSessionDataDelegate {
  private static let stateLock = NSLock()
  private static var resourceProxyURL: URL?
  private static var allowedReleaseNotesURLs = Set<String>()
  private static var registrationAttempted = false
  private static var isInterceptorInstalled = false

  private var session: URLSession?
  private var proxyTask: URLSessionDataTask?
  private var originalURL: URL?

  static func configure(resourceProxyURL: URL?) {
    stateLock.lock()
    self.resourceProxyURL = resourceProxyURL
    allowedReleaseNotesURLs.removeAll()
    let shouldInstall = !registrationAttempted
    registrationAttempted = true
    stateLock.unlock()

    if shouldInstall {
      let installed = URLSessionConfiguration.installTorUpdateProtocol()
      stateLock.lock()
      isInterceptorInstalled = installed
      stateLock.unlock()
    }
  }

  static func allowReleaseNotes(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https" else { return false }
    stateLock.lock()
    defer { stateLock.unlock() }
    guard resourceProxyURL != nil, isInterceptorInstalled else { return false }
    allowedReleaseNotesURLs.insert(url.absoluteString)
    return true
  }

  static func proxiedURL(for upstreamURL: URL, through resourceProxyURL: URL) -> URL? {
    guard var components = URLComponents(
      url: resourceProxyURL,
      resolvingAgainstBaseURL: false
    ) else {
      return nil
    }
    components.queryItems = [
      URLQueryItem(name: "url", value: upstreamURL.absoluteString),
    ]
    return components.url
  }

  override class func canInit(with request: URLRequest) -> Bool {
    guard let url = request.url, url.scheme?.lowercased() == "https" else {
      return false
    }
    stateLock.lock()
    defer { stateLock.unlock() }
    return isInterceptorInstalled &&
      resourceProxyURL != nil &&
      allowedReleaseNotesURLs.contains(url.absoluteString)
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let upstreamURL = request.url else {
      failWithBlockedRequest()
      return
    }

    Self.stateLock.lock()
    let resourceProxyURL = Self.resourceProxyURL
    let isAllowed = Self.allowedReleaseNotesURLs.contains(upstreamURL.absoluteString)
    Self.stateLock.unlock()

    guard isAllowed,
          let resourceProxyURL,
          let proxyURL = Self.proxiedURL(for: upstreamURL, through: resourceProxyURL) else {
      failWithBlockedRequest()
      return
    }

    NSLog("network privacy: Tor release notes proxy started")

    originalURL = upstreamURL
    var proxyRequest = URLRequest(url: proxyURL)
    proxyRequest.httpMethod = "GET"
    proxyRequest.cachePolicy = .reloadIgnoringLocalCacheData
    proxyRequest.timeoutInterval = torUpdateTransferTimeout

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = []
    configuration.timeoutIntervalForRequest = torUpdateTransferTimeout
    let session = URLSession(
      configuration: configuration,
      delegate: self,
      delegateQueue: nil
    )
    self.session = session
    let task = session.dataTask(with: proxyRequest)
    proxyTask = task
    task.resume()
  }

  override func stopLoading() {
    proxyTask?.cancel()
    proxyTask = nil
    session?.invalidateAndCancel()
    session = nil
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let originalURL,
          let httpResponse = response as? HTTPURLResponse,
          let forwardedResponse = HTTPURLResponse(
            url: originalURL,
            statusCode: httpResponse.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: httpResponse.allHeaderFields.reduce(into: [:]) { headers, entry in
              guard let name = entry.key as? String,
                    let value = entry.value as? String else { return }
              headers[name] = value
            }
          ) else {
      completionHandler(.cancel)
      failWithBlockedRequest()
      return
    }
    client?.urlProtocol(self, didReceive: forwardedResponse, cacheStoragePolicy: .notAllowed)
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    client?.urlProtocol(self, didLoad: data)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      client?.urlProtocol(self, didFailWithError: error)
    } else {
      client?.urlProtocolDidFinishLoading(self)
      NSLog("network privacy: Tor release notes proxy completed")
    }
    proxyTask = nil
    session.finishTasksAndInvalidate()
    self.session = nil
  }

  private func failWithBlockedRequest() {
    client?.urlProtocol(
      self,
      didFailWithError: URLError(.unsupportedURL)
    )
  }
}

private extension URLSessionConfiguration {
  @objc class func vizorTorUpdateDefaultSessionConfiguration() -> URLSessionConfiguration {
    let configuration = vizorTorUpdateDefaultSessionConfiguration()
    var protocolClasses = configuration.protocolClasses ?? []
    if !protocolClasses.contains(where: { $0 == TorUpdateReleaseNotesURLProtocol.self }) {
      protocolClasses.insert(TorUpdateReleaseNotesURLProtocol.self, at: 0)
    }
    configuration.protocolClasses = protocolClasses
    return configuration
  }

  static func installTorUpdateProtocol() -> Bool {
    let defaultSelector = NSSelectorFromString("defaultSessionConfiguration")
    let replacementSelector = #selector(vizorTorUpdateDefaultSessionConfiguration)
    guard let defaultMethod = class_getClassMethod(URLSessionConfiguration.self, defaultSelector),
          let replacementMethod = class_getClassMethod(
            URLSessionConfiguration.self,
            replacementSelector
          ) else {
      return false
    }
    method_exchangeImplementations(defaultMethod, replacementMethod)
    return true
  }
}

private final class TorUpdateFeedDelegate: NSObject, SPUUpdaterDelegate {
  private static let sparkleInstallationCanceledErrorCode = 4007
  private static let directUpdateRetryInterval: TimeInterval = 0.1
  private static let directUpdateRetryTimeout: TimeInterval = 10
  var feedURL: String?
  var resourceProxyURL: URL?
  private var updateCycleDrainCompletions: [() -> Void] = []
  private var pendingDirectUpdateCheck: (() -> Void)?
  private var directUpdateRetryDeadline: DispatchTime?
  private var directUpdateRetryWorkItem: DispatchWorkItem?

  func feedURLString(for updater: SPUUpdater) -> String? {
    return feedURL
  }

  func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
    guard resourceProxyURL != nil, let releaseNotesURL = updateItem.releaseNotesURL else {
      return resourceProxyURL == nil
    }
    return TorUpdateReleaseNotesURLProtocol.allowReleaseNotes(releaseNotesURL)
  }

  func updater(
    _ updater: SPUUpdater,
    shouldProceedWithUpdate updateItem: SUAppcastItem,
    updateCheck: SPUUpdateCheck
  ) throws {
    guard resourceProxyURL != nil else { return }

    let alert = NSAlert()
    alert.alertStyle = .informational
    alert.messageText = "Use Tor for this update?"
    alert.informativeText = "Updating over Tor may take longer. Turning Tor off switches all Vizor network requests to a direct connection."
    alert.addButton(withTitle: "Continue with Tor")
    alert.addButton(withTitle: "Turn off Tor and update")
    alert.addButton(withTitle: "Cancel")

    switch alert.runModal() {
    case .alertFirstButtonReturn:
      return
    case .alertSecondButtonReturn:
      DispatchQueue.main.async { [weak self, weak updater] in
        NativeUpdatePrivacyChannel.requestDisableTorForUpdate { disabled in
          guard let self, let updater else { return }
          guard disabled else {
            self.showTorDisableFailure()
            return
          }
          self.runDirectUpdateCheckWhenReady(updater)
        }
      }
      throw NSError(
        domain: SUSparkleErrorDomain,
        code: Self.sparkleInstallationCanceledErrorCode,
        userInfo: nil
      )
    default:
      throw NSError(
        domain: SUSparkleErrorDomain,
        code: Self.sparkleInstallationCanceledErrorCode,
        userInfo: nil
      )
    }
  }

  func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
    guard let resourceProxyURL else { return }
    guard let upstreamURL = request.url,
          let proxyURL = TorUpdateReleaseNotesURLProtocol.proxiedURL(
            for: upstreamURL,
            through: resourceProxyURL
          ) else {
      request.url = URL(string: "http://127.0.0.1:1/blocked")
      return
    }
    request.url = proxyURL
    request.timeoutInterval = torUpdateTransferTimeout
  }

  func awaitCurrentUpdateCycle(
    updater: SPUUpdater,
    completion: @escaping () -> Void
  ) {
    guard updater.sessionInProgress else {
      completion()
      return
    }
    updateCycleDrainCompletions.append(completion)
  }

  func updater(
    _ updater: SPUUpdater,
    didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
    error: Error?
  ) {
    let completions = updateCycleDrainCompletions
    updateCycleDrainCompletions.removeAll()
    completions.forEach { $0() }
    DispatchQueue.main.async { [weak self, weak updater] in
      guard let self, let updater else { return }
      self.performPendingDirectUpdateCheckIfReady(updater)
    }
  }

  private func runDirectUpdateCheckWhenReady(_ updater: SPUUpdater) {
    pendingDirectUpdateCheck = { updater.checkForUpdates() }
    directUpdateRetryDeadline = .now() + Self.directUpdateRetryTimeout
    performPendingDirectUpdateCheckIfReady(updater)
  }

  private func performPendingDirectUpdateCheckIfReady(_ updater: SPUUpdater) {
    guard let directUpdateCheck = pendingDirectUpdateCheck else {
      return
    }
    if updater.sessionInProgress {
      guard let deadline = directUpdateRetryDeadline, DispatchTime.now() < deadline else {
        pendingDirectUpdateCheck = nil
        directUpdateRetryDeadline = nil
        showDirectUpdateRestartFailure()
        return
      }
      directUpdateRetryWorkItem?.cancel()
      let retry = DispatchWorkItem { [weak self, weak updater] in
        guard let self, let updater else { return }
        self.performPendingDirectUpdateCheckIfReady(updater)
      }
      directUpdateRetryWorkItem = retry
      DispatchQueue.main.asyncAfter(
        deadline: .now() + Self.directUpdateRetryInterval,
        execute: retry
      )
      return
    }
    pendingDirectUpdateCheck = nil
    directUpdateRetryDeadline = nil
    directUpdateRetryWorkItem?.cancel()
    directUpdateRetryWorkItem = nil
    directUpdateCheck()
  }

  private func showDirectUpdateRestartFailure() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Couldn’t restart the update"
    alert.informativeText = "Tor is off. Check for updates again to continue with a direct connection."
    alert.addButton(withTitle: "Close")
    alert.runModal()
  }

  private func showTorDisableFailure() {
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = "Couldn’t turn off Tor"
    alert.informativeText = "Tor remains on. Turn it off in Settings, then check for updates again."
    alert.addButton(withTitle: "Close")
    alert.runModal()
  }
}
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
    appNapActivity = ProcessInfo.processInfo.beginActivity(
      options: .userInitiatedAllowingIdleSystemSleep,
      reason: "Wallet sync and scheduled shielded broadcasts run while hidden"
    )

#if SPARKLE_ENABLED
    configureUpdateMenu(enabled: !Self.persistedTorEnabled())
#else
    checkForUpdatesMenuItem.isHidden = true
    checkForUpdatesMenuItem.isEnabled = false
#endif
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    IncomingUriChannel.handle(urls: urls)
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
      TorUpdateReleaseNotesURLProtocol.configure(resourceProxyURL: nil)
      configureUpdateMenu(enabled: false)
    } else {
      updateFeedDelegate.feedURL = nil
      updateFeedDelegate.resourceProxyURL = nil
      TorUpdateReleaseNotesURLProtocol.configure(resourceProxyURL: nil)
      startUpdaterIfAvailable()
      updaterController?.updater.automaticallyChecksForUpdates = true
      configureUpdateMenu(enabled: true)
    }
    return true
  }

  func prepareForTorDisable(completion: @escaping () -> Void) {
    updaterController?.updater.automaticallyChecksForUpdates = false
    configureUpdateMenu(enabled: false)
    guard let updater = updaterController?.updater else {
      completion()
      return
    }

    // Keep the existing feed and resource proxies installed while an active
    // Sparkle cycle drains. Flutter tears those proxies down only after this
    // completion is delivered.
    updateFeedDelegate.awaitCurrentUpdateCycle(
      updater: updater,
      completion: completion
    )
  }

  func pauseUpdatesForFailClosedStartup(completion: @escaping () -> Void) {
    updaterController?.updater.automaticallyChecksForUpdates = false
    updateFeedDelegate.feedURL = nil
    updateFeedDelegate.resourceProxyURL = nil
    TorUpdateReleaseNotesURLProtocol.configure(resourceProxyURL: nil)
    configureUpdateMenu(enabled: false)

    guard let updater = updaterController?.updater else {
      completion()
      return
    }
    // An already-running Sparkle transfer cannot be rerouted. Delay the
    // fail-closed startup result until that session has fully quiesced, so the
    // Flutter layer cannot report paused traffic while Sparkle is still direct.
    updateFeedDelegate.awaitCurrentUpdateCycle(
      updater: updater,
      completion: completion
    )
  }

  func resumeUpdatesThroughTor(feedURL: String, resourceURL: URL) {
    updateFeedDelegate.feedURL = feedURL
    updateFeedDelegate.resourceProxyURL = resourceURL
    TorUpdateReleaseNotesURLProtocol.configure(resourceProxyURL: resourceURL)
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

  static func requestDisableTorForUpdate(completion: @escaping (Bool) -> Void) {
    guard let channel else {
      completion(false)
      return
    }
    channel.invokeMethod("disableTorForUpdate", arguments: nil) { result in
      if result is FlutterError || result as? NSObject === FlutterMethodNotImplemented {
        completion(false)
        return
      }
      completion(result as? Bool ?? false)
    }
  }

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
      case "prepareForTorDisable":
#if SPARKLE_ENABLED
        guard let delegate = NSApp.delegate as? AppDelegate else {
          result(nil)
          return
        }
        delegate.prepareForTorDisable {
          result(nil)
        }
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
