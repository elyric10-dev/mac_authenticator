import Foundation

/// RFC 4648 Base32 encoding/decoding (no padding required on decode).
///
/// TOTP secrets are conventionally shared as Base32 strings (e.g.
/// "JBSWY3DPEHPK3PXP") because it's case-insensitive and avoids ambiguous
/// characters — easy to type by hand if needed. Foundation doesn't ship a
/// Base32 implementation, so this is a small standalone one.
enum Base32 {
    private static let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
    private static let charMap: [Character: UInt8] = {
        var map: [Character: UInt8] = [:]
        for (i, c) in alphabet.enumerated() {
            map[c] = UInt8(i)
        }
        return map
    }()

    /// Decode a Base32 string into raw bytes. Tolerant of lowercase input,
    /// padding characters ("="), and whitespace — all common in
    /// hand-typed or copy-pasted secrets.
    static func decode(_ input: String) -> Data? {
        let cleaned = input
            .uppercased()
            .replacingOccurrences(of: "=", with: "")
            .filter { !$0.isWhitespace }

        guard !cleaned.isEmpty else { return nil }

        var bits = 0
        var value: UInt32 = 0
        var output = Data()

        for char in cleaned {
            guard let charValue = charMap[char] else {
                // Invalid character for Base32 — bail rather than silently
                // producing a wrong secret, which would generate codes that
                // simply never match the server's.
                return nil
            }
            value = (value << 5) | UInt32(charValue)
            bits += 5

            if bits >= 8 {
                bits -= 8
                let byte = UInt8((value >> UInt32(bits)) & 0xff)
                output.append(byte)
            }
        }

        return output
    }

    /// Encode raw bytes into a Base32 string (no padding). Useful if you
    /// ever need to display/export a secret back out.
    static func encode(_ data: Data) -> String {
        var bits = 0
        var value: UInt32 = 0
        var output = ""

        for byte in data {
            value = (value << 8) | UInt32(byte)
            bits += 8

            while bits >= 5 {
                bits -= 5
                let index = Int((value >> UInt32(bits)) & 0x1f)
                output.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
            }
        }

        if bits > 0 {
            let index = Int((value << UInt32(5 - bits)) & 0x1f)
            output.append(alphabet[alphabet.index(alphabet.startIndex, offsetBy: index)])
        }

        return output
    }
}
