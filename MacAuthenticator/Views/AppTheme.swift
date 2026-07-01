import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.18, green: 0.72, blue: 0.78)
    static let accentDeep = Color(red: 0.10, green: 0.45, blue: 0.62)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let card = Color(nsColor: .windowBackgroundColor).opacity(0.72)

    static let headerGradient = LinearGradient(
        colors: [accentDeep, accent.opacity(0.85)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let panelWidth: CGFloat = 340
    static let addPanelWidth: CGFloat = 380
    static let cornerRadius: CGFloat = 12
}

struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AppTheme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

extension View {
    func panelCard() -> some View {
        modifier(PanelCard())
    }
}
