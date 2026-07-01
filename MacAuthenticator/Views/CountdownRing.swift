import SwiftUI

struct CountdownRing: View {
    let progress: Double
    let isUrgent: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    isUrgent ? Color.red : AppTheme.accent,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
        .frame(width: 16, height: 16)
    }
}
