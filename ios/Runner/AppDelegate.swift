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
      // One-release tombstone for requests submitted by the removed general
      // background-sync feature. Do not register a handler for this identifier.
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: "com.keplr.vizor.sync"
      )
      // A BGTask cold-launches the app with a background application state.
      // Cancelling here unconditionally removes the very request iOS is
      // launching us to service. Only a user-driven foreground launch should
      // discard a stale pending preparation request.
      if application.applicationState != .background {
        BackgroundMigrationPreparationManager.shared
          .handoffPendingRequestForForegroundLaunch()
      }
      BackgroundMigrationPreparationManager.shared.registerBackgroundTask()
      BGTaskScheduler.shared.cancel(
        taskRequestWithIdentifier: "com.keplr.vizor.txtrack"
      )
    }
    if application.applicationState != .background {
      IronwoodMigrationNotificationGate.shared.enforceOnForeground()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillEnterForeground(_ application: UIApplication) {
    IronwoodMigrationNotificationGate.shared.enforceOnForeground()
    if #available(iOS 26.0, *) {
      BackgroundMigrationManager.shared.handoffToForeground()
    }
    super.applicationWillEnterForeground(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    let keychainAccessibilityMigrationHandler =
      KeychainAccessibilityMigrationChannel()
    let keychainAccessibilityMigrationChannel = FlutterMethodChannel(
      name: keychainAccessibilityMigrationChannelName,
      binaryMessenger: messenger
    )
    keychainAccessibilityMigrationChannel.setMethodCallHandler { call, result in
      keychainAccessibilityMigrationHandler.handle(call, result: result)
    }

    let backgroundMigrationChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/background_migration",
      binaryMessenger: messenger
    )
    backgroundMigrationChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getNotificationAuthorizationStatus":
        IronwoodMigrationNotificationGate.shared.status { status in
          DispatchQueue.main.async { result(status.rawValue) }
        }
      case "requestNotificationAuthorization":
        IronwoodMigrationNotificationGate.shared.requestAuthorization {
          status in
          if !status.allowsBackgroundMigration {
            IronwoodMigrationNotificationGate.shared.hardDisable()
          }
          DispatchQueue.main.async { result(status.rawValue) }
        }
      case "openNotificationSettings":
        IronwoodMigrationNotificationGate.shared.openSettings {
          opened in result(opened)
        }
      case "schedule":
        BackgroundMigrationManager.shared.schedule { scheduled in
          DispatchQueue.main.async { result(scheduled) }
        }
      case "startPreparation":
        if #available(iOS 26.0, *) {
          BackgroundMigrationPreparationManager.shared.start {
            success in DispatchQueue.main.async { result(success) }
          }
        } else {
          result(false)
        }
      case "supportsPreparationTracking":
        // Denomination-preparation confirmation tracking is a
        // BGContinuedProcessingTask, an iOS 26 API, while the Runner target
        // deploys to iOS 15. On an older build there is no task to submit and
        // no runtime state to report, so `getPreparationRuntimeState` answers
        // `idle` — indistinguishable from "supported but nothing armed yet".
        // Dart therefore asks for the capability separately instead of
        // inferring it from an idle state.
        //
        // This reports the availability of the code path, not a guarantee that
        // a submission will succeed. A submission can still be refused at
        // runtime; that shows up as `startPreparation` returning false, which
        // already leaves the run in its foreground-only presentation.
        if #available(iOS 26.0, *) {
          result(true)
        } else {
          result(false)
        }
      case "getPreparationRuntimeState":
        guard
          let arguments = call.arguments as? [String: Any],
          let network = arguments["network"] as? String,
          let accountUuid = arguments["accountUuid"] as? String,
          let runId = arguments["runId"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Missing Ironwood preparation scope.",
              details: nil
            )
          )
          return
        }
        if #available(iOS 26.0, *) {
          BackgroundMigrationPreparationManager.shared.runtimeState(
            network: network,
            accountUuid: accountUuid,
            runId: runId
          ) { state in
            DispatchQueue.main.async { result(state.rawValue) }
          }
        } else {
          // No continued-processing task exists below iOS 26, so there is
          // genuinely nothing running. Dart must not read this `idle` as
          // "background tracking is possible but not armed" — see
          // `supportsPreparationTracking`.
          result(BackgroundMigrationPreparationRuntimeState.idle.rawValue)
        }
      case "ackPreparationForegroundContinuation":
        guard
          let arguments = call.arguments as? [String: Any],
          let network = arguments["network"] as? String,
          let accountUuid = arguments["accountUuid"] as? String,
          let runId = arguments["runId"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "Missing Ironwood preparation scope.",
              details: nil
            )
          )
          return
        }
        if #available(iOS 26.0, *) {
          BackgroundMigrationPreparationManager.shared
            .acknowledgeForegroundContinuation(
              network: network,
              accountUuid: accountUuid,
              runId: runId
            )
        }
        result(true)
      case "stageOutboxBatch":
        do {
          result(try BackgroundMigrationOutboxChannel.stageBatch(arguments: call.arguments))
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "armOutboxBatch":
        do {
          try BackgroundMigrationOutboxChannel.armBatch(arguments: call.arguments)
          self.completeOutboxArmWithBackgroundSchedule(result: result)
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "recoverOutboxBatch":
        do {
          let recovered = try BackgroundMigrationOutboxChannel.recoverBatch(
            arguments: call.arguments
          )
          if recovered {
            self.completeOutboxArmWithBackgroundSchedule(result: result)
          } else {
            result(false)
          }
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "discardOutboxBatch":
        do {
          // Re-staging follows immediately and arms its own schedule, and
          // discarding can only remove work, so no scheduling change is needed
          // here. The batch id is reused, so notification bookkeeping stays
          // keyed to the same record.
          result(
            try BackgroundMigrationOutboxChannel.discardBatch(
              arguments: call.arguments
            )
          )
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "hasOutboxBatch":
        do {
          result(try BackgroundMigrationOutboxChannel.hasBatch(arguments: call.arguments))
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "recordVerifiedProofReadiness":
        do {
          let shouldSchedule =
            try BackgroundMigrationOutboxChannel.recordVerifiedProofReadiness(
              arguments: call.arguments
            )
          guard shouldSchedule else {
            result(false)
            return
          }
          // Persist first, then request a wake. If submission fails, the
          // pending marker survives and the next foreground status check
          // retries scheduling without announcing readiness twice.
          BackgroundMigrationManager.shared.schedule { _ in
            DispatchQueue.main.async { result(true) }
          }
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "listOutboxReceipts":
        do {
          result(try BackgroundMigrationOutboxChannel.listReceipts())
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "listOutboxAttemptedTxids":
        do {
          result(
            try BackgroundMigrationOutboxChannel.listAttemptedTxids(
              arguments: call.arguments
            )
          )
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "ackOutboxReceipts":
        do {
          try BackgroundMigrationOutboxChannel.acknowledgeReceipts(arguments: call.arguments)
          result(true)
        } catch {
          result(self.backgroundMigrationFlutterError(error))
        }
      case "runOutboxOnceNow":
        DispatchQueue.global(qos: .utility).async {
          let outcome = BackgroundMigrationOutboxChannel.runOnceNow()
          DispatchQueue.main.async { result(self.backgroundOutboxResult(outcome)) }
        }
      case "cancel":
        BackgroundMigrationManager.shared.cancelIfNoRunnableWork()
        if #available(iOS 26.0, *) {
          BackgroundMigrationPreparationManager.shared
            .cancelIfNoActivePreparation()
        }
        result(true)
      case "quiesce":
        BackgroundMigrationManager.shared.quiesce {
          outboxSuccess in
          guard outboxSuccess else {
            result(false)
            return
          }
          if #available(iOS 26.0, *) {
            BackgroundMigrationPreparationManager.shared.quiesce {
              preparationSuccess in result(preparationSuccess)
            }
          } else {
            result(true)
          }
        }
      case "resume":
        BackgroundMigrationManager.shared.resumeAfterFailedMutation {
          resumed in
          if #available(iOS 26.0, *) {
            BackgroundMigrationPreparationManager.shared.resumeAfterMutation()
          }
          DispatchQueue.main.async { result(resumed) }
        }
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
          completion: { success in
            if success {
              if #available(iOS 26.0, *) {
                BackgroundMigrationPreparationManager.shared
                  .cancelIfNoActivePreparation()
              }
            }
            result(success)
          }
        )
      case "revokeAll":
        BackgroundMigrationManager.shared.revokeAll {
          success in
          if success {
            if #available(iOS 26.0, *) {
              BackgroundMigrationPreparationManager.shared
                .cancelIfNoActivePreparation()
            }
          }
          result(success)
        }
      #if DEBUG || targetEnvironment(simulator)
        case "runOnceForTesting":
          DispatchQueue.global(qos: .utility).async {
            let outcome = BackgroundMigrationManager.shared.runOnceForTesting()
            DispatchQueue.main.async {
              result(self.backgroundOutboxResult(outcome))
            }
          }
        case "resumeWithoutSchedulingForTesting":
          result(
            BackgroundMigrationManager.shared
              .resumeWithoutSchedulingForTesting()
          )
      #endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let networkPrivacyChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/network_privacy",
      binaryMessenger: messenger
    )
    networkPrivacyChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "excludeFromBackup":
        // Arti's directory records this wallet's guard choice. Restoring it
        // onto another device would carry that choice across, so it is kept
        // out of iCloud and finder backups; a restored install picks fresh
        // guards at the cost of one bootstrap.
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty
        else {
          result(
            FlutterError(
              code: "invalid_arguments",
              message: "excludeFromBackup requires a path.",
              details: nil
            )
          )
          return
        }
        var url = URL(fileURLWithPath: path)
        do {
          // Created here when it does not exist yet, so the mark can be set
          // before the bootstrap rather than only after it: from the directory's
          // first moment it holds guard state, and the process can be killed
          // while that is being written.
          try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
          )
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try url.setResourceValues(values)
          result(true)
        } catch {
          result(
            FlutterError(
              code: "exclude_failed",
              message: error.localizedDescription,
              details: nil
            )
          )
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

    // MethodChannel for the native screenshot/recording privacy shield —
    // mirrors the macOS `PrivacyExposureChannel` contract on the shared
    // `privacy_shield` channel. iOS only needs the window-blanking half.
    let privacyShieldChannel = FlutterMethodChannel(
      name: "com.zcash.wallet/privacy_shield",
      binaryMessenger: messenger
    )
    privacyShieldChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "setSensitiveContentVisible":
        guard
          let args = call.arguments as? [String: Any],
          let visible = args["visible"] as? Bool
        else {
          result(
            FlutterError(
              code: "bad_args",
              message: "Expected visible argument.",
              details: nil
            )
          )
          return
        }
        SecureScreenshotShield.shared.setSensitiveContentVisible(visible)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // EventChannel for screenshot detection — sensitive screens (secret
    // passphrase) warn when the user captures them.
    let screenshotChannel = FlutterEventChannel(
      name: "com.zcash.wallet/screenshots",
      binaryMessenger: messenger
    )
    screenshotChannel.setStreamHandler(ScreenshotStreamHandler())
  }

  private func completeOutboxArmWithBackgroundSchedule(
    result: @escaping FlutterResult
  ) {
    IronwoodMigrationNotificationGate.shared.status { status in
      guard status.allowsBackgroundMigration else {
        // The durable outbox remains intentionally usable from the foreground
        // when the user declines notifications. Only the background lane is
        // disabled in this mode.
        IronwoodMigrationNotificationGate.shared.hardDisable()
        let success = IronwoodMigrationOutboxArmSchedulePolicy.reportsSuccess(
          authorization: status,
          submitted: false
        )
        DispatchQueue.main.async { result(success) }
        return
      }
      BackgroundMigrationManager.shared.schedule { submitted in
        // With authorization granted, a scheduler submission failure must be
        // surfaced so Dart does not mistake an unscheduled outbox for a
        // background-tracked one.
        let success = IronwoodMigrationOutboxArmSchedulePolicy.reportsSuccess(
          authorization: status,
          submitted: submitted
        )
        DispatchQueue.main.async { result(success) }
      }
    }
  }

  private func backgroundMigrationFlutterError(_ error: Error) -> FlutterError {
    // A conflicting batch is a repairable state, not a generic failure: a batch
    // record exists for this run but cannot deliver its scheduled
    // transactions. Dart distinguishes it by code so recovery can restage the
    // missing items instead of aborting on the inspection call.
    if let outboxError = error as? BackgroundMigrationOutboxError,
      outboxError == .conflictingBatch
    {
      return FlutterError(
        code: "ironwood_outbox_conflicting_batch",
        message: String(describing: error),
        details: nil
      )
    }
    return FlutterError(
      code: "ironwood_outbox_error",
      message: String(describing: error),
      details: nil
    )
  }

  private func backgroundOutboxResult(
    _ runResult: BackgroundMigrationOutboxRunResult
  ) -> [String: Any?] {
    let transport = backgroundTransportResult(runResult.transport)
    var result = transport
    result["transport"] = transport
    result["accountUuid"] = runResult.transportAccountUuid
    if let proofReady = runResult.proofReady {
      result["proofReady"] = [
        "batchId": proofReady.batchId,
        "observedHeight": proofReady.observedHeight,
      ]
    } else {
      result["proofReady"] = NSNull()
    }
    return result
  }

  private func backgroundTransportResult(
    _ outcome: BackgroundMigrationTransportOutcome
  ) -> [String: Any?] {
    switch outcome {
    case .noWork:
      return ["outcome": "noWork"]
    case .waiting(let nextHeight, let observedHeight, let delay):
      return [
        "outcome": "waiting",
        "nextHeight": nextHeight,
        "observedHeight": observedHeight,
        "delaySeconds": delay,
      ]
    case .accepted(let nextHeight, let observedHeight, let delay):
      return [
        "outcome": "accepted",
        "nextHeight": nextHeight,
        "observedHeight": observedHeight,
        "delaySeconds": delay,
      ]
    case .needsUserAction:
      return ["outcome": "needsUserAction"]
    case .temporarilyUnavailable:
      return ["outcome": "temporarilyUnavailable"]
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
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.00)
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
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.70)
              ],
              relativeTime: 0,
              duration: 0.04
            ),
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.70)
              ],
              relativeTime: 0.08,
              duration: 0.04
            ),
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.90)
              ],
              relativeTime: 0.16,
              duration: 0.04
            ),
            CHHapticEvent(
              eventType: .hapticContinuous,
              parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.60)
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

    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    for window in windows {
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

/// Blanks the whole app window in OS screenshots and screen recordings while a
/// sensitive screen (secret passphrase / import) is showing.
///
/// Uses the canonical `isSecureTextEntry` layer trick: the key window's layer
/// is re-parented into a hidden secure `UITextField`'s canvas layer, which
/// iOS excludes from any capture. Toggling `isSecureTextEntry` then blanks or
/// reveals the window without touching the layer tree again.
///
/// Every step is a defensive no-op on failure (no key window yet, missing
/// superlayer, missing canvas layer). If the private UIKit layout this relies
/// on changes in a future iOS release, the app degrades to its prior behavior
/// (the post-capture screenshot warning sheet) instead of crashing.
///
/// Lives in this file so it needs no `project.pbxproj` entry, matching
/// `ScreenshotStreamHandler`.
final class SecureScreenshotShield {
  static let shared = SecureScreenshotShield()

  // Ported from no_screenshot's open-source iOS-26 technique. The secure-canvas
  // capture exclusion already worked (stills came out black); only geometry was
  // broken on iOS 26.5. Two fixes vs the old code: (1) find the canvas by the
  // secure field's private CANVAS SUBVIEW class name instead of sublayer index
  // (index `.last` grabbed a small offset aux layer on iOS 26.5), and (2) re-pin
  // the reparented window layer to full window bounds so it no longer collapses
  // into a corner. The flag stays as the single kill switch, and the screenshot
  // warning sheet remains the permanent fallback if a future iOS breaks the
  // private-layer layout this relies on.
  private static let isNativeBlankingEnabled = true

  private let secureField = UITextField()
  private var isLayerAttached = false
  private weak var shieldedWindow: UIWindow?
  private weak var shieldedWindowLayer: CALayer?
  private weak var canvasLayer: CALayer?
  private var geometryObservers: [NSObjectProtocol] = []

  private init() {}

  /// Idempotent: repeated calls with the same value only toggle the flag, and
  /// the one-time layer setup runs at most once even across Dart hot restarts.
  func setSensitiveContentVisible(_ visible: Bool) {
    guard Self.isNativeBlankingEnabled else { return }
    Self.performOnMain { [weak self] in
      guard let self else { return }
      self.attachLayerIfNeeded()
      // If the layer could not be attached (no window yet), a later call
      // retries; nothing is toggled until the trick is wired up.
      guard self.isLayerAttached else { return }
      self.reassertWindowGeometry()
      self.secureField.isSecureTextEntry = visible
    }
  }

  /// MethodChannel handlers use the main thread by default. Apply inline there
  /// so capture exclusion is enabled before the handler returns; retain a safe
  /// fallback for any future caller that reaches this API off-main.
  static func performOnMain(_ operation: @escaping () -> Void) {
    if Thread.isMainThread {
      operation()
    } else {
      DispatchQueue.main.async(execute: operation)
    }
  }

  private func attachLayerIfNeeded() {
    // Keep the existing graft intact while UIKit temporarily has no key window.
    // If the same window becomes key again, the identity check below reuses it
    // instead of trying to insert the secure field beneath its own descendant.
    guard let window = Self.keyWindow() else { return }

    // Re-graft if not attached, or if the window we grafted into is gone or is
    // no longer the key window — a UIScene can reconnect and hand us a fresh
    // UIWindow. Without this, `isLayerAttached` would latch to a dead window and
    // silently stop blanking: a screenshot would then capture the secret in
    // plaintext with no error and no fallback.
    if isLayerAttached {
      if let attached = shieldedWindow, attached === window {
        return
      }
      Self.restoreLayerHierarchy(
        windowLayer: shieldedWindowLayer,
        secureLayer: secureField.layer
      )
      isLayerAttached = false
      shieldedWindow = nil
      shieldedWindowLayer = nil
      canvasLayer = nil
    }

    secureField.isUserInteractionEnabled = false
    secureField.translatesAutoresizingMaskIntoConstraints = false
    // Stop a rightward shift under RTL device languages.
    secureField.semanticContentAttribute = .forceLeftToRight
    secureField.textAlignment = .left

    // Build the field's internal (canvas) layer tree, then detach the field as a
    // SUBVIEW so we never create a circular view hierarchy (an iOS 26 crash
    // trap); only the LAYERS are grafted below.
    window.addSubview(secureField)
    secureField.layoutIfNeeded()
    secureField.removeFromSuperview()

    // Only re-parent once every dependency is present, so a partial failure
    // leaves the window untouched.
    guard let superlayer = window.layer.superlayer else { return }
    guard let canvas = Self.secureCanvasLayer(of: secureField) else { return }

    // Zero the container so the reparented window layer inherits no offset.
    secureField.layer.frame = .zero
    secureField.layer.masksToBounds = false
    canvas.masksToBounds = false

    superlayer.addSublayer(secureField.layer)
    canvas.addSublayer(window.layer)

    shieldedWindow = window
    shieldedWindowLayer = window.layer
    canvasLayer = canvas
    isLayerAttached = true

    reassertWindowGeometry()
    installGeometryObservers()
  }

  /// Reverses the secure-canvas graft before moving the field to a different
  /// window. The field layer occupies the window layer's former host position,
  /// so restore the window there before attempting another UIKit attachment.
  static func restoreLayerHierarchy(
    windowLayer: CALayer?,
    secureLayer: CALayer
  ) {
    let originalSuperlayer = secureLayer.superlayer
    windowLayer?.removeFromSuperlayer()
    secureLayer.removeFromSuperlayer()
    if let originalSuperlayer, let windowLayer {
      originalSuperlayer.addSublayer(windowLayer)
    }
  }

  /// Robust canvas identification: prefer the private secure-text canvas subview
  /// by class name (stable across iOS 15..26, unlike the sublayer index), then
  /// the largest-frame sublayer, then the historical index heuristic.
  private static func secureCanvasLayer(of field: UITextField) -> CALayer? {
    if let byName = field.subviews.first(where: {
      String(describing: type(of: $0)).contains("CanvasView")
    }) {
      return byName.layer
    }
    if let biggest = field.layer.sublayers?.max(by: {
      ($0.bounds.width * $0.bounds.height) < ($1.bounds.width * $1.bounds.height)
    }) {
      return biggest
    }
    if #available(iOS 17.0, *) { return field.layer.sublayers?.last }
    return field.layer.sublayers?.first
  }

  /// Force the reparented window layer (and the canvas above it) back to full
  /// window bounds at origin zero. UIKit re-lays the window layer on
  /// rotation/scene changes, so this is re-run from the observers and before
  /// each visibility toggle.
  private func reassertWindowGeometry() {
    guard let window = shieldedWindow, let canvas = canvasLayer else { return }
    let full = CGRect(origin: .zero, size: window.bounds.size)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    canvas.frame = full
    canvas.masksToBounds = false
    window.layer.frame = full
    CATransaction.commit()
  }

  private func installGeometryObservers() {
    guard geometryObservers.isEmpty else { return }
    let nc = NotificationCenter.default
    let reassert: (Notification) -> Void = { [weak self] _ in
      guard let self else { return }
      // These observers deliver on the main queue. Re-graft synchronously so a
      // newly active window is protected before UIKit presents its first frame.
      self.attachLayerIfNeeded()
      self.reassertWindowGeometry()

      // Rotation can settle the final window bounds after its notification.
      // Re-pin geometry once more without delaying the security attachment.
      DispatchQueue.main.async { [weak self] in
        self?.reassertWindowGeometry()
      }
    }
    geometryObservers = [
      nc.addObserver(
        forName: UIDevice.orientationDidChangeNotification,
        object: nil, queue: .main, using: reassert
      ),
      nc.addObserver(
        forName: UIScene.didActivateNotification,
        object: nil, queue: .main, using: reassert
      ),
      nc.addObserver(
        forName: UIApplication.didBecomeActiveNotification,
        object: nil, queue: .main, using: reassert
      ),
    ]
  }

  private static func keyWindow() -> UIWindow? {
    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }
}
