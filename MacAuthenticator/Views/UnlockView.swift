import SwiftUI

struct UnlockView: View {
    @EnvironmentObject private var appController: AppController

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: BiometricAuthService.systemImageName)
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.accentDeep)
                .symbolRenderingMode(.hierarchical)

            Text("Unlock Authenticator")
                .font(.system(size: 15, weight: .semibold))

            Text("Use \(BiometricAuthService.biometryLabel) to view your codes.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if appController.isAuthenticating {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 4)
            } else {
                Button {
                    Task { await appController.authenticateIfNeeded() }
                } label: {
                    Label("Unlock with \(BiometricAuthService.biometryLabel)", systemImage: BiometricAuthService.systemImageName)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accentDeep)
                .padding(.top, 4)
            }

            if let authError = appController.authError {
                Text(authError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}
