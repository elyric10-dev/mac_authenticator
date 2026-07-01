import AppKit
import Combine

/// Shared app-level actions used by the menu bar icon context menu and views.
@MainActor
final class AppController: ObservableObject {
    static weak var current: AppController?

    @Published var showingAddAccount = false
    @Published private(set) var isPanelOpen = false
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published var authError: String?

    init() {
        Self.current = self
    }

    func setPanelOpen(_ open: Bool) {
        isPanelOpen = open
    }

    func lock() {
        isUnlocked = false
        isAuthenticating = false
        authError = nil
        showingAddAccount = false
    }

    func authenticateIfNeeded() async {
        guard !isUnlocked, !isAuthenticating else { return }

        isAuthenticating = true
        authError = nil

        defer { isAuthenticating = false }

        do {
            let success = try await BiometricAuthService.authenticate(
                reason: "Unlock Authenticator to view your 2FA codes."
            )
            if success {
                isUnlocked = true
                authError = nil
            }
        } catch BiometricAuthError.cancelled {
            authError = "Authentication cancelled."
            closePanelIfOpen()
        } catch {
            authError = error.localizedDescription
        }
    }

    func returnToAccountList() {
        showingAddAccount = false
    }

    func openManage2FA() {
        returnToAccountList()
        NSApp.activate(ignoringOtherApps: true)

        if !isPanelOpen {
            StatusBarMenuController.openMenuBarPanel()
        }
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func closePanelIfOpen() {
        guard isPanelOpen else { return }
        StatusBarMenuController.closeMenuBarPanel()
    }
}
