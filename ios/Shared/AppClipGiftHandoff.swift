import Foundation
import Security

/// Hands a Gift Card link from the App Clip to the full app after install.
///
/// The App Clip saves the link in the keychain. On iOS 15.4 and later the
/// full app can read keychain items its App Clip created; the parent and
/// associated App Clip entitlements grant that access. App Clips cannot use
/// `keychain-access-groups`, so both sides use the default access group and
/// never set `kSecAttrAccessGroup`.
///
/// The link is a bearer secret. Never log it, and never write it to an app
/// group container, `UserDefaults`, or any other unencrypted store.
enum AppClipGiftHandoff {
  static let paymentLinkPath = "/payment-links/open"
  /// Matches Dart's `VizorPaymentLink.maxEncodedLength`.
  static let maxLinkBytes = 16 * 1024
  static let defaultKeychainService = "com.keplr.vizor.appclip.gift-link"
  private static let keychainAccount = "pending"
  private static let supportedFragmentPrefixes = ["v1=", "v2=", "v3="]

  /// True for the Gift Card link shape the gateway page and Dart accept:
  /// `https://<host>/payment-links/open#v<n>=<payload>` with no query,
  /// credentials, or port. Dart still validates the payload itself.
  static func isGiftLink(_ url: URL, host: String) -> Bool {
    guard
      url.scheme?.lowercased() == "https",
      url.host?.lowercased() == host.lowercased(),
      url.user == nil,
      url.password == nil,
      url.port == nil,
      url.path == paymentLinkPath,
      url.query == nil,
      let fragment = url.fragment,
      url.absoluteString.utf8.count <= maxLinkBytes,
      let prefix = supportedFragmentPrefixes.first(where: { fragment.hasPrefix($0) })
    else {
      return false
    }
    let payload = fragment.dropFirst(prefix.count)
    return !payload.isEmpty && !payload.contains("&")
  }

  /// App Clip side: replaces any earlier pending link with `url`.
  @discardableResult
  static func save(
    _ url: URL,
    service: String = defaultKeychainService
  ) -> Bool {
    guard let data = url.absoluteString.data(using: .utf8) else { return false }
    let query = baseQuery(service: service)
    SecItemDelete(query as CFDictionary)
    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] =
      kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  /// Full app side: returns the pending link once and deletes it.
  ///
  /// A link that no longer matches `host` (for example after a host change)
  /// is deleted without being returned.
  static func consume(
    host: String,
    service: String = defaultKeychainService
  ) -> URL? {
    var query = baseQuery(service: service)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess else { return nil }
    SecItemDelete(baseQuery(service: service) as CFDictionary)

    guard
      let data = result as? Data,
      let string = String(data: data, encoding: .utf8),
      let url = URL(string: string),
      isGiftLink(url, host: host)
    else {
      return nil
    }
    return url
  }

  private static func baseQuery(service: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: keychainAccount,
    ]
  }
}
