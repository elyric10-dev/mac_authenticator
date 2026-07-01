import AppKit
import SwiftUI

struct HeaderToolbarButton: View {
    let systemImage: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(AppTheme.accentDeep)
                .frame(width: 24, height: 24)
                .background(Circle().fill(.white))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var appController: AppController
    @EnvironmentObject var clock: TickingClock
    @State private var showingExportOptions = false

    var body: some View {
        VStack(spacing: 0) {
            if !appController.isUnlocked {
                UnlockView()
            } else if appController.showingAddAccount {
                AddAccountView(isPresented: $appController.showingAddAccount)
            } else {
                accountList
            }
        }
        .frame(width: appController.showingAddAccount ? AppTheme.addPanelWidth : AppTheme.panelWidth)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .onAppear {
            clock.setPaused(appController.showingAddAccount)
            appController.setPanelOpen(true)
            Task { await appController.authenticateIfNeeded() }
        }
        .onDisappear {
            appController.setPanelOpen(false)
            appController.lock()
        }
        .onChange(of: appController.showingAddAccount) { showingAdd in
            clock.setPaused(showingAdd)
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            header

            if store.accounts.isEmpty {
                emptyState
            } else {
                if store.accountsMissingSecrets > 0 {
                    missingSecretsBanner
                }
                if let lastError = store.lastError {
                    errorBanner(lastError)
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.accounts) { account in
                            AccountRow(account: account) {
                                store.removeAccount(account)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 380)
            }

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Authenticator")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if !store.accounts.isEmpty {
                    HeaderToolbarButton(
                        systemImage: "square.and.arrow.up",
                        help: "Export accounts as QR images"
                    ) {
                        showingExportOptions = true
                    }
                    .popover(isPresented: $showingExportOptions, arrowEdge: .bottom) {
                        exportOptionsPopover
                    }
                }

                HeaderToolbarButton(systemImage: "plus", help: "Add account") {
                    appController.showingAddAccount = true
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.headerGradient)
    }

    private var exportOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Export Accounts")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))

            Divider()

            exportPopoverButton("All accounts as one QR…") {
                showingExportOptions = false
                exportAllMigration()
            }

            exportPopoverButton("Separate QR images in folder…") {
                showingExportOptions = false
                exportAllIndividual()
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func exportPopoverButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34))
                .foregroundStyle(AppTheme.accent)
                .symbolRenderingMode(.hierarchical)

            Text("No accounts yet")
                .font(.system(size: 15, weight: .semibold))

            Text("Import a QR code or paste a setup link\nto start generating codes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                appController.showingAddAccount = true
            } label: {
                Label("Add Account", systemImage: "plus.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accentDeep)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
    }

    private var missingSecretsBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Secrets missing — re-import accounts using your QR codes.")
                .font(.caption)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            Button {
                store.lastError = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
    }

    private var footer: some View {
        HStack {
            Image(systemName: "cursorarrow.click.2")
                .font(.caption2)
            Text("Right-click shield for menu")
                .font(.caption2)
        }
        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func exportAllMigration() {
        do {
            try store.exportAllAsMigrationQR()
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func exportAllIndividual() {
        do {
            try store.exportAllAsIndividualQRImages()
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
