import AppKit

extension NSPasteboard {
    var hasImportableImage: Bool {
        if canReadObject(forClasses: [NSImage.self]) {
            return true
        }

        let types: [NSPasteboard.PasteboardType] = [.png, .tiff]
        return types.contains { availableType(from: [$0]) != nil }
    }

    func importableCGImage() -> CGImage? {
        if let images = readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            for image in images {
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    return cgImage
                }
            }
        }

        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            guard let data = data(forType: type),
                  let image = NSImage(data: data),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }
            return cgImage
        }

        return nil
    }
}
