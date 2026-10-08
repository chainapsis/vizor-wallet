import CoreFoundation
import Foundation
import Security

package struct IosCleanupScope: Sendable {
  package let namespace: String
  package let simulatorUdid: String
  package let ownerNonce: String
  package let expectedTeam: String
  package init(namespace: String, simulatorUdid: String, ownerNonce: String, expectedTeam: String) throws {
    // Shared canonical namespace/team validation; no macOS native system is used.
    _ = try MacCleanupScope(namespace: namespace, expectedTeam: expectedTeam)
    guard let uuid = UUID(uuidString: simulatorUdid), uuid.uuidString == simulatorUdid else {
      throw CleanupFailure("invalid_simulator_uuid")
    }
    guard ownerNonce.utf8.count == 16,
      ownerNonce.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw CleanupFailure("invalid_owner_nonce") }
    self.namespace = namespace
    self.simulatorUdid = simulatorUdid
    self.ownerNonce = ownerNonce
    self.expectedTeam = expectedTeam
  }

  package var services: [String] {
    let wallet = "com.keplr.vizor.regtest.secure_store.e2e.\(namespace)"
    return [wallet, wallet + ".accessibility-migration-v1",
      "com.zcash.wallet.biometric-unlock.e2e.\(namespace)",
      "com.keplr.vizor.ironwood-migration-background.v1.e2e.\(namespace)",
      "com.keplr.vizor.ironwood-migration-outbox-key.v1.e2e.\(namespace)"]
  }
  package var preferencesPrefix: String { "flutter.vizor_e2e_\(namespace)." }
  package var defaultsSuite: String { "com.keplr.vizor.regtest.e2e.\(namespace)" }
  package var notificationPrefix: String { "vizor_e2e_\(namespace)." }
}

package struct IosHelperIdentity: Sendable {
  package let bundleId: String
  package let simulatorUdid: String
  package let isSimulator: Bool
  package let cleanupBuildMarker: Bool
  package let applicationIdentifier: String

  func validate(for scope: IosCleanupScope) throws {
    guard isSimulator, cleanupBuildMarker, bundleId == "com.keplr.vizor",
      simulatorUdid == scope.simulatorUdid,
      applicationIdentifier == "\(scope.expectedTeam).com.keplr.vizor"
    else { throw CleanupFailure("ios_helper_identity_mismatch") }
  }
}

package struct IosPreferencesObservation: Encodable, Sendable {
  package let domain: String
  package let prefix: String?
  package let beforeCount: Int
  package var removedCount = 0
  package var afterCount: Int?
  package var synchronized: Bool?
}

package struct IosNotificationsObservation: Encodable, Sendable {
  package let prefix: String
  package let pendingBeforeCount: Int
  package let deliveredBeforeCount: Int
  package var pendingRemovedCount = 0
  package var deliveredRemovedCount = 0
  package var pendingAfterCount: Int?
  package var deliveredAfterCount: Int?
}

package struct IosCleanupReceipt: Encodable, Sendable {
  package let schemaVersion = 1
  package let platform = "ios"
  package let mode: CleanupMode
  package let namespace: String
  package let simulatorUdid: String
  package let ownerNonce: String
  package let expectedTeam: String
  package let keychainScope = "application_accessible"
  package var identity: IosIdentityObservation?
  package var keychain: [KeychainObservation] = []
  package var preferences: [IosPreferencesObservation] = []
  package var notifications: IosNotificationsObservation?
  package var completed = false
  package var errorCode: String?
  package var errorStatus: Int32?
}

package struct IosIdentityObservation: Encodable, Sendable {
  package let bundleId: String
  package let simulatorUdid: String
  package let cleanupBuildMarker: Bool
  package let applicationIdentifier: String
}

@MainActor package protocol IosCleanupSystem {
  func identity() throws -> IosHelperIdentity
  func lookup(service: String) -> Int32
  func delete(service: String) -> Int32
  func synchronizePreferences(domain: String) -> Bool
  func preferenceKeys(domain: String) throws -> [String]
  func removePreference(_ key: String, domain: String)
  func notificationIdentifiers(delivered: Bool) async throws -> [String]
  func removeNotifications(_ identifiers: [String], delivered: Bool)
}

// Only the dedicated simulator helper invokes this. A native snapshot is not
// process/device ownership or permission to delete a simulator/workspace.
@MainActor package func inspectOrCleanIos(
  _ scope: IosCleanupScope, mode: CleanupMode, system: IosCleanupSystem
) async -> IosCleanupReceipt {
  var receipt = IosCleanupReceipt(mode: mode, namespace: scope.namespace,
    simulatorUdid: scope.simulatorUdid, ownerNonce: scope.ownerNonce, expectedTeam: scope.expectedTeam)
  do {
    let identity = try system.identity()
    try identity.validate(for: scope)
    receipt.identity = IosIdentityObservation(bundleId: identity.bundleId,
      simulatorUdid: identity.simulatorUdid, cleanupBuildMarker: identity.cleanupBuildMarker,
      applicationIdentifier: identity.applicationIdentifier)
    // Preflight all resources before any mutation. Never read secret values.
    for service in scope.services {
      let status = system.lookup(service: service)
      receipt.keychain.append(KeychainObservation(service: service, beforeStatus: status))
      guard status == errSecSuccess || status == errSecItemNotFound else {
        throw CleanupFailure("keychain_preflight_failed", status: status)
      }
    }
    let domains: [(String, String?)] = [("com.keplr.vizor", scope.preferencesPrefix), (scope.defaultsSuite, nil)]
    var keysByDomain: [[String]] = []
    for (domain, prefix) in domains {
      guard system.synchronizePreferences(domain: domain) else {
        throw CleanupFailure("preferences_synchronize_failed")
      }
      let keys = try system.preferenceKeys(domain: domain).filter { prefix == nil || $0.hasPrefix(prefix!) }
      guard Set(keys).count == keys.count else { throw CleanupFailure("preferences_keys_invalid") }
      keysByDomain.append(keys)
      receipt.preferences.append(IosPreferencesObservation(domain: domain, prefix: prefix, beforeCount: keys.count))
    }
    let pending = try await system.notificationIdentifiers(delivered: false).filter { $0.hasPrefix(scope.notificationPrefix) }
    let delivered = try await system.notificationIdentifiers(delivered: true).filter { $0.hasPrefix(scope.notificationPrefix) }
    guard Set(pending).count == pending.count, Set(delivered).count == delivered.count else {
      throw CleanupFailure("notification_identifiers_invalid")
    }
    receipt.notifications = IosNotificationsObservation(prefix: scope.notificationPrefix,
      pendingBeforeCount: pending.count, deliveredBeforeCount: delivered.count)
    for index in receipt.keychain.indices {
      if mode == .delete {
        let status = system.delete(service: scope.services[index])
        receipt.keychain[index].deleteStatus = status
        guard status == errSecSuccess || status == errSecItemNotFound else {
          throw CleanupFailure("keychain_delete_failed", status: status)
        }
        receipt.keychain[index].afterStatus = system.lookup(service: scope.services[index])
        guard receipt.keychain[index].afterStatus == errSecItemNotFound else {
          throw CleanupFailure("keychain_delete_unproven", status: receipt.keychain[index].afterStatus)
        }
      } else { receipt.keychain[index].afterStatus = receipt.keychain[index].beforeStatus }
    }
    for index in domains.indices {
      let (domain, prefix) = domains[index]
      if mode == .delete {
        for key in keysByDomain[index] {
          system.removePreference(key, domain: domain)
          receipt.preferences[index].removedCount += 1
        }
        let synchronized = system.synchronizePreferences(domain: domain)
        receipt.preferences[index].synchronized = synchronized
        guard synchronized else { throw CleanupFailure("preferences_synchronize_failed") }
        let remaining = try system.preferenceKeys(domain: domain).filter { prefix == nil || $0.hasPrefix(prefix!) }
        receipt.preferences[index].afterCount = remaining.count
        guard remaining.isEmpty else { throw CleanupFailure("preferences_delete_unproven") }
      } else {
        receipt.preferences[index].afterCount = keysByDomain[index].count
        receipt.preferences[index].synchronized = true
      }
    }
    if mode == .delete {
      system.removeNotifications(pending, delivered: false)
      receipt.notifications!.pendingRemovedCount = pending.count
      system.removeNotifications(delivered, delivered: true)
      receipt.notifications!.deliveredRemovedCount = delivered.count
      let pendingAfter = try await system.notificationIdentifiers(delivered: false).filter { $0.hasPrefix(scope.notificationPrefix) }
      let deliveredAfter = try await system.notificationIdentifiers(delivered: true).filter { $0.hasPrefix(scope.notificationPrefix) }
      receipt.notifications!.pendingAfterCount = pendingAfter.count
      receipt.notifications!.deliveredAfterCount = deliveredAfter.count
      guard pendingAfter.isEmpty, deliveredAfter.isEmpty else { throw CleanupFailure("notifications_delete_unproven") }
    } else {
      receipt.notifications!.pendingAfterCount = pending.count
      receipt.notifications!.deliveredAfterCount = delivered.count
    }
    receipt.completed = receipt.keychain.allSatisfy { $0.afterStatus == errSecItemNotFound }
      && receipt.preferences.allSatisfy { $0.afterCount == 0 && $0.synchronized == true }
      && receipt.notifications?.pendingAfterCount == 0 && receipt.notifications?.deliveredAfterCount == 0
    if !receipt.completed { receipt.errorCode = "native_state_retained" }
  } catch let failure as CleanupFailure {
    receipt.errorCode = failure.code
    receipt.errorStatus = failure.status
  } catch { receipt.errorCode = "native_operation_failed" }
  return receipt
}
