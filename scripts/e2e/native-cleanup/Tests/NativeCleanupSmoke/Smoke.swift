// MANUAL native mutation smoke, not a SwiftPM test target or product.
// Compile alongside the two NativeCleanup sources, then sign a non-UI app
// bundle with the cohort's identity/profile. Never run a real wallet executable.
import CoreFoundation
import Foundation
import Security

@main
enum Smoke {
  static func main() {
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      guard arguments.count == 2, arguments[0] == "--team" else {
        throw CleanupFailure("invalid_arguments")
      }
      let receipt = try run(expectedTeam: arguments[1])
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase
      encoder.outputFormatting = [.sortedKeys]
      print(String(decoding: try encoder.encode(receipt), as: UTF8.self))
      print("PASS: owned native state absent; siblings retained; all inserted fixture state cleaned")
    } catch let failure as CleanupFailure {
      print("FAIL: \(failure.code); status=\(failure.status.map(String.init) ?? "none")")
      exit(1)
    } catch {
      print("FAIL: unexpected_native_error")
      exit(1)
    }
  }

  private static func run(expectedTeam: String) throws -> MacCleanupReceipt {
    let runId = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10))
    let owned = try MacCleanupScope(namespace: "vizor_\(runId)_w0_0", expectedTeam: expectedTeam)
    let sibling = try MacCleanupScope(namespace: "vizor_\(runId)_w0_1", expectedTeam: expectedTeam)
    let system = MacCleanupSystem()
    let identity = try system.signingIdentity()
    try identity.validate(for: owned)
    let group = identity.applicationIdentifier
    let sentinel = "e2e_cleanup_probe_\(runId)"
    let ownKey = owned.preferencesPrefix + "fixture"
    let siblingKey = sibling.preferencesPrefix + "fixture"
    for service in owned.services + sibling.services {
      guard system.lookup(service: service, accessGroup: group) == errSecItemNotFound else {
        throw CleanupFailure("fixture_service_already_exists")
      }
    }
    let keys = try system.preferenceKeys()
    guard !keys.contains(sentinel), !keys.contains(where: {
      $0.hasPrefix(owned.preferencesPrefix) || $0.hasPrefix(sibling.preferencesPrefix)
    }) else { throw CleanupFailure("fixture_prefix_already_exists") }
    // Flush the intended exact scope before seeding so interrupted smoke logs
    // identify partial fixture state, without exposing any secret values.
    print("fixture_namespaces: \(owned.namespace), \(sibling.namespace)")
    fflush(stdout)
    var inserted: [String] = []
    var insertedPreferences: [String] = []
    var receipt: MacCleanupReceipt?
    var primary: CleanupFailure?
    do {
      for service in owned.services + sibling.services {
        let query: [CFString: Any] = [
          kSecClass: kSecClassGenericPassword, kSecAttrService: service,
          kSecAttrAccessGroup: group, kSecAttrAccount: "synthetic-fixture-only",
          kSecUseDataProtectionKeychain: true,
          kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
          kSecValueData: Data("synthetic-test-data".utf8),
        ]
        let added = SecItemAdd(query as CFDictionary, nil)
        guard added == errSecSuccess else { throw CleanupFailure("fixture_insert_failed", status: added) }
        inserted.append(service)
      }
      for key in [sentinel, ownKey, siblingKey] {
        CFPreferencesSetValue(key as CFString, true as CFBoolean, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        insertedPreferences.append(key)
      }
      guard system.synchronizePreferences() else { throw CleanupFailure("fixture_preferences_failed") }
      let before = inspectOrClean(owned, mode: .verify, system: system)
      guard !before.completed, before.errorCode == "native_state_retained",
        before.keychain.count == 2,
        before.keychain.allSatisfy({ $0.afterStatus == errSecSuccess }),
        before.preferences?.afterCount == 1
      else { throw CleanupFailure("fixture_presence_unproven") }
      let cleaned = inspectOrClean(owned, mode: .delete, system: system)
      guard cleaned.completed else {
        throw CleanupFailure(cleaned.errorCode ?? "fixture_cleanup_unproven", status: cleaned.errorStatus)
      }
      receipt = cleaned
      guard sibling.services.allSatisfy({ system.lookup(service: $0, accessGroup: group) == errSecSuccess }) else {
        throw CleanupFailure("sibling_services_changed")
      }
      let afterKeys = Set(try system.preferenceKeys())
      guard afterKeys.contains(sentinel), afterKeys.contains(siblingKey), !afterKeys.contains(ownKey) else {
        throw CleanupFailure("sibling_preferences_changed")
      }
      guard inspectOrClean(owned, mode: .verify, system: system).completed else {
        throw CleanupFailure("read_only_absence_unproven")
      }
    } catch let failure as CleanupFailure {
      primary = failure
    } catch {
      primary = CleanupFailure("fixture_native_operation_failed")
    }
    var cleanupUnproven = false
    for service in inserted {
      let status = system.delete(service: service, accessGroup: group)
      if (status != errSecSuccess && status != errSecItemNotFound)
        || system.lookup(service: service, accessGroup: group) != errSecItemNotFound
      { cleanupUnproven = true }
    }
    for key in insertedPreferences { system.removePreference(key) }
    if !system.synchronizePreferences() { cleanupUnproven = true }
    do {
      let remaining = Set(try system.preferenceKeys())
      if insertedPreferences.contains(where: remaining.contains) { cleanupUnproven = true }
    } catch { cleanupUnproven = true }
    if cleanupUnproven { print("RETAINED: fixture_cleanup_unproven; see exact namespaces above") }
    if let primary { throw primary }
    guard !cleanupUnproven, let receipt else { throw CleanupFailure("fixture_cleanup_unproven") }
    return receipt
  }
}
