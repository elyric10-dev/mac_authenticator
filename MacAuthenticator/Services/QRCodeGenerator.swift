import AppKit
import CoreImage

enum QRCodeError: Error, LocalizedError {
    case generationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .generationFailed:
            return "Couldn't generate a QR code image."
        case .pngEncodingFailed:
            return "Couldn't save the QR code as a PNG file."
        }
    }
}

enum QRCodeGenerator {

    static func generateImage(from string: String, size: CGFloat = 512) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let output = filter.outputImage else { return nil }

        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    static func pngData(from image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw QRCodeError.pngEncodingFailed
        }
        return png
    }

    static func savePNG(image: NSImage, to url: URL) throws {
        let png = try pngData(from: image)
        try png.write(to: url, options: .atomic)
    }
}
