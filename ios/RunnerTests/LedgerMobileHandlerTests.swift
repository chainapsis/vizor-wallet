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

      // Both a second import and signing share the occupied native slot.
      for call in [ufvkCall, signingCall] {
        handler.handle(call) { value in
          XCTAssertEqual((value as? FlutterError)?.code, "unavailable")
        }
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
  func testUfvkAndSigningKeepNormalMultiCommandResponses() async {
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
    transport.responses = ["9000", "6985"]
    let signing = expectation(description: "signing responses complete")
    handler.handle(signingCall) { value in
      XCTAssertEqual(value as? [[Int]], [[0x90, 0], [0x69, 0x85]])
      signing.fulfill()
    }
    await fulfillment(of: [signing], timeout: 2)
  }

  @MainActor
  func testCancelledSigningAlsoBlocksUfvkUntilTheResponseDrains() async {
    let transport = PendingLedgerTransport()
    let handler = LedgerMobileHandler(transport: transport)
    connect(handler)
    let started = expectation(description: "signing reached transport")
    transport.onExchange = { started.fulfill() }
    var results: [Any?] = []
    handler.handle(signingCall) { results.append($0) }
    await fulfillment(of: [started], timeout: 2)
    handler.handle(FlutterMethodCall(methodName: "cancelSigning", arguments: nil)) { _ in }
    handler.handle(ufvkCall) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "unavailable")
    }
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
    XCTAssertEqual(results.compactMap { $0 as? FlutterError }.first?.code, "cancelled")
    XCTAssertEqual(transport.commands.count, 1)
  }

  private var ufvkCall: FlutterMethodCall {
    FlutterMethodCall(methodName: "exchangeUfvk", arguments: [
      "first": ["cla": 0xe0, "ins": 0x50, "p1": 0, "p2": 0, "data": [0, 0, 0, 0]],
      "continuation": ["cla": 0xe0, "ins": 0x50, "p1": 0x80, "p2": 0, "data": []],
    ])
  }

  private var signingCall: FlutterMethodCall {
    FlutterMethodCall(methodName: "exchangeApdus", arguments: [
      "commands": [
        ["cla": 0xe0, "ins": 0x52, "p1": 0, "p2": 0, "data": []],
        ["cla": 0xe0, "ins": 0x52, "p1": 1, "p2": 0, "data": []],
      ]
    ])
  }

  private func connect(_ handler: LedgerMobileHandler) {
    handler.handle(FlutterMethodCall(methodName: "connect", arguments: [
      "deviceId": "00000000-0000-0000-0000-000000000001", "deviceName": "Test Ledger"
    ])) { value in XCTAssertNil(value) }
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
  var onExchange: (() -> Void)?
  private var pending: CheckedContinuation<String, Error>?

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
  func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: EmptyResponse?,
    success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse) {
    isConnected = true
    success(peripheral)
  }
  func disconnect(completion: OptionalBleErrorResponse?) {
    XCTAssertNil(pending, "Must not enter the SDK's pending-disconnect wait")
    disconnects += 1
    isConnected = false
    completion?(nil)
  }
  func stopScanning() {}
  func scan(duration: TimeInterval, callback: @escaping PeripheralsWithServicesResponse,
    stopped: @escaping OptionalBleErrorResponse) { XCTFail("Unexpected scan") }
  func connect(toPeripheralID peripheral: PeripheralIdentifier, disconnectedCallback: EmptyResponse?) async throws -> PeripheralIdentifier { fatalError("unused") }
  func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?, success: @escaping PeripheralResponse, failure: @escaping BleErrorResponse) { XCTFail("unused") }
  func create(scanDuration: TimeInterval, disconnectedCallback: EmptyResponse?) async throws -> PeripheralIdentifier { fatalError("unused") }
  func exchange(apdu: APDU, callback: @escaping (Result<String, BleTransportError>) -> Void) { XCTFail("unused") }
  func send(apdu: APDU, success: @escaping EmptyResponse, failure: @escaping BleErrorResponse) { XCTFail("unused") }
  func send(apdu: APDU) async throws { XCTFail("unused") }
  func disconnect() async throws { disconnect(completion: nil) }
  func bluetoothAvailabilityCallback(completion: @escaping (Bool) -> Void) {}
  func bluetoothStateCallback(completion: @escaping (CBManagerState) -> Void) {}
  func bluetoothStateCallback() async -> CBManagerState { .poweredOn }
  func notifyDisconnected(completion: @escaping EmptyResponse) {}
  func getAppAndVersion(success: @escaping (AppInfo) -> Void, failure: @escaping ErrorResponse) { XCTFail("unused") }
  func getAppAndVersion() async throws -> AppInfo { fatalError("unused") }
  func openAppIfNeeded(_ name: String, completion: @escaping (Result<Void, Error>) -> Void) { XCTFail("unused") }
  func openAppIfNeeded(_ name: String) async throws { XCTFail("unused") }
}
