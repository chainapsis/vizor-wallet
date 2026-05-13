import Flutter
@testable import Runner
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testDefaultNetworkCanBeDecodedFromDartDefines() {
    let encoded = Data("ZCASH_DEFAULT_NETWORK=test".utf8).base64EncodedString()

    XCTAssertEqual(
      RpcEndpointConfigStore.defaultNetwork(fromDartDefines: encoded),
      "test"
    )
  }

  func testEndpointDefaultsFollowNetwork() {
    XCTAssertEqual(
      RpcEndpointConfigStore.defaultLightwalletdUrl(forNetwork: "test"),
      "https://testnet.zec.rocks:443"
    )
    XCTAssertEqual(
      RpcEndpointConfigStore.defaultPresetId(forNetwork: "test"),
      "default-testnet"
    )
  }

  func testSecureStoreServiceFollowsNetwork() {
    XCTAssertEqual(
      secureStoreService(forNetwork: "main"),
      "com.keplr.vizor.secure_store"
    )
    XCTAssertEqual(
      secureStoreService(forNetwork: "test"),
      "com.keplr.vizor.test.secure_store"
    )
  }

}
