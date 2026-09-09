import BleTransport
import XCTest

@testable import Runner

final class LedgerMobileHandlerTests: XCTestCase {
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
