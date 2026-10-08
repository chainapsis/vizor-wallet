import Foundation
import Testing
@testable import NativeCleanup

private func simulatedExecutable(_ entitlements: [String: Any]) throws -> Data {
  let payload = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
  var result = Data(repeating: 0, count: 184)
  func u32(_ offset: Int, _ value: UInt32) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { result.replaceSubrange(offset..<offset + 4, with: $0) }
  }
  func u64(_ offset: Int, _ value: UInt64) {
    var little = value.littleEndian
    withUnsafeBytes(of: &little) { result.replaceSubrange(offset..<offset + 8, with: $0) }
  }
  func name(_ offset: Int, _ value: String) {
    result.replaceSubrange(offset..<offset + value.utf8.count, with: value.utf8)
  }
  u32(0, 0xfeedfacf); u32(12, 2); u32(16, 1); u32(20, 152)
  u32(32, 0x19); u32(36, 152); name(40, "__TEXT"); u32(96, 1)
  name(104, "__entitlements"); name(120, "__TEXT")
  u64(144, UInt64(payload.count)); u32(152, 184)
  result.append(payload)
  return result
}

@Suite("Simulator embedded access rights (isolated binary fixtures)")
struct IosSimulatedEntitlementsTests {
  @Test func parsesXcodeStyleRightsRatherThanAdHocCodesignOutput() throws {
    let embedded = ["application-identifier": "A1B2C3D4E5.com.keplr.vizor"]
    let parsed = try iosSimulatedEntitlements(simulatedExecutable(embedded))
    #expect(try iosHelperApplicationIdentifier(parsed) == "A1B2C3D4E5.com.keplr.vizor")
  }

  @Test(arguments: [0, 1, 31, 32, 100, 183, 184, 200])
  func truncatedExecutablesFailClosed(_ count: Int) throws {
    let bytes = try simulatedExecutable(["application-identifier": "A1B2C3D4E5.com.keplr.vizor"])
    #expect(throws: CleanupFailure.self) { try iosSimulatedEntitlements(Data(bytes.prefix(count))) }
  }

  @Test(arguments: [0, 12, 16, 20, 36, 96, 144, 152])
  func corruptHeaderCommandSectionAndPayloadBoundsAreRefused(_ offset: Int) throws {
    var bytes = try simulatedExecutable(["application-identifier": "A1B2C3D4E5.com.keplr.vizor"])
    bytes.replaceSubrange(offset..<offset + 4, with: [UInt8](repeating: 255, count: 4))
    #expect(throws: CleanupFailure.self) { try iosSimulatedEntitlements(bytes) }
  }

  @Test func absentSectionAndInvalidPlistAreNotEmptyRights() throws {
    var bytes = try simulatedExecutable(["application-identifier": "A1B2C3D4E5.com.keplr.vizor"])
    bytes[104] = 0
    #expect(throws: CleanupFailure.self) { try iosSimulatedEntitlements(bytes) }
    bytes = try simulatedExecutable(["application-identifier": "A1B2C3D4E5.com.keplr.vizor"])
    bytes[184] = 0
    #expect(throws: CleanupFailure.self) { try iosSimulatedEntitlements(bytes) }
  }

  @Test(arguments: ["", "com.keplr.vizor", "A1B2C3D4E5.other.app", "lowerteam1.com.keplr.vizor"])
  func missingOrWrongApplicationIdentifierCannotReachKeychain(_ identifier: String) {
    #expect(throws: CleanupFailure.self) {
      try iosHelperApplicationIdentifier(["application-identifier": identifier])
    }
    #expect(throws: CleanupFailure.self) { try iosHelperApplicationIdentifier([:]) }
  }

  @Test func helperCannotInheritSharedGroupsDomainsOrUnexpectedRights() {
    let identifier = "A1B2C3D4E5.com.keplr.vizor"
    for extra: [String: Any] in [
      ["keychain-access-groups": [identifier, "shared.group"]],
      ["keychain-access-groups": "invalid"], ["com.apple.developer.team-identifier": "OTHERTEAM1"],
      ["com.apple.security.application-groups": ["group.com.keplr.vizor"]],
      ["com.apple.developer.associated-domains": ["applinks:link.vizor.cash"]],
      ["get-task-allow": 1], ["com.apple.security.get-task-allow": "true"],
    ] {
      let values = ["application-identifier": identifier] as [String: Any]
      #expect(throws: CleanupFailure.self) {
        try iosHelperApplicationIdentifier(values.merging(extra) { _, new in new })
      }
    }
  }

  @Test func onlySameDefaultGroupAndBooleanDebugFlagsAreAllowed() throws {
    let identifier = "A1B2C3D4E5.com.keplr.vizor"
    #expect(try iosHelperApplicationIdentifier([
      "application-identifier": identifier, "com.apple.developer.team-identifier": "A1B2C3D4E5",
      "keychain-access-groups": [identifier], "get-task-allow": true, "com.apple.security.get-task-allow": false,
    ]) == identifier)
  }
}
