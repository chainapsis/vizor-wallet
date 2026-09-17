import BleTransport
import CoreBluetooth
import XCTest

#if os(macOS)
  import FlutterMacOS
#else
  import Flutter
#endif

@testable import Runner

final class LedgerMobileHandlerTests: XCTestCase {
  @MainActor
  func testPermissionRequestWaitsForDecisionAndRejectsConcurrentDeviceWork() async {
    let transport = PendingLedgerTransport()
    var authorization: CBManagerAuthorization = .notDetermined
    let handler = LedgerMobileHandler(transport: transport, authorization: { authorization })
    var results: [Bool] = []
    handler.handle(FlutterMethodCall(methodName: "requestPermissions", arguments: nil)) {
      if let result = $0 as? Bool { results.append(result) }
    }
    XCTAssertTrue(results.isEmpty)
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) {
      XCTAssertNotNil($0 as? FlutterError)
    }
    authorization = .denied
    transport.stateCallback?(.unauthorized)
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(results, [false])
    handler.close()
    XCTAssertEqual(results.count, 1)
  }

  @MainActor
  func testPermissionDeadlineCompletesUnansweredPrompt() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport,
      authorization: { .notDetermined }, permissionTimeout: 1_000_000)
    let finished = expectation(description: "permission deadline")
    handler.handle(FlutterMethodCall(methodName: "requestPermissions", arguments: nil)) {
      XCTAssertEqual($0 as? Bool, false)
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 1)
    handler.close()
  }

  @MainActor
  func testAccessStatusDoesNotCreateBluetoothTransport() {
    let handler = LedgerMobileHandler()
    var status: [String: Any]?
    handler.handle(FlutterMethodCall(methodName: "bluetoothAccessStatus", arguments: nil)) {
      status = $0 as? [String: Any]
    }
    XCTAssertEqual(status?["permissionKind"] as? String, "bluetooth")
    XCTAssertNotNil(status?["permission"])
    // A read-only query must leave the lazy transport uninitialized.
    let storage = Mirror(reflecting: handler).children.first { $0.label == "transportStorage" }
    XCTAssertEqual(Mirror(reflecting: storage!.value).children.count, 0)
    handler.close()
  }

  @MainActor
  func testAppQueryTimeoutAbortsTransportAndAllowsFreshConnection() async {
    let transport = PendingLedgerTransport()
    transport.drainsOnAbort = true
    let handler = LedgerMobileHandler(transport: transport, appQueryTimeout: 10_000_000)
    connect(handler)
    let timedOut = expectation(description: "query timeout")
    var completions = 0
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) {
      completions += 1
      XCTAssertEqual(($0 as? FlutterError)?.code, "disconnected")
      timedOut.fulfill()
    }
    await fulfillment(of: [timedOut], timeout: 2)
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(transport.aborts, 1)
    XCTAssertFalse(transport.hasPendingExchange)
    XCTAssertFalse(transport.isConnected)
    connect(handler)
    transport.responses = ["01055a6361736805332e392e329000"]
    let ready = expectation(description: "new session query")
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) {
      XCTAssertEqual(($0 as? [String: String])?["name"], "Zcash")
      ready.fulfill()
    }
    await fulfillment(of: [ready], timeout: 2)
    XCTAssertEqual(completions, 1)
    handler.close()
  }

  @MainActor
  func testTimeoutKeepsOwnershipUntilAbortActuallyDrains() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport, appQueryTimeout: 10_000_000)
    connect(handler)
    let timedOut = expectation(description: "query timed out")
    var completions = 0
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) { _ in
      completions += 1
      timedOut.fulfill()
    }
    await fulfillment(of: [timedOut], timeout: 2)
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "disconnected")
    }
    transport.complete("01055a6361736805332e392e329000")
    for _ in 0..<20 { await Task.yield() }
    XCTAssertEqual(completions, 1)
    handler.close()
  }

  @MainActor
  func testSigningProgressPrecedesReviewResponseAndStopsAfterCancellation() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    var phases: [String] = []
    handler.onSigningProgress = { id, phase in
      XCTAssertEqual(id, "attempt-1")
      phases.append(phase)
    }
    let started = expectation(description: "review request reached transport")
    transport.onExchange = { started.fulfill() }
    let command: [String: Any] = ["cla": 0xe0, "ins": 0x58, "p1": 0, "p2": 1, "data": [0]]
    handler.handle(FlutterMethodCall(methodName: "exchangeApdus", arguments: [
      "commands": [command], "progressId": "attempt-1"
    ])) { _ in }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertEqual(phases, ["sending", "reviewing"])
    handler.handle(FlutterMethodCall(methodName: "cancelSigning", arguments: nil)) { _ in }
    transport.complete("9000")
    for _ in 0..<10 { await Task.yield() }
    XCTAssertEqual(phases, ["sending", "reviewing"])
    handler.close()
  }

  @MainActor
  func testSigningFinishesOnlyAfterReviewResponse() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    var phases: [String] = []
    handler.onSigningProgress = { _, phase in phases.append(phase) }
    let started = expectation(description: "review sent")
    let finished = expectation(description: "exchange finished")
    transport.onExchange = { started.fulfill() }
    let command: [String: Any] = ["cla": 0xe0, "ins": 0x56, "p1": 1, "p2": 1, "data": [0]]
    handler.handle(FlutterMethodCall(methodName: "exchangeApdus", arguments: [
      "commands": [command], "progressId": "attempt-2"
    ])) { _ in finished.fulfill() }
    await fulfillment(of: [started], timeout: 2)
    XCTAssertEqual(phases, ["sending", "reviewing"])
    transport.complete("9000")
    await fulfillment(of: [finished], timeout: 2)
    XCTAssertEqual(phases, ["sending", "reviewing", "finishing"])
    handler.close()
  }

  func testInvalidPairingIsDistinctFromRejectionAndDisconnection() {
    let invalid = NSError(domain: CBErrorDomain, code: CBError.peerRemovedPairingInformation.rawValue)
    XCTAssertTrue(ledgerPairingInformationIsInvalid(invalid))
    XCTAssertTrue(ledgerPairingInformationIsInvalid(
      BleTransportError.underlying(error: invalid, fallback: .connectError(description: "Connection failed"))))
    XCTAssertFalse(ledgerPairingInformationIsInvalid(
      BleTransportError.connectError(description: invalid.localizedDescription)))
    XCTAssertFalse(ledgerPairingInformationIsInvalid(
      NSError(domain: CBATTErrorDomain, code: invalid.code)))
    XCTAssertFalse(ledgerPairingInformationIsInvalid(
      BleTransportError.pairingError(description: "Rejected")))
    XCTAssertFalse(ledgerPairingInformationIsInvalid(
      NSError(domain: CBErrorDomain, code: CBError.peripheralDisconnected.rawValue)))
  }

  @MainActor
  func testRadioLossSettlesSdkExchangeAndAllowsUserRetry() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "query pending")
    transport.onExchange = { started.fulfill() }
    let failed = expectation(description: "query completed")
    var completions = 0
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) { value in
      completions += 1
      XCTAssertNotNil(value as? FlutterError)
      failed.fulfill()
    }
    await fulfillment(of: [started], timeout: 2)
    transport.failExchangeOnDisconnect()
    await fulfillment(of: [failed], timeout: 2)
    // Let the handler's SDK Task release its operation lease.
    await Task.yield()
    connect(handler)
    transport.onExchange = nil
    transport.responses = ["01055a6361736805332e392e3201029000"]
    let ready = expectation(description: "new query")
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) { value in
      XCTAssertNil(value as? FlutterError)
      ready.fulfill()
    }
    await fulfillment(of: [ready], timeout: 2)
    XCTAssertEqual(completions, 1)
    XCTAssertEqual(transport.connects, 2)
    handler.close()
  }

  @MainActor
  func testPairingCauseWinsOverGenericDisconnectNotification() async {
    let native = NSError(domain: CBErrorDomain, code: CBError.peerRemovedPairingInformation.rawValue)
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "query started")
    transport.onExchange = { started.fulfill() }
    let failed = expectation(description: "pairing failure delivered")
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "pairing_invalid")
      failed.fulfill()
    }
    await fulfillment(of: [started], timeout: 2)
    transport.failExchangeOnDisconnect(BleTransportError.underlying(error: native,
      fallback: .currentConnectedError(description: "Ledger disconnected")))
    await fulfillment(of: [failed], timeout: 2)
    handler.close()
  }

  @MainActor
  func testStructuredPairingFailureReachesFlutterWithNativeIdentity() {
    let native = NSError(domain: CBErrorDomain,
                         code: CBError.peerRemovedPairingInformation.rawValue,
                         userInfo: [NSLocalizedDescriptionKey: "任意の翻訳"])
    let transport = PendingLedgerTransport()
    transport.deferConnectCompletion = true
    let handler = LedgerMobileHandler(transport: transport)
    var results: [Any?] = []
    connect(handler) { results.append($0) }
    transport.failConnect(.underlying(error: native, fallback: .connectError(description: "Generic failure")))
    XCTAssertEqual(results.count, 1)
    let failure = results.first! as? FlutterError
    XCTAssertEqual(failure?.code, "pairing_invalid")
    let details = failure?.details as? [String: Any]
    XCTAssertEqual(details?["nativeDomain"] as? String, CBErrorDomain)
    XCTAssertEqual(details?["nativeCode"] as? Int, native.code)
    XCTAssertFalse(LedgerMobileAppSwitchCoordinator.isTransientTransitionError(
      BleTransportError.underlying(error: native, fallback: .connectError(description: "Generic failure"))))
    handler.close()
  }

  @MainActor
  func testPickerCancellationDrainsLateConnectBeforeReconnect() async {
    let transport = PendingLedgerTransport()
    transport.deferConnectCompletion = true
    transport.deferDisconnectCompletion = true
    let handler = LedgerMobileHandler(transport: transport)
    var results: [Any?] = []
    connect(handler) { results.append($0) }
    handler.handle(FlutterMethodCall(methodName: "cancelSigning", arguments: nil)) { XCTAssertNil($0) }
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual((results[0] as? FlutterError)?.code, "cancelled")
    connect(handler) { XCTAssertEqual(($0 as? FlutterError)?.code, "busy") }
    XCTAssertEqual(transport.connects, 1)
    transport.completeConnect()
    XCTAssertEqual(transport.disconnects, 1)
    XCTAssertEqual(results.count, 1)
    connect(handler) { XCTAssertEqual(($0 as? FlutterError)?.code, "busy") }
    handler.handle(ufvkCall) { XCTAssertEqual(($0 as? FlutterError)?.code, "busy") }
    XCTAssertTrue(transport.commands.isEmpty)
    transport.completeDisconnect()
    transport.deferConnectCompletion = false
    connect(handler)
    XCTAssertEqual(transport.connects, 2)
    XCTAssertTrue(transport.isConnected)
    handler.close()
    transport.completeDisconnect()
  }

  @MainActor
  func testPickerCancellationIgnoresLateConnectFailure() async {
    let transport = PendingLedgerTransport()
    transport.deferConnectCompletion = true
    let handler = LedgerMobileHandler(transport: transport)
    var results: [Any?] = []
    connect(handler) { results.append($0) }
    handler.handle(FlutterMethodCall(methodName: "cancelSigning", arguments: nil)) { XCTAssertNil($0) }
    transport.failConnect()
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual((results[0] as? FlutterError)?.code, "cancelled")
    XCTAssertEqual(transport.disconnects, 0)
    transport.deferConnectCompletion = false
    connect(handler)
    XCTAssertEqual(transport.connects, 2)
    handler.close()
  }

  @MainActor
  func testCancelledConnectRetriesFailedCleanupBeforeNewConnection() async {
    let transport = PendingLedgerTransport()
    transport.deferConnectCompletion = true
    transport.disconnectFailures = 1
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler) { _ in }
    handler.handle(FlutterMethodCall(methodName: "cancelSigning", arguments: nil)) { XCTAssertNil($0) }
    transport.completeConnect()
    XCTAssertTrue(transport.isConnected)
    XCTAssertEqual(transport.disconnects, 1)
    connect(handler) { XCTAssertEqual(($0 as? FlutterError)?.code, "busy") }
    XCTAssertEqual(transport.disconnects, 2)
    XCTAssertEqual(transport.connects, 1)
    XCTAssertFalse(transport.isConnected)
    transport.deferConnectCompletion = false
    connect(handler)
    XCTAssertEqual(transport.connects, 2)
    handler.close()
  }

  @MainActor
  func testCancelledSigningDoesNotSendRemainingCommands() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "signing reached transport")
    transport.onExchange = { started.fulfill() }
    let command: [String: Any] = ["cla": 0xe0, "ins": 0x52, "p1": 0, "p2": 0, "data": []]
    var results: [Any?] = []
    handler.handle(FlutterMethodCall(methodName: "exchangeApdus", arguments: ["commands": [command, command]])) {
      results.append($0)
    }
    await fulfillment(of: [started], timeout: 2)
    handler.handle(FlutterMethodCall(methodName: "cancelSigning", arguments: nil)) { XCTAssertNil($0) }
    XCTAssertEqual(results.compactMap { $0 as? FlutterError }.first?.code, "cancelled")
    transport.onExchange = nil
    transport.complete("9000")
    let deadline = Date().addingTimeInterval(2)
    var disconnected = false
    while !disconnected && Date() < deadline {
      await Task.yield()
      handler.handle(FlutterMethodCall(methodName: "disconnect", arguments: nil)) { disconnected = $0 == nil }
    }
    XCTAssertTrue(disconnected)
    XCTAssertEqual(transport.commands.count, 1)
    XCTAssertEqual(results.count, 1)
    handler.close()
  }

  @MainActor
  func testCancelledUfvkDrainsWithoutContinuationOrDuplicateResult() async {
    // An approved first chunk would normally require another APDU. A rejection
    // must also drain without completing the cancelled Flutter result twice.
    for lateResponse in ["0003759000", "6985"] {
      let transport = PendingLedgerTransport()
      let handler = LedgerMobileHandler(transport: transport)
      connect(handler)
      let started = expectation(description: "UFVK reached transport")
      transport.onExchange = { started.fulfill() }
      var results: [Any?] = []
      handler.handle(ufvkCall) { results.append($0) }
      await fulfillment(of: [started], timeout: 2)

      handler.handle(FlutterMethodCall(methodName: "cancelSigning", arguments: nil)) { value in
        XCTAssertNil(value)
      }
      XCTAssertEqual(results.count, 1)
      XCTAssertEqual(results.compactMap { $0 as? FlutterError }.first?.code, "cancelled")

      // A second import shares the occupied native slot.
      handler.handle(ufvkCall) { value in
        XCTAssertEqual((value as? FlutterError)?.code, "busy")
      }
      handler.handle(FlutterMethodCall(methodName: "disconnect", arguments: nil)) { value in
        XCTAssertEqual((value as? FlutterError)?.message,
          "Finish or reject the pending request on your Ledger, then try again.")
      }
      XCTAssertEqual(transport.disconnects, 0)
      XCTAssertEqual(transport.commands.count, 1)

      transport.onExchange = nil
      transport.complete(lateResponse)
      // Poll the public API until the cancelled task has drained; no sleeps or
      // private state access, and no new transport command until it is safe.
      let deadline = Date().addingTimeInterval(2)
      var disconnected = false
      while !disconnected && Date() < deadline {
        await Task.yield()
        handler.handle(FlutterMethodCall(methodName: "disconnect", arguments: nil)) {
          disconnected = $0 == nil
        }
      }
      XCTAssertTrue(disconnected)
      XCTAssertEqual(results.count, 1)
      XCTAssertEqual(transport.commands.count, 1)
      XCTAssertEqual(transport.disconnects, 1)

      connect(handler)
      transport.responses = ["0001759000"]
      let fresh = expectation(description: "new UFVK completes")
      handler.handle(ufvkCall) { value in
        XCTAssertNil(value as? FlutterError)
        XCTAssertEqual(value as? [[Int]], [[0, 1, 117, 0x90, 0]])
        fresh.fulfill()
      }
      await fulfillment(of: [fresh], timeout: 2)
      XCTAssertEqual(results.count, 1)
      XCTAssertEqual(transport.commands.count, 2)
    }
  }

  @MainActor
  func testCancelledOpenAppDrainsBeforeAnotherTransportOperation() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "open app reached transport")
    transport.onExchange = { started.fulfill() }
    var results: [Any?] = []

    handler.handle(
      FlutterMethodCall(methodName: "openZcashApp", arguments: nil)
    ) { results.append($0) }
    await fulfillment(of: [started], timeout: 2)

    handler.handle(
      FlutterMethodCall(methodName: "cancelSigning", arguments: nil)
    ) { value in
      XCTAssertNil(value)
    }
    XCTAssertEqual(results.compactMap { $0 as? FlutterError }.first?.code, "cancelled")

    handler.handle(FlutterMethodCall(methodName: "disconnect", arguments: nil)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    connect(handler) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    handler.handle(FlutterMethodCall(methodName: "startDiscovery", arguments: nil)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    XCTAssertEqual(transport.disconnects, 0)
    XCTAssertEqual(transport.connects, 1)
    XCTAssertEqual(transport.scans, 0)
    XCTAssertEqual(transport.commands, [LedgerMobileProtocol.openZcashAppCommand])

    transport.onExchange = nil
    transport.complete("9000")
    let deadline = Date().addingTimeInterval(2)
    var disconnected = false
    while !disconnected && Date() < deadline {
      await Task.yield()
      handler.handle(FlutterMethodCall(methodName: "disconnect", arguments: nil)) {
        disconnected = $0 == nil
      }
    }
    XCTAssertTrue(disconnected)
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(transport.commands.count, 1)
    XCTAssertEqual(transport.disconnects, 1)
  }

  @MainActor
  func testOpenAppRecoversFromExpectedDisconnectWithoutCancellingResult() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "open app reached transport")
    transport.onExchange = { started.fulfill() }
    let completed = expectation(description: "open app completed after reconnect")
    var received: Any?

    handler.handle(
      FlutterMethodCall(methodName: "openZcashApp", arguments: nil)
    ) { value in
      received = value
      completed.fulfill()
    }
    await fulfillment(of: [started], timeout: 2)

    transport.simulateDisconnect()
    await Task.yield()
    transport.responses = ["01055a6361736805332e392e3201029000"]
    transport.onExchange = nil
    transport.complete("9000")

    await fulfillment(of: [completed], timeout: 2)
    XCTAssertNil(received as? FlutterError)
    XCTAssertEqual((received as? [String: String])?["name"], "Zcash")
    XCTAssertEqual(transport.reconnects, 1)
    XCTAssertEqual(transport.commands.count, 2)
  }

  @MainActor
  func testDelayedOldDisconnectDoesNotClearReconnectedSession() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "open app reached transport")
    transport.onExchange = { started.fulfill() }
    let opened = expectation(description: "open app completed after reconnect")
    handler.handle(
      FlutterMethodCall(methodName: "openZcashApp", arguments: nil)
    ) { value in
      XCTAssertNil(value as? FlutterError)
      opened.fulfill()
    }
    await fulfillment(of: [started], timeout: 2)

    transport.loseConnectionWithoutCallback()
    transport.responses = ["01055a6361736805332e392e3201029000"]
    transport.onExchange = nil
    transport.complete("9000")
    await fulfillment(of: [opened], timeout: 2)
    XCTAssertEqual(transport.reconnects, 1)
    XCTAssertEqual(transport.disconnectCallbackCount, 2)

    // The original session's notification was queued after the replacement
    // connected. It must not erase the restored device.
    transport.simulateDisconnect(callbackIndex: 0, markDisconnected: false)
    await Task.yield()
    transport.responses = ["01055a6361736805332e392e3201029000"]
    let current = expectation(description: "new session remains connected")
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) { value in
      XCTAssertNil(value as? FlutterError)
      current.fulfill()
    }
    await fulfillment(of: [current], timeout: 2)

    // A disconnect from the replacement session still invalidates it.
    transport.simulateDisconnect(callbackIndex: 1)
    await Task.yield()
    handler.handle(FlutterMethodCall(methodName: "currentApp", arguments: nil)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "disconnected")
    }
  }

  @MainActor
  func testDiscoveryRejectsPendingConnectCallback() {
    let transport = PendingLedgerTransport()
    transport.deferConnectCompletion = true
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler) { _ in }

    handler.handle(FlutterMethodCall(methodName: "startDiscovery", arguments: nil)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    XCTAssertEqual(transport.scans, 0)
    transport.completeConnect()
  }

  @MainActor
  func testCurrentAppUsesTrackedCancellationSlot() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "current app reached transport")
    transport.onExchange = { started.fulfill() }
    var results: [Any?] = []

    handler.handle(
      FlutterMethodCall(methodName: "currentApp", arguments: nil)
    ) { results.append($0) }
    await fulfillment(of: [started], timeout: 2)
    handler.handle(
      FlutterMethodCall(methodName: "cancelSigning", arguments: nil)
    ) { value in
      XCTAssertNil(value)
    }
    handler.handle(
      FlutterMethodCall(methodName: "currentApp", arguments: nil)
    ) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }

    XCTAssertEqual(results.compactMap { $0 as? FlutterError }.first?.code, "cancelled")
    transport.onExchange = nil
    transport.complete("01055a6361736805332e392e3201029000")
    let deadline = Date().addingTimeInterval(2)
    while transport.hasPendingExchange && Date() < deadline {
      await Task.yield()
    }
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(transport.commands.count, 1)
  }

  @MainActor
  func testCloseDefersDisconnectUntilPendingExchangeDrains() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "UFVK reached transport")
    transport.onExchange = { started.fulfill() }
    var results: [Any?] = []
    handler.handle(ufvkCall) { results.append($0) }
    await fulfillment(of: [started], timeout: 2)

    handler.close()
    XCTAssertEqual(results.compactMap { $0 as? FlutterError }.first?.code, "cancelled")
    XCTAssertEqual(transport.disconnects, 0)

    transport.onExchange = nil
    transport.complete("6985")
    let deadline = Date().addingTimeInterval(2)
    while transport.disconnects == 0 && Date() < deadline {
      await Task.yield()
    }
    XCTAssertEqual(results.count, 1)
    XCTAssertEqual(transport.disconnects, 1)
    XCTAssertFalse(transport.isConnected)
  }

  @MainActor
  func testReplacementHandlerWaitsForOldHandlerDrainAndDisconnect() async {
    let transport = PendingLedgerTransport()
    transport.deferDisconnectCompletion = true
    let oldHandler = LedgerMobileHandler(transport: transport)
    connect(oldHandler)
    let started = expectation(description: "old handler exchange reached transport")
    transport.onExchange = { started.fulfill() }
    oldHandler.handle(ufvkCall) { _ in }
    await fulfillment(of: [started], timeout: 2)

    oldHandler.close()
    let replacementHandler = LedgerMobileHandler(transport: transport)
    connect(replacementHandler) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    XCTAssertEqual(transport.connects, 1)
    XCTAssertEqual(transport.disconnects, 0)

    transport.onExchange = nil
    transport.complete("6985")
    let deadline = Date().addingTimeInterval(2)
    while transport.disconnects == 0 && Date() < deadline {
      await Task.yield()
    }
    XCTAssertEqual(transport.disconnects, 1)

    connect(replacementHandler) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    XCTAssertEqual(transport.connects, 1)

    transport.completeDisconnect()
    connect(replacementHandler)
    XCTAssertEqual(transport.connects, 2)
    XCTAssertTrue(transport.isConnected)
    try? await Task.sleep(nanoseconds: 150_000_000)
    XCTAssertEqual(transport.disconnects, 1)
    XCTAssertTrue(transport.isConnected)
  }

  @MainActor
  func testReplacementHandlerWaitsForOldPendingConnectAndCloseDisconnect() async {
    let transport = PendingLedgerTransport()
    transport.deferConnectCompletion = true
    transport.deferDisconnectCompletion = true
    var oldHandler: LedgerMobileHandler? = LedgerMobileHandler(transport: transport)
    connect(oldHandler!) { _ in }

    oldHandler?.close()
    oldHandler = nil
    let replacementHandler = LedgerMobileHandler(transport: transport)
    connect(replacementHandler) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    XCTAssertEqual(transport.connects, 1)
    XCTAssertEqual(transport.disconnects, 0)

    transport.completeConnect()
    await Task.yield()
    XCTAssertEqual(transport.disconnects, 1)
    connect(replacementHandler) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }

    transport.completeDisconnect()
    transport.deferConnectCompletion = false
    connect(replacementHandler)
    XCTAssertEqual(transport.connects, 2)
    XCTAssertTrue(transport.isConnected)
  }

  @MainActor
  func testReplacementHandlerWaitsForOldPendingPublicDisconnect() async {
    let transport = PendingLedgerTransport()
    transport.deferDisconnectCompletion = true
    var oldHandler: LedgerMobileHandler? = LedgerMobileHandler(transport: transport)
    connect(oldHandler!)
    oldHandler?.handle(FlutterMethodCall(methodName: "disconnect", arguments: nil)) { _ in }
    oldHandler?.close()
    oldHandler = nil

    let replacementHandler = LedgerMobileHandler(transport: transport)
    connect(replacementHandler) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    XCTAssertEqual(transport.connects, 1)

    transport.completeDisconnect()
    connect(replacementHandler)
    XCTAssertEqual(transport.connects, 2)
    XCTAssertTrue(transport.isConnected)
  }

  @MainActor
  func testCloseRetriesDisconnectFailureBeforeReleasingReplacement() async {
    let transport = PendingLedgerTransport()
    transport.disconnectFailures = 1
    var oldHandler: LedgerMobileHandler? = LedgerMobileHandler(transport: transport)
    connect(oldHandler!)
    oldHandler?.close()
    oldHandler = nil

    let replacementHandler = LedgerMobileHandler(transport: transport)
    connect(replacementHandler) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "busy")
    }
    XCTAssertEqual(transport.connects, 1)
    XCTAssertTrue(transport.isConnected)

    let deadline = Date().addingTimeInterval(2)
    while transport.disconnects < 2 && Date() < deadline {
      await Task.yield()
    }
    XCTAssertEqual(transport.disconnects, 2)
    XCTAssertFalse(transport.isConnected)

    connect(replacementHandler)
    XCTAssertEqual(transport.connects, 2)
    XCTAssertTrue(transport.isConnected)
  }

  @MainActor
  func testUfvkKeepsNormalMultiCommandResponses() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    transport.responses = ["0003759000", "66769000"]
    let ufvk = expectation(description: "UFVK chunks complete")
    handler.handle(ufvkCall) { value in
      XCTAssertEqual(value as? [[Int]], [[0, 3, 117, 0x90, 0], [102, 118, 0x90, 0]])
      ufvk.fulfill()
    }
    await fulfillment(of: [ufvk], timeout: 2)
    XCTAssertEqual(transport.commands.map { $0[2] }, [0, 0x80])
  }

  private var ufvkCall: FlutterMethodCall {
    FlutterMethodCall(methodName: "exchangeUfvk", arguments: [
      "first": ["cla": 0xe0, "ins": 0x50, "p1": 0, "p2": 0, "data": [0, 0, 0, 0]],
      "continuation": ["cla": 0xe0, "ins": 0x50, "p1": 0x80, "p2": 0, "data": []],
    ])
  }

  private func connect(
    _ handler: LedgerMobileHandler,
    result: @escaping FlutterResult = { value in XCTAssertNil(value) }
  ) {
    handler.handle(FlutterMethodCall(methodName: "connect", arguments: [
      "deviceId": "00000000-0000-0000-0000-000000000001", "deviceName": "Test Ledger"
    ]), result: result)
  }

  func testApduEncodingAlwaysIncludesLc() {
    XCTAssertEqual(
      LedgerMobileApduCommand(
        cla: 0xe0,
        ins: 0x50,
        p1: 0x80,
        p2: 0,
        data: []
      ).encoded,
      [0xe0, 0x50, 0x80, 0x00, 0x00]
    )
    XCTAssertEqual(
      LedgerMobileApduCommand(
        cla: 0xe0,
        ins: 0xd8,
        p1: 0,
        p2: 0,
        data: [0x5a, 0x63]
      ).encoded,
      [0xe0, 0xd8, 0x00, 0x00, 0x02, 0x5a, 0x63]
    )
  }

  func testHexResponseParsingRejectsMalformedInput() throws {
    XCTAssertEqual(
      try LedgerMobileProtocol.bytes(fromHex: "01029000"),
      [0x01, 0x02, 0x90, 0x00]
    )
    XCTAssertThrowsError(try LedgerMobileProtocol.bytes(fromHex: "123"))
    XCTAssertThrowsError(try LedgerMobileProtocol.bytes(fromHex: "zz"))
  }

  func testAppInfoParsingPreservesNameAndVersion() throws {
    let response = try LedgerMobileProtocol.bytes(
      fromHex: "01055a6361736805332e392e3201029000"
    )
    XCTAssertEqual(
      try LedgerMobileProtocol.appInfo(from: response),
      LedgerMobileAppInfo(name: "Zcash", version: "3.9.2")
    )
  }

  func testAppInfoParsingSurfacesStatusAndTruncation() {
    XCTAssertThrowsError(
      try LedgerMobileProtocol.appInfo(from: [0x55, 0x15])
    ) { error in
      XCTAssertEqual(error as? LedgerMobileProtocolError, .status(0x5515))
    }
    XCTAssertThrowsError(
      try LedgerMobileProtocol.appInfo(
        from: [0x01, 0x05, 0x5a, 0x90, 0x00]
      )
    )
  }

  func testAppSwitchContinuesWhenLedgerKeepsBleConnected() async throws {
    var events: [String] = []
    var appReads = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(
      waitBetweenAttempts: { _ in }
    )

    let app = try await coordinator.openZcashApp(
      openApplication: { events.append("open") },
      isConnected: { true },
      reconnect: {
        XCTFail("A retained BLE session must not reconnect")
      },
      readCurrentApp: {
        appReads += 1
        events.append("app")
        return LedgerMobileAppInfo(
          name: appReads == 1 ? "BOLOS" : "Zcash",
          version: appReads == 1 ? "2.4.1" : "3.9.2"
        )
      }
    )
    events.append("ufvk")

    XCTAssertEqual(app, LedgerMobileAppInfo(name: "Zcash", version: "3.9.2"))
    XCTAssertEqual(events, ["open", "app", "app", "ufvk"])
  }

  func testAppSwitchReconnectsTheSelectedLedgerAfterDisconnect() async throws {
    var connected = true
    var reconnects = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(
      waitBetweenAttempts: { _ in }
    )

    let app = try await coordinator.openZcashApp(
      openApplication: { connected = false },
      isConnected: { connected },
      reconnect: {
        reconnects += 1
        connected = true
      },
      readCurrentApp: {
        LedgerMobileAppInfo(name: "Zcash", version: "3.9.2")
      }
    )

    XCTAssertEqual(reconnects, 1)
    XCTAssertEqual(app, LedgerMobileAppInfo(name: "Zcash", version: "3.9.2"))
  }

  func testOpenZcashApduAndStatusValidation() throws {
    XCTAssertEqual(
      LedgerMobileProtocol.openZcashAppCommand,
      [0xe0, 0xd8, 0x00, 0x00, 0x05, 0x5a, 0x63, 0x61, 0x73, 0x68]
    )
    XCTAssertNoThrow(try LedgerMobileProtocol.requireSuccess([0x90, 0x00]))
    XCTAssertThrowsError(
      try LedgerMobileProtocol.requireSuccess([0x69, 0x85])
    ) { error in
      XCTAssertEqual(error as? LedgerMobileProtocolError, .status(0x6985))
    }
  }

  @MainActor
  func testOpenZcashAppMapsRawMissingAppAndLockedStatuses() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let cases: [(response: String, code: String, message: String)] = [
      ("6807", "unavailable", "The Zcash app is not installed on this Ledger."),
      ("5515", "locked", "Unlock your Ledger and reopen the Zcash app."),
      ("6982", "locked", "Unlock your Ledger and reopen the Zcash app."),
      ("5303", "locked", "Unlock your Ledger and reopen the Zcash app."),
    ]

    for testCase in cases {
      transport.responses = [testCase.response]
      let completed = expectation(description: "mapped status \(testCase.response)")
      handler.handle(
        FlutterMethodCall(methodName: "openZcashApp", arguments: nil)
      ) { value in
        let error = value as? FlutterError
        XCTAssertEqual(error?.code, testCase.code)
        XCTAssertEqual(error?.message, testCase.message)
        completed.fulfill()
      }
      await fulfillment(of: [completed], timeout: 2)
    }
  }

  func testAppSwitchRecoversLostOpenResponseWithoutOpeningTwice() async throws {
    var opens = 0
    var reads = 0
    let app = try await LedgerMobileAppSwitchCoordinator().openZcashApp(
      openApplication: {
        opens += 1
        throw BleTransportError.readError(description: "App switched before reply")
      },
      isConnected: { true },
      reconnect: { XCTFail("The retained session needs no reconnect") },
      readCurrentApp: {
        reads += 1
        return LedgerMobileAppInfo(name: "Zcash", version: "3.9.3")
      }
    )
    XCTAssertEqual(app.name, "Zcash")
    XCTAssertEqual(opens, 1)
    XCTAssertEqual(reads, 1)
  }

  func testAppSwitchUsesTimeBudgetInsteadOfThreeFastReconnectFailures() async throws {
    var now: TimeInterval = 0
    var connected = false
    var reconnects = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(
      now: { now },
      waitBetweenAttempts: { now += $0 }
    )
    let app = try await coordinator.openZcashApp(
      openApplication: {},
      isConnected: { connected },
      reconnect: {
        reconnects += 1
        if now < 1 { throw BleTransportError.connectError(description: "Not ready") }
        connected = true
      },
      readCurrentApp: { LedgerMobileAppInfo(name: "Zcash", version: "3.9.3") }
    )
    XCTAssertEqual(app.name, "Zcash")
    XCTAssertEqual(reconnects, 5)
    XCTAssertEqual(now, 1)
  }

  func testAppSwitchWaitsThroughBusyResponsesButHasAnElapsedTimeLimit() async throws {
    var now: TimeInterval = 0
    var reads = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(
      recoveryTimeout: 1,
      now: { now },
      waitBetweenAttempts: { now += $0 }
    )
    do {
      _ = try await coordinator.openZcashApp(
        openApplication: { throw LedgerMobileProtocolError.status(0x6601) },
        isConnected: { true },
        reconnect: { XCTFail("No reconnect needed") },
        readCurrentApp: {
          reads += 1
          throw LedgerMobileProtocolError.status(0x6901)
        }
      )
      XCTFail("An app that stays busy must not become ready")
    } catch {
      XCTAssertEqual(error as? LedgerMobileProtocolError, .status(0x6901))
    }
    XCTAssertEqual(reads, 4)
    XCTAssertEqual(now, 1)
  }

  func testAppSwitchDoesNotChargeUserApprovalTimeToRecovery() async throws {
    var now: TimeInterval = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(now: { now })
    let app = try await coordinator.openZcashApp(
      openApplication: { now = 60 },
      isConnected: { true },
      reconnect: {},
      readCurrentApp: { LedgerMobileAppInfo(name: "Zcash", version: "3.9.3") }
    )
    XCTAssertEqual(app.name, "Zcash")
  }

  func testAppSwitchStopsAfterSlowReconnectConsumesBudget() async throws {
    var now: TimeInterval = 0
    var connected = false
    var reads = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(now: { now })
    do {
      _ = try await coordinator.openZcashApp(
        openApplication: {},
        isConnected: { connected },
        reconnect: { now = 11; connected = true },
        readCurrentApp: {
          reads += 1
          return LedgerMobileAppInfo(name: "Zcash", version: "3.9.3")
        }
      )
      XCTFail("Do not start another request after the budget expires")
    } catch {
      XCTAssertEqual(error as? LedgerMobileProtocolError, .appSwitchTimedOut(nil))
    }
    XCTAssertEqual(reads, 0)
  }

  func testAppSwitchNeverRetriesTerminalErrorsFromOpeningOrPolling() async throws {
    let errors: [Error] = [
      LedgerMobileProtocolError.status(0x6985),
      LedgerMobileProtocolError.status(0x5501),
      LedgerMobileProtocolError.status(0x5515),
      LedgerMobileProtocolError.status(0x6807),
      LedgerMobileProtocolError.invalidAppInfo,
      BleTransportError.userRefusedOnDevice,
      BleTransportError.bluetoothNotAvailable,
      BleTransportError.pairingError(description: "Denied"),
      CancellationError(),
    ]
    for error in errors {
      for failureDuringOpen in [true, false] {
        var reads = 0
        var waits = 0
        let coordinator = LedgerMobileAppSwitchCoordinator(
          waitBetweenAttempts: { _ in waits += 1 }
        )
        do {
          _ = try await coordinator.openZcashApp(
            openApplication: { if failureDuringOpen { throw error } },
            isConnected: { true },
            reconnect: { XCTFail("A terminal error must not reconnect") },
            readCurrentApp: { reads += 1; throw error }
          )
          XCTFail("A terminal error must fail")
        } catch let received {
          XCTAssertEqual(String(reflecting: received), String(reflecting: error))
        }
        XCTAssertEqual(waits, 0)
        XCTAssertEqual(reads, failureDuringOpen ? 0 : 1)
      }
    }
  }

  func testAppSwitchCancellationRejectsLateReadyResponse() async throws {
    var cancelled = false
    do {
      _ = try await LedgerMobileAppSwitchCoordinator().openZcashApp(
        openApplication: {},
        isConnected: { true },
        reconnect: {},
        readCurrentApp: {
          cancelled = true
          return LedgerMobileAppInfo(name: "Zcash", version: "3.9.3")
        },
        isCancelled: { cancelled }
      )
      XCTFail("Cancelled preparation must not allow a signing request")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
  }

  func testAppSwitchReturnsAsSoonAsBusyStateClears() async throws {
    var now: TimeInterval = 0
    var reads = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(
      now: { now },
      waitBetweenAttempts: { now += $0 }
    )
    let app = try await coordinator.openZcashApp(
      openApplication: {},
      isConnected: { true },
      reconnect: { XCTFail("No reconnect needed") },
      readCurrentApp: {
        reads += 1
        if now < 0.5 { throw LedgerMobileProtocolError.status(0x6901) }
        return LedgerMobileAppInfo(name: "Zcash", version: "3.9.3")
      }
    )
    XCTAssertEqual(app.name, "Zcash")
    XCTAssertEqual(now, 0.5)
    XCTAssertEqual(reads, 3)
  }

  func testAppSwitchCancellationDuringWaitStopsFurtherRequests() async throws {
    var now: TimeInterval = 0
    var cancelled = false
    var reads = 0
    let coordinator = LedgerMobileAppSwitchCoordinator(
      now: { now },
      waitBetweenAttempts: { now += $0; cancelled = true }
    )
    do {
      _ = try await coordinator.openZcashApp(
        openApplication: {},
        isConnected: { true },
        reconnect: { XCTFail("No reconnect needed") },
        readCurrentApp: {
          reads += 1
          return LedgerMobileAppInfo(name: "BOLOS", version: "2.4.1")
        },
        isCancelled: { cancelled }
      )
      XCTFail("Cancelled preparation must stop polling")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertEqual(reads, 1)
  }
}

// The real handler and SDK protocol run in these tests, but there is no BLE
// radio. A pending exchange deliberately ignores Task cancellation, like 1.0.1.
private final class PendingLedgerTransport: BleTransportProtocol {
  static var shared: BleTransportProtocol { fatalError("Inject the test transport") }
  var isBluetoothAvailable = true
  var isConnected = false
  var commands: [[UInt8]] = []
  var responses: [String] = []
  var disconnects = 0
  var reconnects = 0
  var connects = 0
  var scans = 0
  var aborts = 0
  var drainsOnAbort = false
  var deferConnectCompletion = false
  var deferDisconnectCompletion = false
  var disconnectFailures = 0
  var onExchange: (() -> Void)?
  private var pending: CheckedContinuation<String, Error>?
  private var disconnectedCallbacks: [DisconnectionResponse] = []
  private var deferredConnect: (PeripheralIdentifier, PeripheralResponse)?
  private var deferredConnectFailure: BleErrorResponse?
  private var deferredDisconnectCompletion: OptionalBleErrorResponse?

  var hasPendingExchange: Bool { pending != nil }
  var disconnectCallbackCount: Int { disconnectedCallbacks.count }

  func complete(_ response: String) {
    let continuation = pending
    pending = nil
    continuation?.resume(returning: response)
  }
  func exchange(apdu: APDU) async throws -> String {
    commands.append(Array(apdu.data))
    if !responses.isEmpty { return responses.removeFirst() }
    return try await withCheckedThrowingContinuation {
      pending = $0
      onExchange?()
    }
  }
  func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: DisconnectionResponse?,
    success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse) {
    connects += 1
    isConnected = true
    if let disconnectedCallback { disconnectedCallbacks.append(disconnectedCallback) }
    if deferConnectCompletion {
      deferredConnect = (peripheral, success)
      deferredConnectFailure = failure
    } else {
      success(peripheral)
    }
  }

  func completeConnect() {
    guard let deferred = deferredConnect else { return }
    deferredConnect = nil
    deferredConnectFailure = nil
    deferred.1(deferred.0)
  }
  func failConnect(_ error: BleTransportError = .connectError(description: "Late failure")) {
    let failure = deferredConnectFailure
    deferredConnect = nil
    deferredConnectFailure = nil
    isConnected = false
    failure?(error)
  }
  func abortExchange() {
    aborts += 1
    guard drainsOnAbort else { return } // Model a non-cooperative SDK in legacy tests.
    isConnected = false
    let continuation = pending
    pending = nil
    continuation?.resume(throwing: BleTransportError.currentConnectedError(description: "Aborted"))
  }
  func disconnect(completion: OptionalBleErrorResponse?) {
    XCTAssertNil(pending, "Must not enter the SDK's pending-disconnect wait")
    disconnects += 1
    if disconnectFailures > 0 {
      disconnectFailures -= 1
      isConnected = true
      completion?(BleTransportError.connectError(description: "Disconnect failed"))
      return
    }
    isConnected = false
    if deferDisconnectCompletion {
      deferredDisconnectCompletion = completion
    } else {
      completion?(nil)
    }
  }

  func completeDisconnect() {
    let completion = deferredDisconnectCompletion
    deferredDisconnectCompletion = nil
    completion?(nil)
  }
  func stopScanning() {}
  func scan(duration: TimeInterval, callback: @escaping PeripheralsWithServicesResponse,
    stopped: @escaping OptionalBleErrorResponse) { scans += 1 }
  func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: DisconnectionResponse?) async throws -> PeripheralIdentifier {
    reconnects += 1
    isConnected = true
    if let disconnectedCallback { disconnectedCallbacks.append(disconnectedCallback) }
    return peripheral
  }
  func create(scanDuration: TimeInterval, disconnectedCallback: DisconnectionResponse?, success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse) { XCTFail("unused") }
  func create(scanDuration: TimeInterval, disconnectedCallback: DisconnectionResponse?) async throws -> PeripheralIdentifier { fatalError("unused") }
  func exchange(apdu: APDU, callback: @escaping (Result<String, BleTransportError>) -> Void) { XCTFail("unused") }
  func send(apdu: APDU, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse) { XCTFail("unused") }
  func send(apdu: APDU) async throws { XCTFail("unused") }
  func disconnect() async throws { disconnect(completion: nil) }
  func bluetoothAvailabilityCallback(completion: @escaping (Bool) -> Void) {}
  var stateCallback: ((CBManagerState) -> Void)?
  func bluetoothStateCallback(completion: @escaping (CBManagerState) -> Void) { stateCallback = completion }
  func bluetoothStateCallback() async -> CBManagerState { .poweredOn }
  func notifyDisconnected(completion: @escaping EmptyResponse) {}
  func getAppAndVersion(success: @escaping (AppInfo) -> Void, failure: @escaping ErrorResponse) { XCTFail("unused") }
  func getAppAndVersion() async throws -> AppInfo { fatalError("unused") }
  func openAppIfNeeded(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) { XCTFail("unused") }
  func openAppIfNeeded(_ name: String) async throws { XCTFail("unused") }

  func loseConnectionWithoutCallback() {
    isConnected = false
  }

  func failExchangeOnDisconnect(_ error: Error = BleTransportError.currentConnectedError(description: "Ledger disconnected")) {
    let continuation = pending
    pending = nil
    isConnected = false
    continuation?.resume(throwing: error)
    simulateDisconnect(error: error)
  }

  func simulateDisconnect(callbackIndex: Int? = nil, markDisconnected: Bool = true, error: Error? = nil) {
    if markDisconnected { isConnected = false }
    let index = callbackIndex ?? disconnectedCallbacks.index(before: disconnectedCallbacks.endIndex)
    disconnectedCallbacks[index](error)
  }
}
