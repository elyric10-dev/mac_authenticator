import Foundation
import LocalAuthentication

enum BiometricAuthError: Error, LocalizedError {
    case notAvailable
    case failed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication isn't available on this Mac."
        case .failed:
            return "Authentication failed. Try again."
        case .cancelled:
            return "Authentication was cancelled."
        }
    }
}

enum BiometricAuthService {

    static var biometryLabel: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "Unlock"
        }
        switch context.biometryType {
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Face ID"
        default:
            return "Biometric Unlock"
        }
    }

    static var systemImageName: String {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return "lock.shield"
        }
        switch context.biometryType {
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        default:
            return "lock.shield"
        }
    }

    /// Authenticate with Touch ID / Face ID when available, otherwise Mac login password.
    static func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password"
        context.localizedCancelTitle = "Cancel"

        let policy: LAPolicy
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
            policy = .deviceOwnerAuthenticationWithBiometrics
        } else if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            policy = .deviceOwnerAuthentication
        } else {
            throw BiometricAuthError.notAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                if let error = error as NSError? {
                    if error.code == LAError.userCancel.rawValue
                        || error.code == LAError.appCancel.rawValue
                        || error.code == LAError.systemCancel.rawValue {
                        continuation.resume(throwing: BiometricAuthError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                if success {
                    continuation.resume(returning: true)
                } else {
                    continuation.resume(throwing: BiometricAuthError.failed)
                }
            }
        }
    }
}
