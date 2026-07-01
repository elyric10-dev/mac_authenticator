import Foundation
import Combine

/// Central observable store: holds the list of accounts (metadata only —
/// secrets are fetched from Keychain on demand by the generator) and
/// persists that metadata list to disk.
///
/// Metadata (issuer, account name, algorithm, digits, period) is NOT
/// sensitive on its own — it's just labels. It's stored as plain JSON in
/// Application Support. Only the secret itself goes through Keychain.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [OTPAccount] = []
    @Published var lastError: String?

    private let storageURL: URL
    /// Secrets are loaded from Keychain once and kept in memory so the UI
    /// timer does not trigger a Keychain lookup every second (which can cause
    /// repeated macOS password prompts).
    private var secretCache: [UUID: Data] = [:]

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        let appDir = appSupport.appendingPathComponent("MacAuthenticator", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.storageURL = appDir.appendingPathComponent("accounts.json")
        load()
    }

    // MARK: - Adding accounts

    /// Add a single parsed entry (from a standard otpauth:// URI or manual entry).
    func addAccount(from entry: ParsedOTPEntry) {
        let account = OTPAccount(
            issuer: entry.issuer,
            accountName: entry.accountName,
            algorithm: entry.algorithm,
            digits: entry.digits,
            period: entry.period
        )

        do {
            try SecretStorage.save(secret: entry.secret, for: account.id)
            secretCache[account.id] = entry.secret
            accounts.append(account)
            persist()
        } catch {
            lastError = "Couldn't save \(account.displayLabel): \(error.localizedDescription)"
        }
    }

    /// Add multiple entries at once (from a Google migration export QR).
    /// Returns the count successfully added so the UI can report it.
    @discardableResult
    func addAccounts(from entries: [ParsedOTPEntry]) -> Int {
        var successCount = 0
        for entry in entries {
            let countBefore = accounts.count
            addAccount(from: entry)
            if accounts.count > countBefore {
                successCount += 1
            }
        }
        return successCount
    }

    // MARK: - Removing accounts

    func removeAccount(_ account: OTPAccount) {
        try? SecretStorage.delete(for: account.id)
        secretCache.removeValue(forKey: account.id)
        accounts.removeAll { $0.id == account.id }
        persist()
    }

    // MARK: - Code generation

    /// Generate the current code for an account. Returns nil if the secret
    /// can't be loaded from Keychain (shouldn't normally happen).
    /// Whether the secret for this account could be loaded.
    func hasSecret(for account: OTPAccount) -> Bool {
        secret(for: account.id) != nil
    }

    var accountsMissingSecrets: Int {
        accounts.filter { secret(for: $0.id) == nil }.count
    }

    func currentCode(for account: OTPAccount, at date: Date = Date()) -> String? {
        guard let secret = secret(for: account.id) else {
            return nil
        }
        return TOTPGenerator.generateCode(
            secret: secret,
            algorithm: account.algorithm,
            digits: account.digits,
            period: account.period,
            date: date
        )
    }

    // MARK: - Persistence (metadata only)

    private func persist() {
        do {
            let data = try JSONEncoder().encode(accounts)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            lastError = "Couldn't save account list: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            accounts = try JSONDecoder().decode([OTPAccount].self, from: data)
            warmSecretCache()
        } catch {
            lastError = "Couldn't load saved accounts: \(error.localizedDescription)"
        }
    }

    private func warmSecretCache() {
        secretCache.removeAll(keepingCapacity: true)
        var missingCount = 0

        for account in accounts {
            if let secret = secret(for: account.id) {
                secretCache[account.id] = secret
            } else {
                missingCount += 1
            }
        }

        if missingCount > 0 {
            lastError = missingCount == 1
                ? "1 account is missing its secret. Re-import that account."
                : "\(missingCount) accounts are missing secrets. Re-import those accounts."
        }
    }

    func exportSecret(for account: OTPAccount) -> Data? {
        secret(for: account.id)
    }

    func exportQR(for account: OTPAccount) throws {
        guard let secret = secret(for: account.id) else {
            throw AccountExportError.missingSecret
        }
        try AccountExporter.exportQRImage(for: account, secret: secret)
    }

    func exportAllAsMigrationQR() throws {
        try AccountExporter.exportAllAccountsMigration(accounts: accounts, secrets: exportableSecrets())
    }

    func exportAllAsIndividualQRImages() throws {
        try AccountExporter.exportAllAccountsIndividually(accounts: accounts, secrets: exportableSecrets())
    }

    private func exportableSecrets() -> [UUID: Data] {
        var result: [UUID: Data] = [:]
        for account in accounts {
            if let secret = secret(for: account.id) {
                result[account.id] = secret
            }
        }
        return result
    }

    private func secret(for accountID: UUID) -> Data? {
        if let cached = secretCache[accountID] {
            return cached
        }

        guard let loaded = try? SecretStorage.load(for: accountID) else {
            return nil
        }

        secretCache[accountID] = loaded
        return loaded
    }
}
