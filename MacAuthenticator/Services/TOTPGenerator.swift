import Foundation
import CryptoKit

/// Implements TOTP (RFC 6238) on top of HOTP (RFC 4226).
///
/// This is the same algorithm Google Authenticator, Microsoft Authenticator,
/// Authy, and basically every other TOTP app implements. There's only one
/// standard here — that's *why* QR codes are interchangeable between apps.
enum TOTPGenerator {

    /// Generate the current TOTP code for a given secret + account config.
    /// - Parameters:
    ///   - secret: Raw secret bytes (already base32-decoded).
    ///   - algorithm: HMAC algorithm (Google/Microsoft default to SHA1).
    ///   - digits: Number of digits in the output code (usually 6, sometimes 8).
    ///   - period: Time step in seconds (almost always 30).
    ///   - date: The point in time to generate the code for (defaults to now).
    static func generateCode(
        secret: Data,
        algorithm: OTPAlgorithm,
        digits: Int,
        period: Int,
        date: Date = Date()
    ) -> String {
        let counter = UInt64(date.timeIntervalSince1970 / Double(period))
        return hotp(secret: secret, counter: counter, algorithm: algorithm, digits: digits)
    }

    /// Seconds remaining until the current code expires and a new one is generated.
    static func secondsRemaining(period: Int, date: Date = Date()) -> Int {
        let elapsed = Int(date.timeIntervalSince1970) % period
        return period - elapsed
    }

    /// Fractional progress (0.0 -> 1.0) through the current time step.
    /// Useful for drawing a countdown ring.
    static func progress(period: Int, date: Date = Date()) -> Double {
        let remaining = secondsRemaining(period: period, date: date)
        return Double(remaining) / Double(period)
    }

    // MARK: - HOTP core (RFC 4226)

    private static func hotp(
        secret: Data,
        counter: UInt64,
        algorithm: OTPAlgorithm,
        digits: Int
    ) -> String {
        var counterBytes = withUnsafeBytes(of: counter.bigEndian) { Data($0) }
        // Ensure exactly 8 bytes (UInt64 already gives us this, but be explicit).
        if counterBytes.count < 8 {
            counterBytes = Data(repeating: 0, count: 8 - counterBytes.count) + counterBytes
        }

        let hmac = computeHMAC(key: secret, message: counterBytes, algorithm: algorithm)

        // Dynamic truncation (RFC 4226 section 5.3).
        let offset = Int(hmac[hmac.count - 1] & 0x0f)
        let truncatedBytes = hmac[offset...offset+3]
        var truncatedValue: UInt32 = 0
        for byte in truncatedBytes {
            truncatedValue = (truncatedValue << 8) | UInt32(byte)
        }
        truncatedValue &= 0x7fffffff

        let modulus = UInt32(pow(10, Double(digits)))
        let code = truncatedValue % modulus

        return String(format: "%0\(digits)d", code)
    }

    private static func computeHMAC(key: Data, message: Data, algorithm: OTPAlgorithm) -> Data {
        switch algorithm {
        case .sha1:
            let mac = HMAC<Insecure.SHA1>.authenticationCode(
                for: message,
                using: SymmetricKey(data: key)
            )
            return Data(mac)
        case .sha256:
            let mac = HMAC<SHA256>.authenticationCode(
                for: message,
                using: SymmetricKey(data: key)
            )
            return Data(mac)
        case .sha512:
            let mac = HMAC<SHA512>.authenticationCode(
                for: message,
                using: SymmetricKey(data: key)
            )
            return Data(mac)
        }
    }
}
