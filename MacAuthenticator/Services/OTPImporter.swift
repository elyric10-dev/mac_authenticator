import AppKit
import Foundation

enum ImportResult {
    case singleAccount(ParsedOTPEntry)
    case multipleAccounts([ParsedOTPEntry])
}

enum ImportError: Error, LocalizedError {
    case unrecognizedFormat
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .unrecognizedFormat:
            return "That doesn't look like a 2FA QR code or setup link (expected otpauth:// or otpauth-migration://)."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Single entry point for turning "some text we got from a QR code or
/// pasted by the user" into one or more ready-to-store accounts.
/// Auto-detects whether it's a standard per-service QR or a Google
/// multi-account migration export.
enum OTPImporter {

    static func importFrom(text: String) throws -> ImportResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("otpauth-migration://") {
            do {
                let entries = try GoogleMigrationParser.parse(trimmed)
                return .multipleAccounts(entries)
            } catch {
                throw ImportError.underlying(error)
            }
        }

        if trimmed.hasPrefix("otpauth://") {
            do {
                let entry = try OTPAuthURIParser.parse(trimmed)
                return .singleAccount(entry)
            } catch {
                throw ImportError.underlying(error)
            }
        }

        // Allow pasting a raw Base32 secret with no URI wrapper at all —
        // common when a site shows you "can't scan? enter this code manually".
        if let secretData = Base32.decode(trimmed), trimmed.count >= 16 {
            let entry = ParsedOTPEntry(
                issuer: "",
                accountName: "Manual Entry",
                secret: secretData,
                algorithm: .sha1,
                digits: 6,
                period: 30
            )
            return .singleAccount(entry)
        }

        throw ImportError.unrecognizedFormat
    }

    /// Decode an image file, then attempt to import every QR payload found.
    static func importFrom(imageURL: URL) throws -> [ImportResult] {
        guard let nsImage = NSImage(contentsOf: imageURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImportError.underlying(QRDecodeError.imageLoadFailed)
        }
        return try importFrom(cgImage: cgImage)
    }

    /// Decode QR codes from raw image bytes (e.g. pasted from clipboard).
    static func importFrom(imageData: Data) throws -> [ImportResult] {
        guard let nsImage = NSImage(data: imageData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ImportError.underlying(QRDecodeError.imageLoadFailed)
        }
        return try importFrom(cgImage: cgImage)
    }

    static func importFrom(cgImage: CGImage) throws -> [ImportResult] {
        let payloads: [String]
        do {
            payloads = try QRImageDecoder.decodeQRCodes(from: cgImage)
        } catch {
            throw ImportError.underlying(error)
        }

        var results: [ImportResult] = []
        var firstError: Error?

        for payload in payloads {
            do {
                results.append(try importFrom(text: payload))
            } catch {
                if firstError == nil { firstError = error }
            }
        }

        if results.isEmpty, let firstError {
            throw firstError
        }

        return results
    }
}
