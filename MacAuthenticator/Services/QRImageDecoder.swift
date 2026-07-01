import Foundation
import Vision
import AppKit

enum QRDecodeError: Error, LocalizedError {
    case noQRCodeFound
    case imageLoadFailed
    case visionRequestFailed(Error)

    var errorDescription: String? {
        switch self {
        case .noQRCodeFound:
            return "No QR code was found in that image."
        case .imageLoadFailed:
            return "Couldn't load that image file."
        case .visionRequestFailed(let error):
            return "QR scan failed: \(error.localizedDescription)"
        }
    }
}

/// Decodes QR codes from an image file using Apple's Vision framework —
/// no third-party barcode library needed.
enum QRImageDecoder {

    /// Decode all QR codes found in an image at the given file URL.
    /// Most QR images contain just one code, but this returns all of them
    /// in case a screenshot has multiple visible.
    static func decodeQRCodes(from imageURL: URL) throws -> [String] {
        guard let nsImage = NSImage(contentsOf: imageURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw QRDecodeError.imageLoadFailed
        }
        return try decodeQRCodes(from: cgImage)
    }

    static func decodeQRCodes(from cgImage: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            throw QRDecodeError.visionRequestFailed(error)
        }

        guard let results = request.results else {
            throw QRDecodeError.noQRCodeFound
        }

        let payloads = results.compactMap { $0.payloadStringValue }
        guard !payloads.isEmpty else {
            throw QRDecodeError.noQRCodeFound
        }

        return payloads
    }
}
