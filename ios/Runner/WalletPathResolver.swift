import Foundation
import Security

private let walletDbNameKey = "zcash_wallet_db_name"
private let secureStoreService = "com.keplr.vizor.secure_store"
private let biometricUnlockService = "com.zcash.wallet.biometric-unlock"
private let installSentinelKey = "vizor_install_sentinel_v1"
private let cleanupPendingKey = "vizor_keychain_cleanup_pending_v1"

enum WalletPathResolverError: Error {
    case dbNameMissing
    case invalidDbNameData
    case keychainStatus(OSStatus)
}

func resolveWalletDbPath() throws -> String {
    let supportDir = try resolveWalletSupportDirectory()
    let dbName = try resolveWalletDbName()
    return supportDir.appendingPathComponent(dbName).path
}

func resolveWalletSupportDirectory() throws -> URL {
    let supportDir = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    try FileManager.default.createDirectory(
        at: supportDir,
        withIntermediateDirectories: true
    )
    return supportDir
}

private func resolveWalletDbName() throws -> String {
    let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrAccount: walletDbNameKey,
        kSecAttrService: secureStoreService,
        kSecReturnData: true,
        kSecMatchLimit: kSecMatchLimitOne,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
        guard let data = item as? Data else {
            throw WalletPathResolverError.invalidDbNameData
        }
        guard let dbName = String(data: data, encoding: .utf8), !dbName.isEmpty else {
            throw WalletPathResolverError.invalidDbNameData
        }
        return dbName
    case errSecItemNotFound:
        throw WalletPathResolverError.dbNameMissing
    default:
        throw WalletPathResolverError.keychainStatus(status)
    }
}

enum KeychainDbNameLookup: Equatable {
    case found(String)
    case missing
    case invalid
    case failed(OSStatus)
}

enum FreshInstallKeychainCleanupDecision: Equatable {
    case sentinelPresent
    case markInstalled
    case preserveExistingInstall
    case clearStaleKeychain
    case deferCleanupAfterReadFailure(OSStatus)
    case deferCleanupAfterInvalidWalletDbName
}

struct FreshInstallKeychainCleaner {
    struct Dependencies {
        var hasInstallSentinel: () -> Bool
        var markInstallSentinel: () -> Void
        var hasCleanupPending: () -> Bool
        var markCleanupPending: () -> Void
        var clearCleanupPending: () -> Void
        var readWalletDbName: () -> KeychainDbNameLookup
        var walletDbExists: (String) -> Bool
        var deleteKeychainService: (String) -> OSStatus
        var log: (String) -> Void

        static let live = Dependencies(
            hasInstallSentinel: {
                UserDefaults.standard.bool(forKey: installSentinelKey)
            },
            markInstallSentinel: {
                UserDefaults.standard.set(true, forKey: installSentinelKey)
            },
            hasCleanupPending: {
                UserDefaults.standard.bool(forKey: cleanupPendingKey)
            },
            markCleanupPending: {
                UserDefaults.standard.set(true, forKey: cleanupPendingKey)
            },
            clearCleanupPending: {
                UserDefaults.standard.removeObject(forKey: cleanupPendingKey)
            },
            readWalletDbName: {
                FreshInstallKeychainCleaner.readWalletDbNameFromKeychain()
            },
            walletDbExists: { dbName in
                FreshInstallKeychainCleaner.walletDbExists(dbName)
            },
            deleteKeychainService: { service in
                FreshInstallKeychainCleaner.deleteGenericPasswordService(service)
            },
            log: { message in
                NSLog("[zcash] %@", message)
            }
        )
    }

    static let servicesToClear = [
        biometricUnlockService,
        ironwoodMigrationBackgroundCredentialService,
        // Keep this last: it holds zcash_wallet_db_name, the stale-install anchor.
        secureStoreService,
    ]

    static func runIfNeeded(dependencies: Dependencies = .live) {
        if dependencies.hasInstallSentinel() {
            return
        }

        let cleanupPending = dependencies.hasCleanupPending()
        switch cleanupDecision(dependencies: dependencies) {
        case .sentinelPresent:
            return
        case .markInstalled:
            dependencies.clearCleanupPending()
            dependencies.markInstallSentinel()
        case .preserveExistingInstall:
            dependencies.clearCleanupPending()
            dependencies.markInstallSentinel()
        case .clearStaleKeychain:
            if !cleanupPending {
                dependencies.markCleanupPending()
            }
            clearStaleKeychain(dependencies: dependencies)
        case .deferCleanupAfterReadFailure(let status):
            dependencies.log("fresh install: deferred keychain cleanup after read status \(status)")
        case .deferCleanupAfterInvalidWalletDbName:
            dependencies.log("fresh install: deferred keychain cleanup after invalid wallet DB name")
        }
    }

    static func cleanupDecision(
        dependencies: Dependencies = .live
    ) -> FreshInstallKeychainCleanupDecision {
        if dependencies.hasInstallSentinel() {
            return .sentinelPresent
        }

        switch dependencies.readWalletDbName() {
        case .missing:
            return .markInstalled
        case .invalid:
            return .deferCleanupAfterInvalidWalletDbName
        case .failed(let status):
            return .deferCleanupAfterReadFailure(status)
        case .found(let dbName):
            // Existing users from before this install sentinel existed can have a
            // Keychain wallet DB name without the sentinel. If the app-private DB
            // still exists, preserve their Keychain values and write the sentinel.
            return dependencies.walletDbExists(dbName)
                ? .preserveExistingInstall
                : .clearStaleKeychain
        }
    }

    private static func clearStaleKeychain(dependencies: Dependencies) {
        var nonAnchorFailure: OSStatus?
        var anchorStatus: OSStatus?

        for service in servicesToClear {
            let status = dependencies.deleteKeychainService(service)
            if service == secureStoreService {
                anchorStatus = status
            } else if !isKeychainDeleteSuccess(status), nonAnchorFailure == nil {
                nonAnchorFailure = status
            }
        }

        guard let anchorStatus else {
            dependencies.log("fresh install: deferred keychain cleanup; secure store was not attempted")
            return
        }

        guard isKeychainDeleteSuccess(anchorStatus) else {
            dependencies.log("fresh install: deferred keychain cleanup after delete status \(anchorStatus)")
            return
        }

        dependencies.clearCleanupPending()
        dependencies.markInstallSentinel()
        if let nonAnchorFailure {
            dependencies.log(
                "fresh install: cleared stale iOS secure storage; "
                    + "non-anchor keychain cleanup failed with status \(nonAnchorFailure)"
            )
        } else {
            dependencies.log("fresh install: cleared stale iOS keychain values")
        }
    }

    private static func readWalletDbNameFromKeychain() -> KeychainDbNameLookup {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: walletDbNameKey,
            kSecAttrService: secureStoreService,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                return .invalid
            }
            guard let dbName = String(data: data, encoding: .utf8), isSafeDbName(dbName) else {
                return .invalid
            }
            return .found(dbName)
        case errSecItemNotFound:
            return .missing
        default:
            return .failed(status)
        }
    }

    private static func walletDbExists(_ dbName: String) -> Bool {
        guard isSafeDbName(dbName) else {
            return true
        }
        guard let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return false
        }
        let dbUrl = supportDir.appendingPathComponent(dbName, isDirectory: false)
        return FileManager.default.fileExists(atPath: dbUrl.path)
    }

    private static func isSafeDbName(_ dbName: String) -> Bool {
        if dbName.isEmpty {
            return false
        }
        return (dbName as NSString).lastPathComponent == dbName
    }

    private static func isKeychainDeleteSuccess(_ status: OSStatus) -> Bool {
        status == errSecSuccess || status == errSecItemNotFound
    }

    private static func deleteGenericPasswordService(_ service: String) -> OSStatus {
        let statuses = [kCFBooleanTrue, kCFBooleanFalse].map { synchronizable in
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrSynchronizable: synchronizable as Any,
            ]
            return SecItemDelete(query as CFDictionary)
        }

        if statuses.contains(errSecSuccess) {
            return errSecSuccess
        }
        if statuses.allSatisfy({ $0 == errSecItemNotFound }) {
            return errSecSuccess
        }
        return statuses.first { $0 != errSecItemNotFound } ?? errSecSuccess
    }
}
