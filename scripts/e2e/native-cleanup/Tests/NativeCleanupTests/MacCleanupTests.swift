import Foundation
import LocalAuthentication
import Security
import Testing
@testable import NativeCleanup

private let namespace = "vizor_a1b2c3d4e5_w2_17"
private let team = "A1B2C3D4E5"
private let group = "A1B2C3D4E5.com.keplr.vizor"
private let wallet = "com.keplr.vizor.regtest.secure_store.e2e.vizor_a1b2c3d4e5_w2_17"
private let prefix = "flutter.vizor_e2e_vizor_a1b2c3d4e5_w2_17."

private struct Item: Hashable { let service: String; let group: String }

// Independent per invocation; models the native status and persisted-key contract.
// These tests do not impersonate a signed app or access the host's Keychain.
private final class Model: CleanupSystem {
  var identity = SigningIdentity(
    bundleId: "com.keplr.vizor", teamId: team, applicationIdentifier: group,
    sandboxEnabled: true, keychainGroups: [group]
  )
  var calls: [String] = []
  var identityError: CleanupFailure?
  var items: Set<Item> = []
  var preferences: Set<String> = []
  var lookupError: Int32?
  var deleteError: Int32?
  var skipDeletion = false
  var skipPreferenceRemoval = false
  var synchronizations = [true, true]
  var keysError: CleanupFailure?

  func signingIdentity() throws -> SigningIdentity {
    calls.append("identity")
    if let identityError { throw identityError }
    return identity
  }
  func lookup(service: String, accessGroup: String) -> Int32 {
    calls.append("lookup:\(service):\(accessGroup)")
    return lookupError ?? (items.contains(Item(service: service, group: accessGroup)) ? errSecSuccess : errSecItemNotFound)
  }
  func delete(service: String, accessGroup: String) -> Int32 {
    calls.append("delete:\(service):\(accessGroup)")
    if let deleteError { return deleteError }
    if skipDeletion { return errSecSuccess }
    return items.remove(Item(service: service, group: accessGroup)) == nil ? errSecItemNotFound : errSecSuccess
  }
  func synchronizePreferences() -> Bool {
    calls.append("synchronize")
    return synchronizations.isEmpty ? true : synchronizations.removeFirst()
  }
  func preferenceKeys() throws -> [String] {
    calls.append("keys")
    if let keysError { throw keysError }
    return preferences.sorted()
  }
  func removePreference(_ key: String) {
    calls.append("remove:\(key)")
    if !skipPreferenceRemoval { preferences.remove(key) }
  }
}

private func scope() throws -> MacCleanupScope {
  try MacCleanupScope(namespace: namespace, expectedTeam: team)
}

@Suite("Case-scoped macOS native cleanup (modelled transport)")
struct MacCleanupTests {
  @Test(arguments: ["vizor_0000000000_w0_0", "vizor_012345abcd_w1000000_1000000"])
  func acceptsCanonicalContractBounds(_ value: String) throws {
    #expect(try MacCleanupScope(namespace: value, expectedTeam: team).namespace == value)
  }

  @Test(arguments: [
    "", "vizor_a1b2c3d4e5_w01_17", "vizor_a1b2c3d4e5_w2_017",
    "vizor_A1B2C3D4E5_w2_17", "vizor_a1b2c3d4e_w2_17",
    "vizor_a1b2c3d4e5_w1000001_17", "vizor_a1b2c3d4e5_w2_1000001",
    "vizor_a1b2c3d4e5_w-1_17", "vizor_a1b2c3d4e5_w2_-1",
    "vizor_a1b2c3d4e5_w2_17/other", "vizor_a1b2c3d4e5_w2_17\n",
    "vizor_a1b2c3d4e5_w2_17_", "vizor_a1b2c3d4e5_w２_17",
  ])
  func rejectsNoncanonicalNamespace(_ value: String) {
    #expect(throws: CleanupFailure("invalid_namespace")) {
      try MacCleanupScope(namespace: value, expectedTeam: team)
    }
  }

  @Test(arguments: ["", "lowercase1", "A1B2C3D4E", "A1B2C3D4E56", "A1B2C3D4É5"])
  func rejectsInvalidTeam(_ value: String) {
    #expect(throws: CleanupFailure("invalid_expected_team")) {
      try MacCleanupScope(namespace: namespace, expectedTeam: value)
    }
  }

  @Test func targetsMatchRuntimeContract() throws {
    let value = try scope()
    #expect(value.services == [wallet, "\(wallet).mnemonic"])
    #expect(value.preferencesPrefix == "flutter.vizor_e2e_vizor_a1b2c3d4e5_w2_17.")
  }

  @Test(arguments: [
    SigningIdentity(bundleId: "other.app", teamId: team, applicationIdentifier: group, sandboxEnabled: true, keychainGroups: [group]),
    SigningIdentity(bundleId: "com.keplr.vizor", teamId: "OTHERTEAM1", applicationIdentifier: group, sandboxEnabled: true, keychainGroups: [group]),
    SigningIdentity(bundleId: "com.keplr.vizor", teamId: team, applicationIdentifier: "other", sandboxEnabled: true, keychainGroups: [group]),
    SigningIdentity(bundleId: "com.keplr.vizor", teamId: team, applicationIdentifier: group, sandboxEnabled: false, keychainGroups: [group]),
    SigningIdentity(bundleId: "com.keplr.vizor", teamId: team, applicationIdentifier: group, sandboxEnabled: true, keychainGroups: [group, "other"]),
  ])
  func wrongIdentityCannotObserveOrMutateStorage(_ identity: SigningIdentity) throws {
    let model = Model()
    model.identity = identity
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "signing_identity_mismatch")
    #expect(model.calls == ["identity"])
    #expect(receipt.keychain.isEmpty)
    #expect(receipt.preferences == nil)
  }

  @Test func deletesOnlyOwnedServicesAndPrefixAndProvesAbsence() throws {
    let model = Model()
    let sibling = Item(service: "com.keplr.vizor.regtest.secure_store.e2e.vizor_a1b2c3d4e5_w2_18", group: group)
    let production = Item(service: "com.keplr.vizor.regtest.secure_store", group: group)
    let otherGroup = Item(service: wallet, group: "OTHER.com.keplr.vizor")
    model.items = [Item(service: wallet, group: group), Item(service: "\(wallet).mnemonic", group: group), sibling, production, otherGroup]
    model.preferences = ["\(prefix)account", "\(prefix)review", "flutter.ordinary", "flutter.vizor_e2e_vizor_a1b2c3d4e5_w2_18.account", "flutter.vizor_e2e_vizor_a1b2c3d4e5_w2_170.account"]
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(receipt.completed)
    #expect(receipt.errorCode == nil)
    #expect(model.items == [sibling, production, otherGroup])
    #expect(model.preferences == ["flutter.ordinary", "flutter.vizor_e2e_vizor_a1b2c3d4e5_w2_18.account", "flutter.vizor_e2e_vizor_a1b2c3d4e5_w2_170.account"])
    #expect(receipt.keychain.map(\.beforeStatus) == [errSecSuccess, errSecSuccess])
    #expect(receipt.keychain.map(\.afterStatus) == [errSecItemNotFound, errSecItemNotFound])
    #expect(receipt.preferences?.beforeCount == 2)
    #expect(receipt.preferences?.removedCount == 2)
    #expect(receipt.preferences?.afterCount == 0)
  }

  @Test func unavailableSigningEvidenceIsNotImplicitAccess() throws {
    let model = Model()
    model.identityError = CleanupFailure("keychain_groups_unavailable")
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "keychain_groups_unavailable")
    #expect(model.calls == ["identity"])
  }

  @Test func verifyRetainsPresentStateWithoutDeleteCalls() throws {
    let model = Model()
    model.items = [Item(service: wallet, group: group)]
    model.preferences = ["\(prefix)account"]
    let receipt = inspectOrClean(try scope(), mode: .verify, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "native_state_retained")
    #expect(receipt.keychain[0].afterStatus == errSecSuccess)
    #expect(receipt.preferences?.afterCount == 1)
    #expect(model.items == [Item(service: wallet, group: group)])
    #expect(model.preferences == ["\(prefix)account"])
    #expect(!model.calls.contains { $0.hasPrefix("delete:") || $0.hasPrefix("remove:") })
  }

  @Test func verifyAbsentStateSucceedsWithoutDeletion() throws {
    let model = Model()
    let receipt = inspectOrClean(try scope(), mode: .verify, system: model)
    #expect(receipt.completed)
    #expect(receipt.keychain.map(\.deleteStatus) == [nil, nil])
    #expect(receipt.preferences?.removedCount == 0)
    #expect(!model.calls.contains { $0.hasPrefix("delete:") || $0.hasPrefix("remove:") })
  }

  @Test(arguments: [errSecAuthFailed, errSecMissingEntitlement, errSecInteractionNotAllowed])
  func lookupErrorsAreNotAbsence(_ status: Int32) throws {
    let model = Model()
    model.lookupError = status
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "keychain_preflight_failed")
    #expect(receipt.errorStatus == status)
    #expect(receipt.keychain[0].beforeStatus == status)
    #expect(!model.calls.contains { $0.hasPrefix("delete:") || $0 == "keys" })
  }

  @Test func deleteErrorRetainsPartialStatusAndDoesNotCleanPreferences() throws {
    let model = Model()
    model.deleteError = errSecInteractionNotAllowed
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "keychain_delete_failed")
    #expect(receipt.keychain[0].deleteStatus == errSecInteractionNotAllowed)
    #expect(receipt.keychain[0].afterStatus == nil)
    #expect(!model.calls.contains("synchronize"))
  }

  @Test func successfulDeleteStatusWithoutAbsenceIsFailure() throws {
    let model = Model()
    model.items = [Item(service: wallet, group: group)]
    model.skipDeletion = true
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "keychain_delete_unproven")
    #expect(receipt.keychain[0].afterStatus == errSecSuccess)
    #expect(receipt.keychain.count == 1)
  }

  @Test func failedPreferenceSynchronizationPreventsSuccess() throws {
    let model = Model()
    model.preferences = ["\(prefix)account"]
    model.synchronizations = [true, false]
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "preferences_synchronize_failed")
    #expect(receipt.preferences?.synchronized == false)
    #expect(receipt.preferences?.afterCount == nil)
  }

  @Test func preferencesKeyListFailureIsNotAnEmptyPrefix() throws {
    let model = Model()
    model.keysError = CleanupFailure("preferences_keys_invalid")
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "preferences_keys_invalid")
    #expect(receipt.preferences == nil)
  }

  @Test func positivePreferenceAbsenceIsRequired() throws {
    let model = Model()
    model.preferences = ["\(prefix)account"]
    model.skipPreferenceRemoval = true
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    #expect(!receipt.completed)
    #expect(receipt.errorCode == "preferences_delete_unproven")
    #expect(receipt.preferences?.afterCount == 1)
  }

  @Test func sdkQueriesAreExactNoninteractiveAndNeverReturnSecrets() throws {
    let lookup = MacCleanupSystem.query(service: wallet, accessGroup: group, lookup: true)
    let deletion = MacCleanupSystem.query(service: wallet, accessGroup: group, lookup: false)
    #expect(lookup[kSecClass] as? String == kSecClassGenericPassword as String)
    #expect(lookup[kSecAttrService] as? String == wallet)
    #expect(lookup[kSecAttrAccessGroup] as? String == group)
    #expect(lookup[kSecAttrSynchronizable] as? String == kSecAttrSynchronizableAny as String)
    #expect(lookup[kSecUseDataProtectionKeychain] as? Bool == true)
    let context = try #require(lookup[kSecUseAuthenticationContext] as? LAContext)
    #expect(context.interactionNotAllowed)
    #expect(deletion[kSecMatchLimit] == nil)
    #expect(deletion[kSecReturnData] == nil)
    #expect(deletion[kSecReturnAttributes] == nil)
    #expect(deletion[kSecReturnRef] == nil)
    #expect(lookup[kSecReturnData] == nil)
    #expect(lookup[kSecReturnAttributes] == nil)
    #expect(lookup[kSecReturnRef] == nil)
  }

  @Test func receiptContainsNoPreferenceKeysOrSecretValues() throws {
    let model = Model()
    model.preferences = ["\(prefix)DO_NOT_REPORT_ACCOUNT_NAME"]
    let receipt = inspectOrClean(try scope(), mode: .delete, system: model)
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    let json = String(decoding: try encoder.encode(receipt), as: UTF8.self)
    #expect(!json.contains("DO_NOT_REPORT_ACCOUNT_NAME"))
    #expect(json.contains("\"after_count\":0"))
    #expect(!json.contains("storage_cleanup_completed"))
    #expect(!json.contains("support_directory"))
  }
}
