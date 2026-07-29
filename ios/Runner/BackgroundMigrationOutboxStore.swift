import CryptoKit
import Foundation
import Security

let ironwoodMigrationOutboxKeyService =
  "com.keplr.vizor.ironwood-migration-outbox-key.v1"

enum BackgroundMigrationOutboxStoreError: Error, Equatable {
  case temporarilyUnavailable
  case invalidKey
  case keychain(OSStatus)
  case invalidCiphertext
  case unsupportedVersion
}

enum BackgroundMigrationOutboxCipher {
  private static let authenticatedData = Data("vizor-ironwood-outbox-v1".utf8)

  static func seal(_ plaintext: Data, keyData: Data) throws -> Data {
    guard keyData.count == 32 else { throw BackgroundMigrationOutboxStoreError.invalidKey }
    let key = SymmetricKey(data: keyData)
    let box = try AES.GCM.seal(plaintext, using: key, authenticating: authenticatedData)
    guard let combined = box.combined else {
      throw BackgroundMigrationOutboxStoreError.invalidCiphertext
    }
    return combined
  }

  static func open(_ ciphertext: Data, keyData: Data) throws -> Data {
    guard keyData.count == 32 else { throw BackgroundMigrationOutboxStoreError.invalidKey }
    do {
      let box = try AES.GCM.SealedBox(combined: ciphertext)
      return try AES.GCM.open(
        box,
        using: SymmetricKey(data: keyData),
        authenticating: authenticatedData
      )
    } catch {
      throw BackgroundMigrationOutboxStoreError.invalidCiphertext
    }
  }
}

enum BackgroundMigrationOutboxKeyStore {
  private static let account = "master-key"

  static func loadOrCreate() throws -> Data {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: ironwoodMigrationOutboxKeyService,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data, data.count == 32 else {
        throw BackgroundMigrationOutboxStoreError.invalidKey
      }
      return data
    case errSecInteractionNotAllowed:
      throw BackgroundMigrationOutboxStoreError.temporarilyUnavailable
    case errSecItemNotFound:
      var key = Data(count: 32)
      let randomStatus = key.withUnsafeMutableBytes { bytes in
        SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
      }
      guard randomStatus == errSecSuccess else {
        throw BackgroundMigrationOutboxStoreError.keychain(randomStatus)
      }
      let add: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: ironwoodMigrationOutboxKeyService,
        kSecAttrAccount: account,
        kSecValueData: key,
        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        kSecAttrSynchronizable: false,
      ]
      let addStatus = SecItemAdd(add as CFDictionary, nil)
      if addStatus == errSecDuplicateItem { return try loadOrCreate() }
      guard addStatus == errSecSuccess else {
        throw BackgroundMigrationOutboxStoreError.keychain(addStatus)
      }
      return key
    default:
      throw BackgroundMigrationOutboxStoreError.keychain(status)
    }
  }
}

final class BackgroundMigrationOutboxStore: @unchecked Sendable {
  static let shared = BackgroundMigrationOutboxStore()

  private let queue = DispatchQueue(label: "com.keplr.vizor.ironwood-outbox")
  private let fileURL: URL
  private let keyProvider: () throws -> Data

  init(
    fileURL: URL? = nil,
    keyProvider: @escaping () throws -> Data = BackgroundMigrationOutboxKeyStore.loadOrCreate
  ) {
    if let fileURL {
      self.fileURL = fileURL
    } else {
      let support = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first!
      self.fileURL =
        support
        .appendingPathComponent("IronwoodMigration", isDirectory: true)
        .appendingPathComponent("background-outbox-v1.bin")
    }
    self.keyProvider = keyProvider
  }

  func read() throws -> BackgroundMigrationOutboxSnapshot {
    try queue.sync { try readUnlocked() }
  }

  func update(
    _ mutation: (inout BackgroundMigrationOutboxSnapshot) throws -> Void
  ) throws -> BackgroundMigrationOutboxSnapshot {
    try queue.sync {
      var snapshot = try readUnlocked()
      try mutation(&snapshot)
      try writeUnlocked(snapshot)
      return snapshot
    }
  }

  func removeAll() throws {
    try queue.sync {
      guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
      try FileManager.default.removeItem(at: fileURL)
    }
  }

  private func readUnlocked() throws -> BackgroundMigrationOutboxSnapshot {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return BackgroundMigrationOutboxSnapshot()
    }
    let key = try keyProvider()
    let encrypted = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    let plaintext = try BackgroundMigrationOutboxCipher.open(encrypted, keyData: key)
    let snapshot = try JSONDecoder().decode(
      BackgroundMigrationOutboxSnapshot.self,
      from: plaintext
    )
    guard snapshot.version == BackgroundMigrationOutboxSnapshot.currentVersion else {
      throw BackgroundMigrationOutboxStoreError.unsupportedVersion
    }
    return snapshot
  }

  private func writeUnlocked(_ snapshot: BackgroundMigrationOutboxSnapshot) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
    )
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: directory.path
    )
    let plaintext = try JSONEncoder().encode(snapshot)
    let encrypted = try BackgroundMigrationOutboxCipher.seal(
      plaintext,
      keyData: try keyProvider()
    )
    try encrypted.write(to: fileURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
      ofItemAtPath: fileURL.path
    )
  }
}
