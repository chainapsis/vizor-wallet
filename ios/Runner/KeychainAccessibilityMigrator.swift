import Flutter
import Foundation
import Security

let keychainAccessibilityMigrationChannelName =
  "com.zcash.wallet/keychain_accessibility_migration"
let keychainAccessibilityMigrationStagingSuffix =
  ".accessibility-migration-v1"
let keychainAccessibilityMigrationAllowedServices = [
  "com.keplr.vizor.secure_store",
  "com.keplr.vizor.ironwood.secure_store",
  "com.keplr.vizor.test.secure_store",
  "com.keplr.vizor.regtest.secure_store",
]

private let keychainAccessibilityTarget =
  kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
private let keychainAccessibilityLegacy =
  kSecAttrAccessibleAfterFirstUnlock as String

struct KeychainAccessibilityMigrationItem: Equatable {
  let account: String
  let data: Data
  let accessibility: String
  let attributes: [String: AnyHashable]

  static func == (
    lhs: KeychainAccessibilityMigrationItem,
    rhs: KeychainAccessibilityMigrationItem
  ) -> Bool {
    lhs.account == rhs.account
      && lhs.data == rhs.data
      && lhs.accessibility == rhs.accessibility
      && lhs.attributes == rhs.attributes
  }
}

protocol KeychainAccessibilityMigrationStore {
  func items(service: String) throws -> [KeychainAccessibilityMigrationItem]
  func add(
    _ item: KeychainAccessibilityMigrationItem,
    service: String
  ) throws
  func delete(service: String, account: String) throws
}

enum KeychainAccessibilityMigrationError: Error, Equatable {
  case invalidService
  case duplicateAccount(String)
  case conflictingCopies(String)
  case unexpectedAccessibility(account: String, accessibility: String)
  case protectedDataUnavailable
  case keychain(operation: String, status: OSStatus)
}

final class KeychainAccessibilityMigrator {
  static let shared = KeychainAccessibilityMigrator()

  private static let allowedServices = Set(
    keychainAccessibilityMigrationAllowedServices
  )

  private let store: KeychainAccessibilityMigrationStore

  init(store: KeychainAccessibilityMigrationStore = SecurityKeychainMigrationStore()) {
    self.store = store
  }

  @discardableResult
  func ensureFirstUnlockThisDeviceOnly(service: String) throws -> Int {
    guard Self.allowedServices.contains(service) else {
      throw KeychainAccessibilityMigrationError.invalidService
    }

    let stagingService = service + keychainAccessibilityMigrationStagingSuffix
    let canonical = try indexedItems(try store.items(service: service))
    let staged = try indexedItems(try store.items(service: stagingService))
    let accounts = Set(canonical.keys).union(staged.keys).sorted()
    var migratedCount = 0

    for account in accounts {
      let didMigrate = try migrate(
        account: account,
        canonical: canonical[account],
        staged: staged[account],
        service: service,
        stagingService: stagingService
      )
      if didMigrate {
        migratedCount += 1
      }
    }
    return migratedCount
  }

  private func indexedItems(
    _ items: [KeychainAccessibilityMigrationItem]
  ) throws -> [String: KeychainAccessibilityMigrationItem] {
    var result: [String: KeychainAccessibilityMigrationItem] = [:]
    for item in items {
      if result.updateValue(item, forKey: item.account) != nil {
        throw KeychainAccessibilityMigrationError.duplicateAccount(item.account)
      }
    }
    return result
  }

  private func migrate(
    account: String,
    canonical: KeychainAccessibilityMigrationItem?,
    staged: KeychainAccessibilityMigrationItem?,
    service: String,
    stagingService: String
  ) throws -> Bool {
    if let staged {
      try requireTarget(staged)
    }

    guard let canonical else {
      guard let staged else { return false }
      try store.add(staged, service: service)
      try verify(staged, service: service)
      try store.delete(service: stagingService, account: account)
      return true
    }

    if canonical.accessibility == keychainAccessibilityTarget {
      guard let staged else { return false }
      try requireMatchingData(canonical, staged)
      try store.delete(service: stagingService, account: account)
      return false
    }

    guard canonical.accessibility == keychainAccessibilityLegacy else {
      throw KeychainAccessibilityMigrationError.unexpectedAccessibility(
        account: account,
        accessibility: canonical.accessibility
      )
    }

    if let staged {
      try requireMatchingData(canonical, staged)
    } else {
      try store.add(canonical, service: stagingService)
      try verify(canonical, service: stagingService)
    }

    try store.delete(service: service, account: account)
    try store.add(canonical, service: service)
    try verify(canonical, service: service)
    try store.delete(service: stagingService, account: account)
    return true
  }

  private func requireTarget(
    _ item: KeychainAccessibilityMigrationItem
  ) throws {
    guard item.accessibility == keychainAccessibilityTarget else {
      throw KeychainAccessibilityMigrationError.unexpectedAccessibility(
        account: item.account,
        accessibility: item.accessibility
      )
    }
  }

  private func requireMatchingData(
    _ lhs: KeychainAccessibilityMigrationItem,
    _ rhs: KeychainAccessibilityMigrationItem
  ) throws {
    guard lhs.data == rhs.data else {
      throw KeychainAccessibilityMigrationError.conflictingCopies(lhs.account)
    }
  }

  private func verify(
    _ expected: KeychainAccessibilityMigrationItem,
    service: String
  ) throws {
    let matches = try store.items(service: service).filter {
      $0.account == expected.account
    }
    guard matches.count == 1 else {
      throw KeychainAccessibilityMigrationError.conflictingCopies(expected.account)
    }
    let actual = matches[0]
    try requireTarget(actual)
    try requireMatchingData(expected, actual)
  }
}

final class SecurityKeychainMigrationStore: KeychainAccessibilityMigrationStore {
  func items(service: String) throws -> [KeychainAccessibilityMigrationItem] {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecReturnAttributes: true,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitAll,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return []
    }
    try check(status, operation: "read")

    guard let dictionaries = result as? [[CFString: Any]] else {
      throw KeychainAccessibilityMigrationError.keychain(
        operation: "decode",
        status: errSecDecode
      )
    }

    return try dictionaries.map { attributes in
      guard
        let account = attributes[kSecAttrAccount] as? String,
        let data = attributes[kSecValueData] as? Data,
        let accessibility = attributes[kSecAttrAccessible] as? String
      else {
        throw KeychainAccessibilityMigrationError.keychain(
          operation: "decode",
          status: errSecDecode
        )
      }

      var preserved: [String: AnyHashable] = [:]
      for key in [
        kSecAttrLabel,
        kSecAttrDescription,
        kSecAttrComment,
        kSecAttrGeneric,
        kSecAttrIsInvisible,
        kSecAttrIsNegative,
        kSecAttrAccessGroup,
      ] {
        if let value = attributes[key] as? AnyHashable {
          preserved[key as String] = value
        }
      }
      return KeychainAccessibilityMigrationItem(
        account: account,
        data: data,
        accessibility: accessibility,
        attributes: preserved
      )
    }
  }

  func add(
    _ item: KeychainAccessibilityMigrationItem,
    service: String
  ) throws {
    var error: Unmanaged<CFError>?
    guard
      let accessControl = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        [],
        &error
      )
    else {
      _ = error?.takeRetainedValue()
      throw KeychainAccessibilityMigrationError.keychain(
        operation: "create_access_control",
        status: errSecParam
      )
    }

    var query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: item.account,
      kSecAttrService: service,
      kSecAttrAccessControl: accessControl,
      kSecValueData: item.data,
    ]
    for (key, value) in item.attributes {
      query[key as CFString] = value
    }
    try check(SecItemAdd(query as CFDictionary, nil), operation: "add")
  }

  func delete(service: String, account: String) throws {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    if status == errSecItemNotFound { return }
    try check(status, operation: "delete")
  }

  private func check(_ status: OSStatus, operation: String) throws {
    if status == errSecSuccess { return }
    if status == errSecInteractionNotAllowed {
      throw KeychainAccessibilityMigrationError.protectedDataUnavailable
    }
    throw KeychainAccessibilityMigrationError.keychain(
      operation: operation,
      status: status
    )
  }
}

final class KeychainAccessibilityMigrationChannel {
  private let queue = DispatchQueue(
    label: "com.zcash.wallet.keychain-accessibility-migration",
    qos: .userInitiated
  )

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "ensureFirstUnlockThisDeviceOnly" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let service = arguments["service"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "Missing secure-store service.",
          details: nil
        )
      )
      return
    }

    queue.async {
      do {
        let migrated = try KeychainAccessibilityMigrator.shared
          .ensureFirstUnlockThisDeviceOnly(service: service)
        DispatchQueue.main.async {
          result(["status": "complete", "migrated": migrated])
        }
      } catch {
        let flutterError = Self.flutterError(error)
        DispatchQueue.main.async { result(flutterError) }
      }
    }
  }

  private static func flutterError(_ error: Error) -> FlutterError {
    guard let migrationError = error as? KeychainAccessibilityMigrationError else {
      return FlutterError(
        code: "migration_failed",
        message: "The iOS secure-store migration failed.",
        details: String(describing: error)
      )
    }
    switch migrationError {
    case .protectedDataUnavailable:
      return FlutterError(
        code: "protected_data_unavailable",
        message: "Unlock the device once after restart to access secure storage.",
        details: nil
      )
    case .keychain(let operation, let status):
      return FlutterError(
        code: "keychain_error",
        message: "The iOS secure-store migration failed.",
        details: ["operation": operation, "status": status]
      )
    case .invalidService:
      return FlutterError(
        code: "invalid_service",
        message: "The secure-store service is not allowed.",
        details: nil
      )
    case .duplicateAccount(let account),
      .conflictingCopies(let account):
      return FlutterError(
        code: "migration_conflict",
        message: "Conflicting secure-store copies were found.",
        details: ["account": account]
      )
    case .unexpectedAccessibility(let account, let accessibility):
      return FlutterError(
        code: "unexpected_accessibility",
        message: "An unexpected secure-store protection class was found.",
        details: ["account": account, "accessibility": accessibility]
      )
    }
  }
}
