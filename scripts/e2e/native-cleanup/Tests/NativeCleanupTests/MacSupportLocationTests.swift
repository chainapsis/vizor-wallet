import Foundation
import Testing
@testable import NativeCleanup

private final class LocationModel: CleanupSystem {
  var identity = SigningIdentity(
    bundleId: "com.keplr.vizor", teamId: "A1B2C3D4E5",
    applicationIdentifier: "A1B2C3D4E5.com.keplr.vizor", sandboxEnabled: true,
    keychainGroups: nil
  )
  var error: CleanupFailure?
  var calls: [String] = []
  func signingIdentity() throws -> SigningIdentity {
    calls.append("identity")
    if let error { throw error }
    return identity
  }
  func lookup(service: String, accessGroup: String) -> Int32 { calls.append("lookup"); return 0 }
  func delete(service: String, accessGroup: String) -> Int32 { calls.append("delete"); return 0 }
  func synchronizePreferences() -> Bool { calls.append("preferences"); return true }
  func preferenceKeys() throws -> [String] { calls.append("keys"); return [] }
  func removePreference(_ key: String) { calls.append("remove") }
}

private func locationScope() throws -> MacCleanupScope {
  try MacCleanupScope(namespace: "vizor_a1b2c3d4e5_w2_17", expectedTeam: "A1B2C3D4E5")
}

@Suite("Signed macOS SDK support location (isolated models)")
struct MacSupportLocationTests {
  @Test func sdkPathMatchesCurrentPathProviderAndDoesNotTouchStorage() throws {
    let model = LocationModel()
    let receipt = observeMacSupportLocation(try locationScope(), system: model) {
      "/Users/model/Library/Containers/com.keplr.vizor/Data/Library/Application Support"
    }
    #expect(receipt.completed)
    #expect(receipt.mode == "support_location")
    #expect(receipt.supportDirectory == "/Users/model/Library/Containers/com.keplr.vizor/Data/Library/Application Support/com.keplr.vizor/e2e/vizor_a1b2c3d4e5_w2_17")
    #expect(model.calls == ["identity"])
    #expect(receipt.errorCode == nil)
  }

  @Test func badSigningCannotEvenQueryTheSdkPath() throws {
    let model = LocationModel()
    model.identity = SigningIdentity(
      bundleId: "com.keplr.vizor", teamId: "A1B2C3D4E5",
      applicationIdentifier: "A1B2C3D4E5.com.keplr.vizor", sandboxEnabled: false,
      keychainGroups: nil
    )
    var reads = 0
    let receipt = observeMacSupportLocation(try locationScope(), system: model) {
      reads += 1
      return "/unused"
    }
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "signing_identity_mismatch")
    #expect(reads == 0)
    #expect(receipt.supportDirectory == nil)
    #expect(model.calls == ["identity"])
  }

  @Test func unavailableIdentityIsNotAPathFallback() throws {
    let model = LocationModel()
    model.error = CleanupFailure("code_identity_unavailable")
    let receipt = observeMacSupportLocation(try locationScope(), system: model) {
      Issue.record("SDK path must not be queried")
      return "/unused"
    }
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "code_identity_unavailable")
    #expect(receipt.identity == nil)
    #expect(receipt.supportDirectory == nil)
  }

  @Test(arguments: ["", "relative/Library", "/some/../Library", "/some/./Library", "/some\0Library"])
  func refusesInvalidSdkPaths(_ path: String) throws {
    let model = LocationModel()
    let receipt = observeMacSupportLocation(try locationScope(), system: model) { path }
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "support_location_invalid")
    #expect(receipt.supportDirectory == nil)
    #expect(model.calls == ["identity"])
  }

  @Test func nativeFailureDoesNotExposeErrorText() throws {
    enum SensitiveError: Error { case secretContent }
    let receipt = observeMacSupportLocation(try locationScope(), system: LocationModel()) {
      throw SensitiveError.secretContent
    }
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "support_location_failed")
    #expect(receipt.supportDirectory == nil)
  }

  @Test func receiptIsADeclarationNotCleanupOrOwnershipProof() throws {
    let receipt = observeMacSupportLocation(try locationScope(), system: LocationModel()) { "/model/Library" }
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let json = try #require(JSONSerialization.jsonObject(with: encoder.encode(receipt)) as? [String: Any])
    #expect(Set(json.keys) == ["schema_version", "platform", "mode", "namespace", "expected_team", "identity", "support_directory", "completed"])
    #expect(json["keychain"] == nil)
    #expect(json["storage_cleanup_completed"] == nil)
    #expect(json["owner_nonce"] == nil)
  }
}
