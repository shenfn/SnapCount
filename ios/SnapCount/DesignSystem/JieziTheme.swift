import SwiftUI

enum JieziTheme {
    static let pageBackground = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.98, blue: 0.95),
            Color(red: 0.92, green: 0.97, blue: 0.95),
            Color(red: 0.96, green: 0.94, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let ink = Color(red: 0.10, green: 0.12, blue: 0.13)
    static let muted = Color(red: 0.42, green: 0.46, blue: 0.48)
    static let mint = Color(red: 0.19, green: 0.63, blue: 0.51)
    static let coral = Color(red: 0.94, green: 0.38, blue: 0.31)
    static let gold = Color(red: 0.89, green: 0.66, blue: 0.22)
}

struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.34), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.08), radius: 22, x: 0, y: 12)
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(JieziTheme.mint)
        .controlSize(.large)
    }
}
