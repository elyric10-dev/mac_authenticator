import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)
    case dataConversionFailed
    case backupNotFound

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String?
            return "Keychain error (\(status)): \(message ?? "unknown")"
        case .dataConversionFailed:
            return "Failed to convert secret data."
        case .backupNotFound:
            return "Secret not found in Keychain or local backup."
        }
    }
}

/// Persists TOTP secrets in Keychain with a local backup.
///
/// Ad-hoc / rebuilt app bundles can lose Keychain access to items saved by a
/// previous signature. The Application Support backup keeps codes working
/// across reinstalls on the same Mac.
enum SecretStorage {
    private static let service = "com.macauthenticator.totp-secrets"

    private static var backupDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("MacAuthenticator", isDirectory: true)
            .appendingPathComponent("secrets", isDirectory: true)
    }

    static func save(secret: Data, for accountID: UUID) throws {
        try? delete(for: accountID)
        try saveBackup(secret: secret, for: accountID)

        // Keychain is best-effort; backup is the reliable store across rebuilds.
        try? saveToKeychain(secret: secret, for: accountID)
    }

    static func load(for accountID: UUID) throws -> Data {
        if let keychainSecret = try? loadFromKeychain(for: accountID) {
            try? saveBackup(secret: keychainSecret, for: accountID)
            return keychainSecret
        }

        if let backupSecret = try? loadBackup(for: accountID) {
            try? saveToKeychain(secret: backupSecret, for: accountID)
            return backupSecret
        }

        throw KeychainError.backupNotFound
    }

    static func delete(for accountID: UUID) throws {
        try? deleteFromKeychain(for: accountID)
        try? deleteBackup(for: accountID)
    }

    // MARK: - Keychain

    private static func saveToKeychain(secret: Data, for accountID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecValueData as String: secret,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func loadFromKeychain(for accountID: UUID) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = result as? Data else {
            throw KeychainError.dataConversionFailed
        }

        return data
    }

    private static func deleteFromKeychain(for accountID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.uuidString
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Local backup

    private static func backupURL(for accountID: UUID) -> URL {
        backupDirectory.appendingPathComponent(accountID.uuidString + ".secret")
    }

    private static func saveBackup(secret: Data, for accountID: UUID) throws {
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let url = backupURL(for: accountID)
        try secret.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    private static func loadBackup(for accountID: UUID) throws -> Data {
        let url = backupURL(for: accountID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw KeychainError.backupNotFound
        }
        return try Data(contentsOf: url)
    }

    private static func deleteBackup(for accountID: UUID) throws {
        let url = backupURL(for: accountID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
