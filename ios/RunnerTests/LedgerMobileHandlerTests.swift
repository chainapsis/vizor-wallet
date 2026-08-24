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
      maxPollAttempts: 3,
      waitBetweenAttempts: {}
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
      maxPollAttempts: 2,
      waitBetweenAttempts: {}
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
}
