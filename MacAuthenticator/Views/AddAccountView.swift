import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AddAccountView: View {
    @EnvironmentObject var store: AccountStore
    @Binding var isPresented: Bool

    @State private var pastedText: String = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isDropTargeted = false
    @State private var pasteMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            addHeader

            VStack(spacing: 14) {
                dropZone

                HStack {
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                    Text("or paste manually")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Setup link, export, or secret key")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $pastedText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 72)
                        .padding(6)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25))
                        )

                    Button {
                        handleTextImport(pastedText)
                    } label: {
                        Label("Import Text", systemImage: "text.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentDeep)
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorMessage {
                    statusBanner(errorMessage, color: .red, icon: "exclamationmark.triangle.fill")
                }

                if let successMessage {
                    statusBanner(successMessage, color: .green, icon: "checkmark.circle.fill")
                }
            }
            .padding(16)

            HStack {
                Button("Back") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accentDeep)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))
        }
        .onPasteCommand(of: [.image, .png, .jpeg, .tiff]) { providers in
            handleImagePaste(providers: providers)
        }
        .onAppear { startPasteMonitor() }
        .onDisappear { stopPasteMonitor() }
    }

    private var addHeader: some View {
        HStack {
            Image(systemName: "person.badge.key.fill")
                .foregroundStyle(.white)
            Text("Add Account")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(AppTheme.headerGradient)
    }

    private func statusBanner(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .multilineTextAlignment(.leading)
        }
        .font(.caption)
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "qrcode.viewfinder")
                .font(.system(size: 30))
                .foregroundStyle(isDropTargeted ? AppTheme.accentDeep : .secondary)

            Text("Drop a QR image or press ⌘V / Ctrl+V")
                .font(.system(size: 12, weight: .medium))
                .multilineTextAlignment(.center)

            Button("Choose Image…") {
                presentFilePicker()
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDropTargeted ? AppTheme.accent.opacity(0.12) : AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isDropTargeted ? AppTheme.accent : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func presentFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            handleImageImport(url: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            DispatchQueue.main.async {
                handleImageImport(url: url)
            }
        }
        return true
    }

    private func handleImageImport(url: URL) {
        clearMessages()
        do {
            let results = try OTPImporter.importFrom(imageURL: url)
            applyResults(results)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handlePastedImage() {
        clearMessages()
        guard let cgImage = NSPasteboard.general.importableCGImage() else {
            errorMessage = "Clipboard doesn't contain an image."
            return
        }

        do {
            let results = try OTPImporter.importFrom(cgImage: cgImage)
            applyResults(results)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleImagePaste(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }

        let types = [UTType.image, .png, .jpeg, .tiff]
        guard let type = types.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            handlePastedImage()
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
            guard let data else {
                DispatchQueue.main.async { self.handlePastedImage() }
                return
            }
            DispatchQueue.main.async {
                self.clearMessages()
                do {
                    let results = try OTPImporter.importFrom(imageData: data)
                    self.applyResults(results)
                } catch {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func startPasteMonitor() {
        stopPasteMonitor()
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isPasteShortcut = event.modifierFlags.contains(.command)
                || event.modifierFlags.contains(.control)
            guard isPasteShortcut,
                  event.charactersIgnoringModifiers?.lowercased() == "v" else {
                return event
            }

            guard NSPasteboard.general.hasImportableImage else {
                return event
            }

            handlePastedImage()
            return nil
        }
    }

    private func stopPasteMonitor() {
        if let pasteMonitor {
            NSEvent.removeMonitor(pasteMonitor)
            self.pasteMonitor = nil
        }
    }

    private func handleTextImport(_ text: String) {
        clearMessages()
        do {
            let result = try OTPImporter.importFrom(text: text)
            applyResults([result])
            pastedText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyResults(_ results: [ImportResult]) {
        var totalAdded = 0
        for result in results {
            switch result {
            case .singleAccount(let entry):
                store.addAccount(from: entry)
                totalAdded += 1
            case .multipleAccounts(let entries):
                totalAdded += store.addAccounts(from: entries)
            }
        }

        if totalAdded > 0 {
            successMessage = totalAdded == 1
                ? "Account added."
                : "\(totalAdded) accounts added."
        } else {
            errorMessage = "No accounts could be imported."
        }
    }

    private func clearMessages() {
        errorMessage = nil
        successMessage = nil
    }
}
