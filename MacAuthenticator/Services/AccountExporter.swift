import AppKit
import UniformTypeIdentifiers

enum AccountExportError: Error, LocalizedError {
    case missingSecret
    case noExportableAccounts
    case imageGenerationFailed

    var errorDescription: String? {
        switch self {
        case .missingSecret:
            return "This account is missing its secret and can't be exported."
        case .noExportableAccounts:
            return "No accounts with secrets are available to export."
        case .imageGenerationFailed:
            return "Couldn't generate a QR code image."
        }
    }
}

@MainActor
enum AccountExporter {

    static func exportQRImage(for account: OTPAccount, secret: Data) throws {
        let uri = OTPAuthURIBuilder.buildURI(for: account, secret: secret)
        guard let image = QRCodeGenerator.generateImage(from: uri) else {
            throw AccountExportError.imageGenerationFailed
        }

        let panel = NSSavePanel()
        panel.title = "Export QR Code"
        panel.message = "Save a QR image for \(account.displayLabel)."
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(sanitizedFilename(account.displayLabel))-qr.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try QRCodeGenerator.savePNG(image: image, to: url)
    }

    static func exportAllAccountsMigration(accounts: [OTPAccount], secrets: [UUID: Data]) throws {
        let entries = exportableEntries(from: accounts, secrets: secrets)
        guard !entries.isEmpty else {
            throw AccountExportError.noExportableAccounts
        }

        let uri = try GoogleMigrationExporter.buildMigrationURI(entries: entries)
        guard let image = QRCodeGenerator.generateImage(from: uri, size: 640) else {
            throw AccountExportError.imageGenerationFailed
        }

        let panel = NSSavePanel()
        panel.title = "Export All Accounts"
        panel.message = "Save a Google Authenticator-style migration QR for \(entries.count) account(s)."
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "MacAuthenticator-export-\(entries.count)-accounts.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try QRCodeGenerator.savePNG(image: image, to: url)
    }

    static func exportAllAccountsIndividually(accounts: [OTPAccount], secrets: [UUID: Data]) throws {
        let exportable = accounts.filter { secrets[$0.id] != nil }
        guard !exportable.isEmpty else {
            throw AccountExportError.noExportableAccounts
        }

        let panel = NSOpenPanel()
        panel.title = "Choose Export Location"
        panel.message = "QR images will be saved inside a MacAuthenticator-QR-Export folder."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let parentFolder = panel.url else { return }

        let exportFolder = try uniqueExportFolder(in: parentFolder)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        var usedNames = Set<String>()
        for account in exportable {
            guard let secret = secrets[account.id] else { continue }
            let uri = OTPAuthURIBuilder.buildURI(for: account, secret: secret)
            guard let image = QRCodeGenerator.generateImage(from: uri) else { continue }

            let filename = uniqueFilename(
                base: "\(sanitizedFilename(account.displayLabel))-qr.png",
                usedNames: &usedNames
            )
            let url = exportFolder.appendingPathComponent(filename)
            try QRCodeGenerator.savePNG(image: image, to: url)
        }

        NSWorkspace.shared.activateFileViewerSelecting([exportFolder])
    }

    private static func uniqueExportFolder(in parentFolder: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let timestamp = formatter.string(from: Date())
        let baseName = "MacAuthenticator-QR-Export-\(timestamp)"
        var candidate = parentFolder.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentFolder.appendingPathComponent("\(baseName)-\(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private static func uniqueFilename(base: String, usedNames: inout Set<String>) -> String {
        guard usedNames.contains(base) else {
            usedNames.insert(base)
            return base
        }

        let stem = base.hasSuffix(".png")
            ? String(base.dropLast(4))
            : base
        var suffix = 2
        var candidate = "\(stem)-\(suffix).png"

        while usedNames.contains(candidate) {
            suffix += 1
            candidate = "\(stem)-\(suffix).png"
        }

        usedNames.insert(candidate)
        return candidate
    }

    private static func exportableEntries(from accounts: [OTPAccount], secrets: [UUID: Data]) -> [ParsedOTPEntry] {
        accounts.compactMap { account in
            guard let secret = secrets[account.id] else { return nil }
            return ParsedOTPEntry(
                issuer: account.issuer,
                accountName: account.accountName,
                secret: secret,
                algorithm: account.algorithm,
                digits: account.digits,
                period: account.period
            )
        }
    }

    private static func sanitizedFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
            .ifEmpty(default: "account")
    }
}

private extension String {
    func ifEmpty(default defaultValue: String) -> String {
        isEmpty ? defaultValue : self
    }
}
