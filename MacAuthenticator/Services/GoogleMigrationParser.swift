import Foundation

/// Parses Google Authenticator's "Export accounts" QR code format:
/// `otpauth-migration://offline?data=<base64>`
///
/// Unlike the standard otpauth:// URI, this packs *multiple* accounts into
/// one QR using a Protobuf-encoded payload. Google has never published a
/// formal .proto schema for this, but it's been reverse-engineered and is
/// stable/well-documented across the community. The schema is small enough
/// that a minimal hand-rolled Protobuf wire-format decoder is simpler and
/// more auditable than pulling in a full Protobuf runtime dependency.
///
/// Wire schema (field numbers as observed in the actual export payload):
///   message MigrationPayload {
///     message OtpParameters {
///       bytes secret = 1;
///       string name = 2;       // accountName
///       string issuer = 3;
///       Algorithm algorithm = 4;
///       DigitCount digit_count = 5;
///       OtpType type = 6;
///     }
///     repeated OtpParameters otp_parameters = 1;
///     int32 version = 2;
///     int32 batch_size = 3;
///     int32 batch_index = 4;
///     int32 batch_id = 5;
///   }
enum GoogleMigrationParseError: Error, LocalizedError {
    case notAMigrationURI
    case missingData
    case invalidBase64
    case malformedProtobuf
    case noAccountsFound

    var errorDescription: String? {
        switch self {
        case .notAMigrationURI:
            return "This doesn't look like a Google Authenticator export QR code."
        case .missingData:
            return "The export QR is missing its data payload."
        case .invalidBase64:
            return "The export data isn't valid — it may be corrupted or cropped."
        case .malformedProtobuf:
            return "Couldn't parse the export data. The QR may be from a newer/different export format."
        case .noAccountsFound:
            return "No accounts were found in this export QR."
        }
    }
}

enum GoogleMigrationParser {

    static func parse(_ uriString: String) throws -> [ParsedOTPEntry] {
        guard let components = URLComponents(string: uriString),
              components.scheme == "otpauth-migration" else {
            throw GoogleMigrationParseError.notAMigrationURI
        }

        guard let dataParam = components.queryItems?.first(where: { $0.name == "data" })?.value else {
            throw GoogleMigrationParseError.missingData
        }

        // The data param is URL-safe-ish base64, sometimes with spaces where
        // '+' should be (from URL decoding quirks), so normalize before decoding.
        let normalized = dataParam
            .replacingOccurrences(of: " ", with: "+")

        guard let payload = Data(base64Encoded: padBase64(normalized)) else {
            throw GoogleMigrationParseError.invalidBase64
        }

        let entries = try parseMigrationPayload(payload)
        guard !entries.isEmpty else {
            throw GoogleMigrationParseError.noAccountsFound
        }
        return entries
    }

    private static func padBase64(_ string: String) -> String {
        let remainder = string.count % 4
        if remainder == 0 { return string }
        return string + String(repeating: "=", count: 4 - remainder)
    }

    // MARK: - Minimal Protobuf wire-format decoder

    private static func parseMigrationPayload(_ data: Data) throws -> [ParsedOTPEntry] {
        var reader = ProtobufReader(data: data)
        var entries: [ParsedOTPEntry] = []

        while let field = try reader.nextField() {
            // Field 1 = repeated OtpParameters (length-delimited submessage)
            if field.number == 1, case .lengthDelimited(let subData) = field.value {
                if let entry = try? parseOtpParameters(subData) {
                    entries.append(entry)
                }
            }
            // Other top-level fields (version, batch_size, etc.) are ignored —
            // they're metadata about the export batch, not needed to import.
        }

        return entries
    }

    private static func parseOtpParameters(_ data: Data) throws -> ParsedOTPEntry {
        var reader = ProtobufReader(data: data)

        var secret: Data?
        var name = ""
        var issuer = ""
        var algorithm: OTPAlgorithm = .sha1
        var digits = 6

        while let field = try reader.nextField() {
            switch (field.number, field.value) {
            case (1, .lengthDelimited(let bytes)):
                secret = bytes
            case (2, .lengthDelimited(let bytes)):
                name = String(data: bytes, encoding: .utf8) ?? ""
            case (3, .lengthDelimited(let bytes)):
                issuer = String(data: bytes, encoding: .utf8) ?? ""
            case (4, .varint(let value)):
                // Algorithm enum: 0=unspecified,1=SHA1,2=SHA256,3=SHA512,4=MD5
                switch value {
                case 2: algorithm = .sha256
                case 3: algorithm = .sha512
                default: algorithm = .sha1
                }
            case (5, .varint(let value)):
                // DigitCount enum: 0=unspecified,1=SIX,2=EIGHT
                digits = (value == 2) ? 8 : 6
            default:
                break
            }
        }

        guard let secret else {
            throw GoogleMigrationParseError.malformedProtobuf
        }

        return ParsedOTPEntry(
            issuer: issuer,
            accountName: name,
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            period: 30 // Google's migration format doesn't carry a period; TOTP default applies.
        )
    }
}

// MARK: - Tiny generic Protobuf wire-format reader

/// A minimal Protobuf wire-format reader supporting only what we need:
/// varints and length-delimited fields (wire types 0 and 2). This covers
/// the entire migration payload schema above. We deliberately do NOT
/// implement fixed32/fixed64 (wire types 1 and 5) since they don't appear
/// in this schema — if encountered, they're skipped safely.
private struct ProtobufField {
    enum Value {
        case varint(UInt64)
        case lengthDelimited(Data)
    }
    let number: Int
    let value: Value
}

private struct ProtobufReader {
    let data: Data
    var offset: Int = 0

    init(data: Data) {
        self.data = data
    }

    var isAtEnd: Bool { offset >= data.count }

    mutating func nextField() throws -> ProtobufField? {
        if isAtEnd { return nil }

        let tag = try readVarint()
        let fieldNumber = Int(tag >> 3)
        let wireType = Int(tag & 0x07)

        switch wireType {
        case 0: // varint
            let value = try readVarint()
            return ProtobufField(number: fieldNumber, value: .varint(value))
        case 2: // length-delimited
            let length = try readVarint()
            let len = Int(length)
            guard offset + len <= data.count else {
                throw GoogleMigrationParseError.malformedProtobuf
            }
            let sub = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + len))
            offset += len
            return ProtobufField(number: fieldNumber, value: .lengthDelimited(sub))
        case 1: // fixed64 — skip 8 bytes
            offset += 8
            return try nextField()
        case 5: // fixed32 — skip 4 bytes
            offset += 4
            return try nextField()
        default:
            throw GoogleMigrationParseError.malformedProtobuf
        }
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while true {
            guard !isAtEnd else { throw GoogleMigrationParseError.malformedProtobuf }
            let byte = data[data.startIndex + offset]
            offset += 1
            result |= UInt64(byte & 0x7f) << shift
            if (byte & 0x80) == 0 {
                break
            }
            shift += 7
            if shift > 63 { throw GoogleMigrationParseError.malformedProtobuf }
        }

        return result
    }
}
