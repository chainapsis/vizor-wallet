import CoreFoundation
import Foundation
import LocalAuthentication
import Security

package struct MacCleanupSystem: CleanupSystem {
  package init() {}

  package func signingIdentity() throws -> SigningIdentity {
    var code: SecCode?
    let copied = SecCodeCopySelf(SecCSFlags(), &code)
    guard copied == errSecSuccess, let code else {
      throw CleanupFailure("code_identity_unavailable", status: copied)
    }
    let validity = SecCodeCheckValidity(code, SecCSFlags(), nil)
    guard validity == errSecSuccess else {
      throw CleanupFailure("code_signature_invalid", status: validity)
    }
    guard let bundleId = Bundle.main.bundleIdentifier,
      let task = SecTaskCreateFromSelf(nil),
      let teamId = SecTaskCopyValueForEntitlement(task, "com.apple.developer.team-identifier" as CFString, nil) as? String,
      let applicationIdentifier = SecTaskCopyValueForEntitlement(task, "com.apple.application-identifier" as CFString, nil) as? String,
      let sandboxEnabled = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool
    else { throw CleanupFailure("signing_entitlements_unavailable") }
    var groupError: Unmanaged<CFError>?
    let rawGroups = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, &groupError)
    if let groupError {
      _ = groupError.takeRetainedValue() // Release without logging native error content.
      throw CleanupFailure("keychain_groups_unavailable")
    }
    let groups: [String]?
    if let rawGroups {
      guard let strings = rawGroups as? [String] else {
        throw CleanupFailure("keychain_groups_invalid")
      }
      groups = strings
    } else { groups = nil }
    return SigningIdentity(
      bundleId: bundleId, teamId: teamId, applicationIdentifier: applicationIdentifier,
      sandboxEnabled: sandboxEnabled, keychainGroups: groups
    )
  }

  static func query(service: String, accessGroup: String, lookup: Bool) -> [CFString: Any] {
    let authentication = LAContext()
    authentication.interactionNotAllowed = true
    var query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccessGroup: accessGroup,
      kSecAttrSynchronizable: kSecAttrSynchronizableAny,
      kSecUseDataProtectionKeychain: true,
      kSecUseAuthenticationContext: authentication,
    ]
    if lookup { query[kSecMatchLimit] = kSecMatchLimitOne }
    return query
  }

  package func lookup(service: String, accessGroup: String) -> Int32 {
    SecItemCopyMatching(Self.query(service: service, accessGroup: accessGroup, lookup: true) as CFDictionary, nil)
  }

  package func delete(service: String, accessGroup: String) -> Int32 {
    SecItemDelete(Self.query(service: service, accessGroup: accessGroup, lookup: false) as CFDictionary)
  }

  package func synchronizePreferences() -> Bool {
    CFPreferencesSynchronize(kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  }

  package func preferenceKeys() throws -> [String] {
    guard let keys = CFPreferencesCopyKeyList(
      kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost
    ) else { return [] }
    guard let strings = keys as? [String] else { throw CleanupFailure("preferences_keys_invalid") }
    return strings
  }

  package func removePreference(_ key: String) {
    CFPreferencesSetValue(key as CFString, nil, kCFPreferencesCurrentApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
  }
}
