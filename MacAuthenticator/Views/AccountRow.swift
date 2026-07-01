import SwiftUI

struct AccountRow: View {
    @EnvironmentObject var store: AccountStore
    @EnvironmentObject var clock: TickingClock

    let account: OTPAccount
    var onDelete: () -> Void

    @State private var justCopied = false
    @State private var isHovered = false

    private var code: String {
        guard store.hasSecret(for: account) else { return "missing" }
        return store.currentCode(for: account, at: clock.now) ?? "------"
    }

    private var formattedCode: String {
        if code == "missing" { return "Re-import" }
        guard code.count == 6 else { return code }
        let mid = code.index(code.startIndex, offsetBy: 3)
        return "\(code[code.startIndex..<mid]) \(code[mid...])"
    }

    private var secondsRemaining: Int {
        TOTPGenerator.secondsRemaining(period: account.period, date: clock.now)
    }

    private var progress: Double {
        TOTPGenerator.progress(period: account.period, date: clock.now)
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(AppTheme.accent.opacity(0.85))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !account.displaySubtitle.isEmpty {
                    Text(account.displaySubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(justCopied ? "Copied!" : formattedCode)
                    .font(.system(size: code == "missing" ? 11 : 15, weight: .bold, design: code == "missing" ? .default : .monospaced))
                    .foregroundStyle(code == "missing" ? .orange : (justCopied ? AppTheme.accentDeep : .primary))
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                HStack(spacing: 6) {
                    Text("\(secondsRemaining)s")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(secondsRemaining <= 5 ? .red : .secondary)
                    CountdownRing(progress: progress, isUrgent: secondsRemaining <= 5)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? AppTheme.accent.opacity(0.08) : AppTheme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(isHovered ? 0.1 : 0.05), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { copyCode() }
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy Code") { copyCode() }
            if store.hasSecret(for: account) {
                Button("Export QR Image…") { exportQR() }
            }
            Button("Remove Account", role: .destructive) { onDelete() }
        }
    }

    private func copyCode() {
        guard store.hasSecret(for: account),
              let code = store.currentCode(for: account, at: clock.now) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)

        withAnimation(.easeInOut(duration: 0.2)) {
            justCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                justCopied = false
            }
        }
    }

    private func exportQR() {
        do {
            try store.exportQR(for: account)
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
