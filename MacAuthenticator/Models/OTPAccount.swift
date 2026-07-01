import Foundation

/// Hash algorithm used for the HMAC step of TOTP generation.
enum OTPAlgorithm: String, Codable, CaseIterable {
    case sha1 = "SHA1"
    case sha256 = "SHA256"
    case sha512 = "SHA512"
}

/// A single TOTP account (e.g. "GitHub: you@email.com").
///
/// IMPORTANT: This struct itself never stores the secret. The secret lives
/// only in the Keychain, looked up by `id`. This means if this struct is ever
/// logged, archived, or serialized for UI state, the shared secret can't leak
/// along with it.
struct OTPAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var issuer: String
    var accountName: String
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
    var dateAdded: Date

    init(
        id: UUID = UUID(),
        issuer: String,
        accountName: String,
        algorithm: OTPAlgorithm = .sha1,
        digits: Int = 6,
        period: Int = 30,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.issuer = issuer
        self.accountName = accountName
        self.algorithm = algorithm
        self.digits = digits
        self.period = period
        self.dateAdded = dateAdded
    }

    /// Display label, e.g. "GitHub (you@email.com)" or just the account name
    /// if no issuer was provided.
    var displayLabel: String {
        if issuer.isEmpty {
            return accountName
        }
        if accountName.isEmpty {
            return issuer
        }
        return "\(issuer)"
    }

    var displaySubtitle: String {
        if issuer.isEmpty || accountName.isEmpty {
            return ""
        }
        return accountName
    }
}
