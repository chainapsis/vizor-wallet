import Foundation
import Security

package struct MacCleanupScope: Sendable {
  package let namespace: String
  package let expectedTeam: String

  package init(namespace: String, expectedTeam: String) throws {
    try validateCleanupNamespace(namespace)
    guard expectedTeam.utf8.count == 10,
      expectedTeam.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) })
    else { throw CleanupFailure("invalid_expected_team") }
    self.namespace = namespace
    self.expectedTeam = expectedTeam
  }

  package var services: [String] {
    let wallet = "com.keplr.vizor.regtest.secure_store.e2e.\(namespace)"
    return [wallet, "\(wallet).mnemonic"]
  }
  package var preferencesPrefix: String { "flutter.vizor_e2e_\(namespace)." }
}

package enum CleanupMode: String, Encodable, Sendable {
  case delete, verify
}

package struct CleanupFailure: Error, Equatable, Sendable {
  package let code: String
  package let status: Int32?
  package init(_ code: String, status: Int32? = nil) {
    self.code = code
    self.status = status
  }
}

package struct SigningIdentity: Sendable {
  package let bundleId: String
  package let teamId: String
  package let applicationIdentifier: String
  package let sandboxEnabled: Bool
  package let keychainGroups: [String]?

  func validate(for scope: MacCleanupScope) throws {
    guard bundleId == "com.keplr.vizor", teamId == scope.expectedTeam,
      applicationIdentifier == "\(scope.expectedTeam).com.keplr.vizor",
      sandboxEnabled,
      keychainGroups == nil || keychainGroups == [applicationIdentifier]
    else { throw CleanupFailure("signing_identity_mismatch") }
  }
}

// This interface mirrors native observations, not a caller-provided cleanup flag.
// Production constructs MacCleanupSystem; tests use isolated models of OS errors.
package protocol CleanupSystem {
  func signingIdentity() throws -> SigningIdentity
  func lookup(service: String, accessGroup: String) -> Int32
  func delete(service: String, accessGroup: String) -> Int32
  func synchronizePreferences() -> Bool
  func preferenceKeys() throws -> [String]
  func removePreference(_ key: String)
}

package struct KeychainObservation: Encodable, Sendable {
  package let service: String
  package let beforeStatus: Int32
  package var deleteStatus: Int32?
  package var afterStatus: Int32?
}

package struct PreferencesObservation: Encodable, Sendable {
  package let prefix: String
  package let beforeCount: Int
  package var removedCount: Int
  package var afterCount: Int?
  package var synchronized: Bool?
}

package struct MacCleanupReceipt: Encodable, Sendable {
  package let schemaVersion = 1
  package let platform = "macos"
  package let mode: CleanupMode
  package let namespace: String
  package let expectedTeam: String
  package var identity: SigningIdentityObservation?
  package var keychain: [KeychainObservation] = []
  package var preferences: PreferencesObservation?
  package var completed = false
  package var errorCode: String?
  package var errorStatus: Int32?
}

package struct SigningIdentityObservation: Encodable, Sendable {
  package let bundleId: String
  package let teamId: String
  package let applicationIdentifier: String
}

// Call only after the case's writers have stopped. This is a native-API snapshot,
// not process ownership, wallet-directory removal, or permission to delete a run.
package func inspectOrClean(
  _ scope: MacCleanupScope, mode: CleanupMode, system: CleanupSystem
) -> MacCleanupReceipt {
  var receipt = MacCleanupReceipt(mode: mode, namespace: scope.namespace, expectedTeam: scope.expectedTeam)
  do {
    let identity = try system.signingIdentity()
    try identity.validate(for: scope)
    receipt.identity = SigningIdentityObservation(
      bundleId: identity.bundleId, teamId: identity.teamId,
      applicationIdentifier: identity.applicationIdentifier
    )
    for service in scope.services {
      let before = system.lookup(service: service, accessGroup: identity.applicationIdentifier)
      receipt.keychain.append(KeychainObservation(service: service, beforeStatus: before))
      let index = receipt.keychain.count - 1
      guard before == errSecSuccess || before == errSecItemNotFound else {
        throw CleanupFailure("keychain_preflight_failed", status: before)
      }
      if mode == .delete {
        let deleted = system.delete(service: service, accessGroup: identity.applicationIdentifier)
        receipt.keychain[index].deleteStatus = deleted
        guard deleted == errSecSuccess || deleted == errSecItemNotFound else {
          throw CleanupFailure("keychain_delete_failed", status: deleted)
        }
        let after = system.lookup(service: service, accessGroup: identity.applicationIdentifier)
        receipt.keychain[index].afterStatus = after
        guard after == errSecItemNotFound else {
          throw CleanupFailure("keychain_delete_unproven", status: after)
        }
      } else {
        receipt.keychain[index].afterStatus = before
      }
    }
    guard system.synchronizePreferences() else {
      throw CleanupFailure("preferences_synchronize_failed")
    }
    let matched = try system.preferenceKeys().filter { $0.hasPrefix(scope.preferencesPrefix) }
    receipt.preferences = PreferencesObservation(prefix: scope.preferencesPrefix, beforeCount: matched.count, removedCount: 0)
    if mode == .delete {
      for key in matched {
        system.removePreference(key)
        receipt.preferences!.removedCount += 1
      }
      let synchronized = system.synchronizePreferences()
      receipt.preferences!.synchronized = synchronized
      guard synchronized else { throw CleanupFailure("preferences_synchronize_failed") }
      let remaining = try system.preferenceKeys().filter { $0.hasPrefix(scope.preferencesPrefix) }
      receipt.preferences!.afterCount = remaining.count
      guard remaining.isEmpty else { throw CleanupFailure("preferences_delete_unproven") }
    } else {
      receipt.preferences!.afterCount = matched.count
      receipt.preferences!.synchronized = true
    }
    receipt.completed = receipt.keychain.allSatisfy { $0.afterStatus == errSecItemNotFound }
      && receipt.preferences?.afterCount == 0
    if !receipt.completed { receipt.errorCode = "native_state_retained" }
  } catch let failure as CleanupFailure {
    receipt.errorCode = failure.code
    receipt.errorStatus = failure.status
  } catch {
    // Never serialize arbitrary native errors or key/value content.
    receipt.errorCode = "native_operation_failed"
  }
  return receipt
}
