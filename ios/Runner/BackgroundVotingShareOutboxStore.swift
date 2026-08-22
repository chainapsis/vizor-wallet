import CryptoKit
import Foundation
import Security

let votingShareOutboxKeyService =
  "com.keplr.vizor.voting-share-outbox-key.v1"

enum BackgroundVotingShareOutboxStoreError: Error, Equatable {
  case temporarilyUnavailable
  case invalidKey
  case keychain(OSStatus)
  case invalidCiphertext
  case unsupportedVersion
}

enum BackgroundVotingShareOutboxCipher {
  private static let authenticatedData = Data("vizor-voting-share-outbox-v1".utf8)

  static func seal(_ plaintext: Data, keyData: Data) throws -> Data {
    guard keyData.count == 32 else {
      throw BackgroundVotingShareOutboxStoreError.invalidKey
    }
    let key = SymmetricKey(data: keyData)
    let box = try AES.GCM.seal(plaintext, using: key, authenticating: authenticatedData)
    guard let combined = box.combined else {
      throw BackgroundVotingShareOutboxStoreError.invalidCiphertext
    }
    return combined
  }

  static func open(_ ciphertext: Data, keyData: Data) throws -> Data {
    guard keyData.count == 32 else {
      throw BackgroundVotingShareOutboxStoreError.invalidKey
    }
    do {
      let box = try AES.GCM.SealedBox(combined: ciphertext)
      return try AES.GCM.open(
        box,
        using: SymmetricKey(data: keyData),
        authenticating: authenticatedData
      )
    } catch {
      throw BackgroundVotingShareOutboxStoreError.invalidCiphertext
    }
  }
}

enum BackgroundVotingShareOutboxKeyStore {
  private static let account = "master-key"

  /// Loads the 32-byte master key, creating it on first use. A keychain that
  /// is not yet readable (first wake after reboot, before first unlock)
  /// surfaces as `temporarilyUnavailable`, never as corruption.
  static func loadOrCreate() throws -> Data {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: votingShareOutboxKeyService,
      kSecAttrAccount: account,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data, data.count == 32 else {
        throw BackgroundVotingShareOutboxStoreError.invalidKey
      }
      return data
    case errSecInteractionNotAllowed:
      throw BackgroundVotingShareOutboxStoreError.temporarilyUnavailable
    case errSecItemNotFound:
      var key = Data(count: 32)
      let randomStatus = key.withUnsafeMutableBytes { bytes in
        SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
      }
      guard randomStatus == errSecSuccess else {
        throw BackgroundVotingShareOutboxStoreError.keychain(randomStatus)
      }
      let add: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: votingShareOutboxKeyService,
        kSecAttrAccount: account,
        kSecValueData: key,
        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        kSecAttrSynchronizable: false,
      ]
      let addStatus = SecItemAdd(add as CFDictionary, nil)
      if addStatus == errSecDuplicateItem { return try loadOrCreate() }
      guard addStatus == errSecSuccess else {
        throw BackgroundVotingShareOutboxStoreError.keychain(addStatus)
      }
      return key
    default:
      throw BackgroundVotingShareOutboxStoreError.keychain(status)
    }
  }
}

final class BackgroundVotingShareOutboxStore: @unchecked Sendable {
  static let shared = BackgroundVotingShareOutboxStore()

  private let queue = DispatchQueue(label: "com.keplr.vizor.voting-share-outbox")
  private let fileURL: URL
  private let keyProvider: () throws -> Data

  init(
    fileURL: URL? = nil,
    keyProvider: @escaping () throws -> Data = BackgroundVotingShareOutboxKeyStore
      .loadOrCreate
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
        .appendingPathComponent("VotingShares", isDirectory: true)
        .appendingPathComponent("background-share-outbox-v1.bin")
    }
    self.keyProvider = keyProvider
  }

  func read() throws -> BackgroundVotingShareOutboxSnapshot {
    try queue.sync { try readUnlocked() }
  }

  func update(
    _ mutation: (inout BackgroundVotingShareOutboxSnapshot) throws -> Void
  ) throws -> BackgroundVotingShareOutboxSnapshot {
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

  private func readUnlocked() throws -> BackgroundVotingShareOutboxSnapshot {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      return BackgroundVotingShareOutboxSnapshot()
    }
    let key = try keyProvider()
    let encrypted = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
    let plaintext = try BackgroundVotingShareOutboxCipher.open(encrypted, keyData: key)
    let snapshot = try JSONDecoder().decode(
      BackgroundVotingShareOutboxSnapshot.self,
      from: plaintext
    )
    guard snapshot.version == BackgroundVotingShareOutboxSnapshot.currentVersion else {
      throw BackgroundVotingShareOutboxStoreError.unsupportedVersion
    }
    return snapshot
  }

  private func writeUnlocked(_ snapshot: BackgroundVotingShareOutboxSnapshot) throws {
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
    let encrypted = try BackgroundVotingShareOutboxCipher.seal(
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
