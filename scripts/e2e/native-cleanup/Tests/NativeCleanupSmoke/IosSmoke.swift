// MANUAL synthetic mutation fixture, not a SwiftPM target or wallet app source.
// Install only on a fresh owned simulator. Never use an existing/user device.
#if os(iOS) && targetEnvironment(simulator)
import CoreFoundation
import Foundation
import Security
import UIKit

@main enum IosSmoke {
  @MainActor static func main() {
    UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(IosSmokeDelegate.self))
  }
}

@MainActor final class IosSmokeDelegate: UIResponder, UIApplicationDelegate {
  func application(_ app: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    Task { @MainActor in
      do {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 4, args[0] == "--owner-nonce", args[2] == "--team" else {
          throw CleanupFailure("invalid_arguments")
        }
        try await run(nonce: args[1], team: args[3])
        print("PASS: all inserted synthetic native state absent; sibling and sentinel checks passed")
        fflush(stdout)
        exit(0)
      } catch let failure as CleanupFailure {
        print("FAIL: \(failure.code); status=\(failure.status.map(String.init) ?? "none")")
        fflush(stdout)
        exit(1)
      } catch {
        print("FAIL: unexpected_native_error")
        fflush(stdout)
        exit(1)
      }
    }
    return true
  }

  private func run(nonce: String, team: String) async throws {
    let system = NativeIosCleanupSystem()
    let identity = try system.identity()
    let run = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(10))
    let owned = try IosCleanupScope(namespace: "vizor_\(run)_w0_0", simulatorUdid: identity.simulatorUdid, ownerNonce: nonce, expectedTeam: team)
    let sibling = try IosCleanupScope(namespace: "vizor_\(run)_w0_1", simulatorUdid: identity.simulatorUdid, ownerNonce: nonce, expectedTeam: team)
    try identity.validate(for: owned)
    // Read-only paired control for the initial simulator entitlement failure.
    // This does not read values or broaden deletion queries.
    var explicit = NativeIosCleanupSystem.query(service: owned.services[0], lookup: true)
    explicit[kSecAttrAccessGroup] = "com.keplr.vizor"
    var attributes: CFTypeRef?
    let explicitStatus = SecItemCopyMatching(explicit as CFDictionary, &attributes)
    print("group_query_control: default=\(system.lookup(service: owned.services[0])); explicit=\(explicitStatus)")
    fflush(stdout)
    for scope in [owned, sibling] {
      guard await inspectOrCleanIos(scope, mode: .verify, system: system).completed else {
        throw CleanupFailure("fixture_scope_not_empty")
      }
    }
    let sentinel = "ios_native_smoke_\(run)"
    guard !(try system.preferenceKeys(domain: "com.keplr.vizor")).contains(sentinel) else {
      throw CleanupFailure("fixture_sentinel_already_exists")
    }
    print("fixture_namespaces: \(owned.namespace), \(sibling.namespace)")
    fflush(stdout)
    var inserted: [String] = []
    var preferences: [(String, String)] = []
    var primary: Error?
    do {
      for service in owned.services + sibling.services {
        // Like the wallet, use the application's actual default Keychain scope,
        // never a caller-chosen group or a guessed macOS team-prefixed group.
        let query: [CFString: Any] = [
          kSecClass: kSecClassGenericPassword, kSecAttrService: service,
          kSecAttrAccount: "synthetic-fixture-only", kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
          kSecValueData: Data("synthetic-fixture-data".utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CleanupFailure("fixture_insert_failed", status: status) }
        inserted.append(service)
        guard system.lookup(service: service) == errSecSuccess else {
          throw CleanupFailure("fixture_default_access_group_unproven")
        }
      }
      let keys = [("com.keplr.vizor", sentinel), ("com.keplr.vizor", owned.preferencesPrefix + "fixture"),
        ("com.keplr.vizor", sibling.preferencesPrefix + "fixture"), (owned.defaultsSuite, "fixture"), (sibling.defaultsSuite, "fixture")]
      for (domain, key) in keys {
        CFPreferencesSetValue(key as CFString, true as CFBoolean, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        preferences.append((domain, key))
      }
      for domain in Set(keys.map(\.0)) {
        guard system.synchronizePreferences(domain: domain) else { throw CleanupFailure("fixture_preferences_failed") }
      }
      let before = await inspectOrCleanIos(owned, mode: .verify, system: system)
      guard !before.completed, before.errorCode == "native_state_retained",
        before.keychain.count == 5, before.keychain.allSatisfy({ $0.afterStatus == errSecSuccess }),
        before.preferences.map(\.afterCount) == [1, 1]
      else { throw CleanupFailure("fixture_presence_unproven") }
      let cleaned = await inspectOrCleanIos(owned, mode: .delete, system: system)
      guard cleaned.completed else { throw CleanupFailure(cleaned.errorCode ?? "fixture_cleanup_unproven", status: cleaned.errorStatus) }
      let encoder = JSONEncoder()
      encoder.keyEncodingStrategy = .convertToSnakeCase
      encoder.outputFormatting = [.sortedKeys]
      print(String(decoding: try encoder.encode(cleaned), as: UTF8.self))
      guard sibling.services.allSatisfy({ system.lookup(service: $0) == errSecSuccess }) else {
        throw CleanupFailure("sibling_services_changed")
      }
      let remaining = Set(try system.preferenceKeys(domain: "com.keplr.vizor"))
      guard remaining.contains(sentinel), remaining.contains(sibling.preferencesPrefix + "fixture"),
        !remaining.contains(owned.preferencesPrefix + "fixture"),
        try system.preferenceKeys(domain: sibling.defaultsSuite) == ["fixture"]
      else { throw CleanupFailure("sibling_preferences_changed") }
      guard await inspectOrCleanIos(owned, mode: .verify, system: system).completed else {
        throw CleanupFailure("read_only_absence_unproven")
      }
    } catch { primary = error }
    var unproven = false
    for service in inserted {
      let status = system.delete(service: service)
      if (status != errSecSuccess && status != errSecItemNotFound)
        || system.lookup(service: service) != errSecItemNotFound { unproven = true }
    }
    for (domain, key) in preferences { system.removePreference(key, domain: domain) }
    for domain in Set(preferences.map(\.0)) {
      if !system.synchronizePreferences(domain: domain) { unproven = true }
    }
    for (domain, key) in preferences {
      do {
        if try system.preferenceKeys(domain: domain).contains(key) { unproven = true }
      } catch { unproven = true }
    }
    if unproven { print("RETAINED: fixture native cleanup unproven; see namespaces above") }
    if let primary { throw primary }
    guard !unproven else { throw CleanupFailure("fixture_native_cleanup_unproven") }
  }
}
#else
#error("The manual native fixture only supports iOS Simulator")
#endif
