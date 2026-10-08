#if os(iOS) && targetEnvironment(simulator)
import CoreFoundation
import Foundation
import LocalAuthentication
import Security
import UserNotifications

@MainActor package struct NativeIosCleanupSystem: IosCleanupSystem {
  package init() {}

  package func identity() throws -> IosHelperIdentity {
    guard let bundle = Bundle.main.bundleIdentifier,
      let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"],
      let marker = Bundle.main.object(forInfoDictionaryKey: "VizorE2eIosCleanup") as? NSNumber,
      CFGetTypeID(marker) == CFBooleanGetTypeID()
    else { throw CleanupFailure("ios_helper_identity_unavailable") }
    guard let executable = Bundle.main.executableURL else { throw CleanupFailure("ios_entitlements_missing") }
    let embedded = try iosSimulatedEntitlements(Data(contentsOf: executable, options: .mappedIfSafe))
    let applicationIdentifier = try iosHelperApplicationIdentifier(embedded)
    // Compilation excludes physical devices. Runtime checks embedded Simulator
    // rights, not just codesign's empty ad-hoc entitlement output. Host capture
    // still must match this default group to the actual trusted cohort build.
    return IosHelperIdentity(bundleId: bundle, simulatorUdid: udid,
      isSimulator: true, cleanupBuildMarker: marker.boolValue,
      applicationIdentifier: applicationIdentifier)
  }

  static func query(service: String, lookup: Bool) -> [CFString: Any] {
    // Match the wallet's iOS service-only queries under this app's access rights.
    // No guessed group or caller-chosen group is accepted. Host provisioning
    // must reject shared/extra access rights before composing device cleanup.
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    var query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword, kSecAttrService: service,
      kSecAttrSynchronizable: kSecAttrSynchronizableAny,
      kSecUseAuthenticationContext: authentication,
    ]
    if lookup {
      query[kSecMatchLimit] = kSecMatchLimitOne
      query[kSecReturnAttributes] = true
    }
    return query
  }

  package func lookup(service: String) -> Int32 {
    var attributes: CFTypeRef?
    return SecItemCopyMatching(Self.query(service: service, lookup: true) as CFDictionary, &attributes)
  }
  package func delete(service: String) -> Int32 {
    SecItemDelete(Self.query(service: service, lookup: false) as CFDictionary)
  }
  package func synchronizePreferences(domain: String) -> Bool {
    CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  }
  package func preferenceKeys(domain: String) throws -> [String] {
    guard let raw = CFPreferencesCopyKeyList(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return [] }
    guard let keys = raw as? [String] else { throw CleanupFailure("preferences_keys_invalid") }
    return keys
  }
  package func removePreference(_ key: String, domain: String) {
    CFPreferencesSetValue(key as CFString, nil, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  }
  package func notificationIdentifiers(delivered: Bool) async throws -> [String] {
    let center = UNUserNotificationCenter.current()
    if delivered { return await center.deliveredNotifications().map { $0.request.identifier } }
    return await center.pendingNotificationRequests().map { $0.identifier }
  }
  package func removeNotifications(_ identifiers: [String], delivered: Bool) {
    let center = UNUserNotificationCenter.current()
    if delivered { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    else { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
  }
}
#endif
