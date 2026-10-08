import Foundation

package struct MacSupportLocationReceipt: Encodable, Sendable {
  package let schemaVersion = 1
  package let platform = "macos"
  package let mode = "support_location"
  package let namespace: String
  package let expectedTeam: String
  package var identity: SigningIdentityObservation?
  package var supportDirectory: String?
  package var completed = false
  package var errorCode: String?
}

// Mirrors path_provider_foundation 2.6.0's macOS user-domain path calculation.
// This probe does not create/adopt directories or observe/change native secrets.
package func macApplicationSupportBase() throws -> String {
  guard let path = NSSearchPathForDirectoriesInDomains(
    .applicationSupportDirectory, .userDomainMask, true
  ).first else { throw CleanupFailure("support_location_unavailable") }
  return path
}

package func observeMacSupportLocation(
  _ scope: MacCleanupScope, system: CleanupSystem,
  applicationSupportBase: () throws -> String = macApplicationSupportBase
) -> MacSupportLocationReceipt {
  var receipt = MacSupportLocationReceipt(namespace: scope.namespace, expectedTeam: scope.expectedTeam)
  do {
    let identity = try system.signingIdentity()
    try identity.validate(for: scope)
    receipt.identity = SigningIdentityObservation(
      bundleId: identity.bundleId, teamId: identity.teamId,
      applicationIdentifier: identity.applicationIdentifier
    )
    let base = try applicationSupportBase()
    guard base.hasPrefix("/"), !base.contains("\0"),
      !base.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." })
    else { throw CleanupFailure("support_location_invalid") }
    receipt.supportDirectory = URL(fileURLWithPath: base, isDirectory: true)
      .appendingPathComponent(identity.bundleId, isDirectory: true)
      .appendingPathComponent("e2e", isDirectory: true)
      .appendingPathComponent(scope.namespace, isDirectory: true).path
    receipt.completed = true
  } catch let failure as CleanupFailure {
    receipt.errorCode = failure.code
  } catch {
    receipt.errorCode = "support_location_failed"
  }
  return receipt
}
