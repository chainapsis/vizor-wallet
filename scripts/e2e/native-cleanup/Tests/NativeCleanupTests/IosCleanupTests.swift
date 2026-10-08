import Foundation
import Security
import Testing
@testable import NativeCleanup

private let iosNamespace = "vizor_a1b2c3d4e5_w2_17"
private let iosUdid = "ED3345B2-2A4F-4A41-A35B-2C09EBA034F6"
private let iosNonce = "1234567890abcdef"

private func iosScope() throws -> IosCleanupScope {
  try IosCleanupScope(namespace: iosNamespace, simulatorUdid: iosUdid,
    ownerNonce: iosNonce, expectedTeam: "A1B2C3D4E5")
}

@MainActor private final class IosModel: IosCleanupSystem {
  var observedIdentity = IosHelperIdentity(bundleId: "com.keplr.vizor",
    simulatorUdid: iosUdid, isSimulator: true, cleanupBuildMarker: true,
    applicationIdentifier: "A1B2C3D4E5.com.keplr.vizor")
  var identityError: Error?
  var services = Set<String>()
  var beforeError: (String, Int32)?
  var deleteError: (String, Int32)?
  var keepServices = Set<String>()
  var preferences: [String: Set<String>] = [:]
  var pending = Set<String>()
  var delivered = Set<String>()
  var keepPreferences = false
  var keepNotifications = false
  var duplicateKeys = false
  var duplicateNotifications = false
  var notificationError: Error?
  var syncFailureAt: Int?
  var syncCount = 0
  var calls: [String] = []

  func identity() throws -> IosHelperIdentity {
    calls.append("identity")
    if let identityError { throw identityError }
    return observedIdentity
  }
  func lookup(service: String) -> Int32 {
    calls.append("lookup:\(service)")
    if let (target, status) = beforeError, target == service { return status }
    return services.contains(service) ? errSecSuccess : errSecItemNotFound
  }
  func delete(service: String) -> Int32 {
    calls.append("delete:\(service)")
    if let (target, status) = deleteError, target == service { return status }
    let existed = services.contains(service)
    if !keepServices.contains(service) { services.remove(service) }
    return existed ? errSecSuccess : errSecItemNotFound
  }
  func synchronizePreferences(domain: String) -> Bool {
    calls.append("sync:\(domain)")
    syncCount += 1
    return syncFailureAt != syncCount
  }
  func preferenceKeys(domain: String) throws -> [String] {
    let keys = (preferences[domain] ?? []).sorted()
    return duplicateKeys ? keys + keys : keys
  }
  func removePreference(_ key: String, domain: String) {
    calls.append("remove-pref:\(domain)")
    if !keepPreferences { preferences[domain]?.remove(key) }
  }
  func notificationIdentifiers(delivered: Bool) async throws -> [String] {
    calls.append(delivered ? "delivered" : "pending")
    if let notificationError { throw notificationError }
    let values = (delivered ? self.delivered : pending).sorted()
    return duplicateNotifications ? values + values : values
  }
  func removeNotifications(_ identifiers: [String], delivered: Bool) {
    calls.append(delivered ? "remove-delivered" : "remove-pending")
    if keepNotifications { return }
    if delivered { self.delivered.subtract(identifiers) }
    else { pending.subtract(identifiers) }
  }
  func seed(_ scope: IosCleanupScope) {
    services.formUnion(scope.services + ["unrelated-service"])
    preferences["com.keplr.vizor"] = [scope.preferencesPrefix + "wallet", "flutter.production", "flutter.vizor_e2e_sibling.value"]
    preferences[scope.defaultsSuite] = ["migration-complete", "background-state"]
    preferences["unrelated-suite"] = ["sentinel"]
    pending = [scope.notificationPrefix + "pending", "user-notification"]
    delivered = [scope.notificationPrefix + "done", "sibling-notification"]
  }
  var mutationCalls: [String] { calls.filter { $0.hasPrefix("delete:") || $0.hasPrefix("remove-") } }
}

@Suite("iOS cleanup observations (per-invocation models)")
@MainActor struct IosCleanupTests {
  @Test func namesMatchRuntimeIncludingRecoveryStagingAndAuxiliarySecrets() throws {
    let scope = try iosScope()
    #expect(scope.services == ["com.keplr.vizor.regtest.secure_store.e2e.\(iosNamespace)",
      "com.keplr.vizor.regtest.secure_store.e2e.\(iosNamespace).accessibility-migration-v1",
      "com.zcash.wallet.biometric-unlock.e2e.\(iosNamespace)",
      "com.keplr.vizor.ironwood-migration-background.v1.e2e.\(iosNamespace)",
      "com.keplr.vizor.ironwood-migration-outbox-key.v1.e2e.\(iosNamespace)"])
    #expect(scope.preferencesPrefix == "flutter.vizor_e2e_\(iosNamespace).")
    #expect(scope.defaultsSuite == "com.keplr.vizor.regtest.e2e.\(iosNamespace)")
    #expect(scope.notificationPrefix == "vizor_e2e_\(iosNamespace).")
  }

  @Test(arguments: ["vizor_a1b2c3d4e5_w01_0", "vizor_a1b2c3d4e5_w0_1000001", "../vizor", "vizor_a1b2c3d4e5_w0_0\n"])
  func invalidNamespaceCannotReachNativeApis(_ namespace: String) {
    #expect(throws: CleanupFailure.self) {
      try IosCleanupScope(namespace: namespace, simulatorUdid: iosUdid, ownerNonce: iosNonce, expectedTeam: "A1B2C3D4E5")
    }
  }

  @Test(arguments: ["ed3345b2-2a4f-4a41-a35b-2c09eba034f6", "booted", "", "ED3345B2-2A4F-4A41-A35B-2C09EBA034F6\n"])
  func requiresCanonicalExactUuid(_ udid: String) {
    #expect(throws: CleanupFailure.self) {
      try IosCleanupScope(namespace: iosNamespace, simulatorUdid: udid, ownerNonce: iosNonce, expectedTeam: "A1B2C3D4E5")
    }
  }

  @Test(arguments: ["", "1234567890ABCDEF", "../../owner", "1234567890abcdef\n", "1234567890abcdef1234567890abcdef"])
  func requiresCanonicalOwnerNonce(_ nonce: String) {
    #expect(throws: CleanupFailure.self) {
      try IosCleanupScope(namespace: iosNamespace, simulatorUdid: iosUdid, ownerNonce: nonce, expectedTeam: "A1B2C3D4E5")
    }
  }

  @Test(arguments: ["bundle", "device", "physical", "marker", "team"])
  func identityMismatchFailsBeforeStorage(_ field: String) async throws {
    let model = IosModel()
    model.observedIdentity = IosHelperIdentity(bundleId: field == "bundle" ? "other.app" : "com.keplr.vizor",
      simulatorUdid: field == "device" ? "wrong-device" : iosUdid,
      isSimulator: field != "physical", cleanupBuildMarker: field != "marker",
      applicationIdentifier: field == "team" ? "OTHERTEAM1.com.keplr.vizor" : "A1B2C3D4E5.com.keplr.vizor")
    let receipt = await inspectOrCleanIos(try iosScope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "ios_helper_identity_mismatch")
    #expect(model.calls == ["identity"])
  }

  @Test func cleansAllScopedResourcesAndPreservesSiblingAndProductionState() async throws {
    let scope = try iosScope()
    let model = IosModel()
    model.seed(scope)
    let receipt = await inspectOrCleanIos(scope, mode: .delete, system: model)
    #expect(receipt.completed)
    #expect(receipt.errorCode == nil)
    #expect(receipt.keychain.count == 5)
    #expect(receipt.keychain.allSatisfy { $0.beforeStatus == 0 && $0.deleteStatus == 0 && $0.afterStatus == -25300 })
    #expect(model.services == ["unrelated-service"])
    #expect(model.preferences["com.keplr.vizor"] == ["flutter.production", "flutter.vizor_e2e_sibling.value"])
    #expect(model.preferences[scope.defaultsSuite] == [])
    #expect(model.preferences["unrelated-suite"] == ["sentinel"])
    #expect(model.pending == ["user-notification"])
    #expect(model.delivered == ["sibling-notification"])
    let firstMutation = try #require(model.calls.firstIndex(where: { $0.hasPrefix("delete:") }))
    #expect(model.calls[..<firstMutation].contains("delivered"))
    #expect(receipt.preferences.map(\.beforeCount) == [1, 2])
    #expect(receipt.notifications?.pendingAfterCount == 0)
    #expect(receipt.notifications?.deliveredAfterCount == 0)
  }

  @Test func emptyScopeHasPositiveAbsenceInBothModes() async throws {
    for mode in [CleanupMode.verify, .delete] {
      let model = IosModel()
      let receipt = await inspectOrCleanIos(try iosScope(), mode: mode, system: model)
      #expect(receipt.completed)
      #expect(receipt.keychain.allSatisfy { $0.beforeStatus == -25300 && $0.afterStatus == -25300 })
      #expect(receipt.preferences.allSatisfy { $0.beforeCount == 0 && $0.afterCount == 0 && $0.synchronized == true })
      if mode == .verify {
        #expect(model.mutationCalls.isEmpty)
        #expect(receipt.keychain.allSatisfy { $0.deleteStatus == nil })
      }
    }
  }

  @Test func verificationNeverDeletesRetainedState() async throws {
    let scope = try iosScope()
    let model = IosModel()
    model.seed(scope)
    let receipt = await inspectOrCleanIos(scope, mode: .verify, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "native_state_retained")
    #expect(model.mutationCalls.isEmpty)
    #expect(model.services.isSuperset(of: scope.services))
    #expect(receipt.preferences.map(\.removedCount) == [0, 0])
  }

  @Test(arguments: [-25308, -25293, -34018, -50])
  func everyKeychainPreflightErrorStopsAllMutations(_ status: Int32) async throws {
    let scope = try iosScope()
    let model = IosModel()
    model.seed(scope)
    model.beforeError = (scope.services.last!, status)
    let receipt = await inspectOrCleanIos(scope, mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "keychain_preflight_failed")
    #expect(receipt.errorStatus == status)
    #expect(model.mutationCalls.isEmpty)
  }

  @Test func preferenceOrNotificationPreflightFailureCannotDeleteSecrets() async throws {
    let scope = try iosScope()
    for fail in ["sync", "notification", "duplicate-pref", "duplicate-notification"] {
      let model = IosModel()
      model.seed(scope)
      if fail == "sync" { model.syncFailureAt = 2 }
      if fail == "notification" { model.notificationError = CleanupFailure("notification_unavailable") }
      model.duplicateKeys = fail == "duplicate-pref"
      model.duplicateNotifications = fail == "duplicate-notification"
      let receipt = await inspectOrCleanIos(scope, mode: .delete, system: model)
      #expect(!receipt.completed)
      #expect(model.mutationCalls.isEmpty)
      #expect(model.services.isSuperset(of: scope.services))
    }
  }

  @Test func failedDeleteLeavesPartialObservationNotSuccess() async throws {
    let scope = try iosScope()
    let model = IosModel()
    model.seed(scope)
    model.deleteError = (scope.services[1], -25308)
    let receipt = await inspectOrCleanIos(scope, mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "keychain_delete_failed")
    #expect(receipt.keychain[0].afterStatus == -25300)
    #expect(receipt.keychain[1].deleteStatus == -25308)
    #expect(receipt.keychain[1].afterStatus == nil)
    #expect(model.services.contains(scope.services[1]))
    #expect(!model.calls.contains("remove-pending"))
  }

  @Test func retainedKeychainItemStopsBeforePreferenceOrNotificationMutation() async throws {
    let scope = try iosScope()
    let model = IosModel()
    model.seed(scope)
    model.keepServices = [scope.services[1]]
    let receipt = await inspectOrCleanIos(scope, mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "keychain_delete_unproven")
    #expect(!model.mutationCalls.contains(where: { $0.hasPrefix("remove-") }))
  }

  @Test(arguments: ["retained-pref", "sync", "retained-notification"])
  func postMutationUncertaintyCannotComplete(_ fault: String) async throws {
    let scope = try iosScope()
    let model = IosModel()
    model.seed(scope)
    model.keepPreferences = fault == "retained-pref"
    model.syncFailureAt = fault == "sync" ? 3 : nil
    model.keepNotifications = fault == "retained-notification"
    let receipt = await inspectOrCleanIos(scope, mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode != nil)
    #expect(model.services.isDisjoint(with: scope.services))
  }

  @Test func arbitraryNativeErrorTextIsNotSerialized() async throws {
    enum SecretError: Error { case sensitivePayload }
    let model = IosModel()
    model.identityError = SecretError.sensitivePayload
    let receipt = await inspectOrCleanIos(try iosScope(), mode: .delete, system: model)
    #expect(receipt.errorCode == "native_operation_failed")
    #expect(receipt.identity == nil)
    #expect(model.mutationCalls.isEmpty)
  }

  @Test func receiptContainsScopeCountsStatusesNotOwnershipOrSecretValues() async throws {
    let scope = try iosScope()
    let model = IosModel()
    model.seed(scope)
    let receipt = await inspectOrCleanIos(scope, mode: .delete, system: model)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let data = try encoder.encode(receipt)
    let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["simulator_udid"] as? String == iosUdid)
    #expect(json["owner_nonce"] as? String == iosNonce)
    #expect(json["keychain_scope"] as? String == "application_accessible")
    #expect(json["access_group"] == nil)
    #expect(json["storage_cleanup_completed"] == nil)
    #expect(json["process_ownership"] == nil)
    let text = try #require(String(data: data, encoding: .utf8))
    #expect(!text.contains("migration-complete"))
    #expect(!text.contains("user-notification"))
  }
}
