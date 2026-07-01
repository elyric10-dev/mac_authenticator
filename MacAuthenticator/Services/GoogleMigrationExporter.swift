import Foundation

enum GoogleMigrationExportError: Error, LocalizedError {
    case noAccounts

    var errorDescription: String? {
        switch self {
        case .noAccounts:
            return "No accounts are available to export."
        }
    }
}

/// Builds Google Authenticator migration export URIs (`otpauth-migration://`).
enum GoogleMigrationExporter {

    static func buildMigrationURI(entries: [ParsedOTPEntry]) throws -> String {
        guard !entries.isEmpty else {
            throw GoogleMigrationExportError.noAccounts
        }

        let payload = encodeMigrationPayload(entries: entries)
        let base64 = payload.base64EncodedString()
        let encoded = base64.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? base64
        return "otpauth-migration://offline?data=\(encoded)"
    }

    private static func encodeMigrationPayload(entries: [ParsedOTPEntry]) -> Data {
        var payload = Data()

        for entry in entries {
            payload.append(encodeOtpParameters(entry))
        }

        // version = 1
        payload.append(ProtobufWriter.encodeVarintField(number: 2, value: 1))
        // batch_size = account count
        payload.append(ProtobufWriter.encodeVarintField(number: 3, value: UInt64(entries.count)))
        // batch_index = 1
        payload.append(ProtobufWriter.encodeVarintField(number: 4, value: 1))
        // batch_id = random-ish stable id
        payload.append(ProtobufWriter.encodeVarintField(number: 5, value: UInt64(entries.count)))

        return payload
    }

    private static func encodeOtpParameters(_ entry: ParsedOTPEntry) -> Data {
        var message = Data()
        message.append(ProtobufWriter.encodeLengthDelimitedField(number: 1, data: entry.secret))
        message.append(ProtobufWriter.encodeStringField(number: 2, string: entry.accountName))
        message.append(ProtobufWriter.encodeStringField(number: 3, string: entry.issuer))

        let algorithmValue: UInt64 = switch entry.algorithm {
        case .sha1: 1
        case .sha256: 2
        case .sha512: 3
        }
        message.append(ProtobufWriter.encodeVarintField(number: 4, value: algorithmValue))

        let digitsValue: UInt64 = entry.digits == 8 ? 2 : 1
        message.append(ProtobufWriter.encodeVarintField(number: 5, value: digitsValue))

        // TOTP
        message.append(ProtobufWriter.encodeVarintField(number: 6, value: 2))

        return ProtobufWriter.encodeLengthDelimitedField(number: 1, data: message)
    }
}

private enum ProtobufWriter {
    static func encodeVarintField(number: Int, value: UInt64) -> Data {
        var data = encodeTag(fieldNumber: number, wireType: 0)
        data.append(encodeVarint(value))
        return data
    }

    static func encodeLengthDelimitedField(number: Int, data payload: Data) -> Data {
        var data = encodeTag(fieldNumber: number, wireType: 2)
        data.append(encodeVarint(UInt64(payload.count)))
        data.append(payload)
        return data
    }

    static func encodeStringField(number: Int, string: String) -> Data {
        encodeLengthDelimitedField(number: number, data: Data(string.utf8))
    }

    private static func encodeTag(fieldNumber: Int, wireType: Int) -> Data {
        encodeVarint(UInt64((fieldNumber << 3) | wireType))
    }

    private static func encodeVarint(_ value: UInt64) -> Data {
        var result = Data()
        var val = value
        repeat {
            var byte = UInt8(val & 0x7f)
            val >>= 7
            if val != 0 {
                byte |= 0x80
            }
            result.append(byte)
        } while val != 0
        return result
    }
}
