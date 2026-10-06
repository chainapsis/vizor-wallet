import Foundation
import XCTest
#if canImport(Runner)
@testable import Runner
#endif

final class AppClipGiftHandoffTests: XCTestCase {
  private let host = "link.vizor.cash"
  // Synthetic unfunded vector from docs/compact-gift-links.md.
  private let v3Link =
    "https://link.vizor.cash/payment-links/open#v3=WyJtYWluIiwiQUFBQUFBQUFBQUFBQUFBQUFBQUFBQSIsMzQ4MzE0MSwiMTAwMDAwMCIsImtuaWdodE1hZ2ljIiwxMS4xNywiSXQncyBhIGdyZWF0IGRheSB0byBzaGllbGQgeW91ciBaRUMg8J-boe-4jyJd"
  private var testService: String!

  override func setUp() {
    super.setUp()
    testService = "com.keplr.vizor.tests.appclip.\(UUID().uuidString)"
  }

  override func tearDown() {
    _ = AppClipGiftHandoff.consume(host: host, service: testService)
    super.tearDown()
  }

  func testAcceptsOnlyGiftLinkShape() {
    XCTAssertTrue(AppClipGiftHandoff.isGiftLink(URL(string: v3Link)!, host: host))
    XCTAssertTrue(
      AppClipGiftHandoff.isGiftLink(
        URL(string: "https://LINK.vizor.cash/payment-links/open#v2=abc")!,
        host: host
      )
    )

    let rejected = [
      "https://link.vizor.cash/payment-links/open",
      "https://link.vizor.cash/payment-links/open#v3=",
      "https://link.vizor.cash/payment-links/open#v4=abc",
      "https://link.vizor.cash/payment-links/open#v3=abc&x=1",
      "https://link.vizor.cash/payment-links/open?x=1#v3=abc",
      "https://link.vizor.cash/payment-links/other#v3=abc",
      "https://link.vizor.cash/#v3=abc",
      "https://example.com/payment-links/open#v3=abc",
      "https://user@link.vizor.cash/payment-links/open#v3=abc",
      "https://link.vizor.cash:8443/payment-links/open#v3=abc",
      "http://link.vizor.cash/payment-links/open#v3=abc",
      "https://link.vizor.cash/payment-links/open#v3="
        + String(repeating: "a", count: AppClipGiftHandoff.maxLinkBytes),
    ]
    for link in rejected {
      XCTAssertFalse(
        AppClipGiftHandoff.isGiftLink(URL(string: link)!, host: host),
        link
      )
    }
  }

  func testConsumeReturnsSavedLinkOnce() {
    XCTAssertNil(AppClipGiftHandoff.consume(host: host, service: testService))
    XCTAssertTrue(AppClipGiftHandoff.save(URL(string: v3Link)!, service: testService))

    XCTAssertEqual(
      AppClipGiftHandoff.consume(host: host, service: testService)?.absoluteString,
      v3Link
    )
    XCTAssertNil(AppClipGiftHandoff.consume(host: host, service: testService))
  }

  func testSaveReplacesEarlierLink() {
    let older = "https://link.vizor.cash/payment-links/open#v2=older"
    XCTAssertTrue(AppClipGiftHandoff.save(URL(string: older)!, service: testService))
    XCTAssertTrue(AppClipGiftHandoff.save(URL(string: v3Link)!, service: testService))

    XCTAssertEqual(
      AppClipGiftHandoff.consume(host: host, service: testService)?.absoluteString,
      v3Link
    )
  }

  func testConsumeDropsLinkForAnotherHost() {
    XCTAssertTrue(AppClipGiftHandoff.save(URL(string: v3Link)!, service: testService))

    XCTAssertNil(
      AppClipGiftHandoff.consume(host: "link-dev.vizor.cash", service: testService)
    )
    XCTAssertNil(AppClipGiftHandoff.consume(host: host, service: testService))
  }

  func testBridgeQueuesPendingAppClipGiftOncePerInstall() throws {
    let bridge = IncomingUriChannelBridge.shared
    let bridgeHost = IncomingUriChannelBridge.deeplinkHost
    let link = "https://\(bridgeHost)/payment-links/open#v3=WyJtYWluIl0"
    let suiteName = "AppClipGiftHandoffTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    _ = bridge.takePending()
    _ = AppClipGiftHandoff.consume(host: bridgeHost)

    XCTAssertTrue(AppClipGiftHandoff.save(URL(string: link)!))
    bridge.handlePendingAppClipGift(defaults: defaults)
    XCTAssertEqual(bridge.takePending(), [link])

    XCTAssertTrue(AppClipGiftHandoff.save(URL(string: link)!))
    bridge.handlePendingAppClipGift(defaults: defaults)
    XCTAssertEqual(bridge.takePending(), [])
    _ = AppClipGiftHandoff.consume(host: bridgeHost)
  }

  func testPreviewReadsV3DisplayFields() {
    let preview = GiftLinkPreview(url: URL(string: v3Link)!)

    XCTAssertEqual(preview.amountZatoshi, "1000000")
    XCTAssertEqual(preview.zecAmountText, "0.01")
    XCTAssertEqual(preview.fiatUsd, 11.17)
    XCTAssertEqual(preview.message, "It's a great day to shield your ZEC 🛡️")
  }

  func testPreviewReadsV2DisplayFields() throws {
    let payload: [String: Any] = [
      "v": 2,
      "network": "main",
      "amountZatoshi": "250000000",
      "mnemonic": "not shown",
      "birthdayHeight": 1,
      "label": "Payment link",
      "presentation": ["message": "  Happy birthday  ", "fiat": ["amount": 42, "currency": "USD"]],
    ]
    let encoded = try JSONSerialization.data(withJSONObject: payload)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
    let preview = GiftLinkPreview(
      url: URL(string: "https://link.vizor.cash/payment-links/open#v2=\(encoded)")!
    )

    XCTAssertEqual(preview.zecAmountText, "2.5")
    XCTAssertEqual(preview.fiatUsd, 42)
    XCTAssertEqual(preview.message, "Happy birthday")
  }

  func testPreviewIgnoresUnreadablePayloads() {
    let unreadable = [
      "https://link.vizor.cash/payment-links/open#v3=!!!!",
      "https://link.vizor.cash/payment-links/open#v3=WyJtYWluIl0",
      "https://link.vizor.cash/payment-links/open#v1=e30",
      "https://link.vizor.cash/payment-links/open",
    ]
    for link in unreadable {
      let preview = GiftLinkPreview(url: URL(string: link)!)
      XCTAssertNil(preview.zecAmountText, link)
      XCTAssertNil(preview.message, link)
    }
  }

  func testZecAmountTextUsesIntegerMath() {
    let cases = [
      ("1", "0.00000001"),
      ("100000000", "1"),
      ("2100000000000000", "21000000"),
      ("123456789", "1.23456789"),
    ]
    for (zatoshi, zec) in cases {
      let preview = GiftLinkPreview(amountZatoshi: zatoshi, fiatUsd: nil, message: nil)
      XCTAssertEqual(preview.zecAmountText, zec, zatoshi)
    }
  }
}
