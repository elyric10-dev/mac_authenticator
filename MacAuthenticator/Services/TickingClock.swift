import Foundation
import Combine

/// A single shared "now" published once per second, so every account row
/// in the list updates in lockstep rather than each row running its own
/// independent timer (wasteful, and they'd drift visually out of sync).
@MainActor
final class TickingClock: ObservableObject {
    @Published private(set) var now: Date = Date()

    private var timer: Timer?
    private var isPaused = false

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isPaused else { return }
                self.now = Date()
            }
        }
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        if !paused {
            now = Date()
        }
    }

    deinit {
        timer?.invalidate()
    }
}
