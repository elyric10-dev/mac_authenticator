import Foundation

/// Result of parsing a single otpauth:// URI: the account metadata plus
/// its raw decoded secret. Kept together only transiently — the caller is
/// responsible for immediately storing `secret` in the Keychain and
/// discarding this struct.
struct ParsedOTPEntry {
    var issuer: String
    var accountName: String
    var secret: Data
    var algorithm: OTPAlgorithm
    var digits: Int
    var period: Int
}

enum OTPAuthURIParseError: Error, LocalizedError {
    case notAnOTPAuthURI
    case missingSecret
    case invalidSecret
    case unsupportedType

    var errorDescription: String? {
        switch self {
        case .notAnOTPAuthURI:
            return "This doesn't look like a valid otpauth:// QR code or link."
        case .missingSecret:
            return "The QR code is missing its secret key."
        case .invalidSecret:
            return "The secret key isn't valid Base32 — it may be corrupted."
        case .unsupportedType:
            return "Only TOTP (time-based) codes are supported, not HOTP (counter-based)."
        }
    }
}

/// Parses standard `otpauth://totp/...` URIs — the format used when a
/// website shows you a single QR code to set up 2FA (GitHub, Google,
/// AWS, etc. all use this exact format under the hood).
enum OTPAuthURIParser {

    static func parse(_ uriString: String) throws -> ParsedOTPEntry {
        guard let components = URLComponents(string: uriString),
              components.scheme == "otpauth" else {
            throw OTPAuthURIParseError.notAnOTPAuthURI
        }

        // host is "totp" or "hotp"
        guard components.host?.lowercased() == "totp" else {
            throw OTPAuthURIParseError.unsupportedType
        }

        // Path is "/Issuer:accountname" or "/accountname"
        let label = components.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .removingPercentEncoding ?? ""

        var issuer = ""
        var accountName = label

        if let colonRange = label.range(of: ":") {
            issuer = String(label[label.startIndex..<colonRange.lowerBound])
            accountName = String(label[colonRange.upperBound...])
        }

        var secretBase32: String?
        var algorithm: OTPAlgorithm = .sha1
        var digits = 6
        var period = 30

        if let items = components.queryItems {
            for item in items {
                switch item.name.lowercased() {
                case "secret":
                    secretBase32 = item.value
                case "issuer":
                    // Query param issuer takes precedence over label issuer
                    // if present, per Google's spec.
                    if let value = item.value, !value.isEmpty {
                        issuer = value
                    }
                case "algorithm":
                    if let value = item.value?.uppercased(),
                       let parsed = OTPAlgorithm(rawValue: value) {
                        algorithm = parsed
                    }
                case "digits":
                    if let value = item.value, let parsed = Int(value) {
                        digits = parsed
                    }
                case "period":
                    if let value = item.value, let parsed = Int(value) {
                        period = parsed
                    }
                default:
                    break
                }
            }
        }

        guard let secretBase32, !secretBase32.isEmpty else {
            throw OTPAuthURIParseError.missingSecret
        }

        guard let secretData = Base32.decode(secretBase32) else {
            throw OTPAuthURIParseError.invalidSecret
        }

        return ParsedOTPEntry(
            issuer: issuer,
            accountName: accountName,
            secret: secretData,
            algorithm: algorithm,
            digits: digits,
            period: period
        )
    }
}
