import SwiftUI
import UIKit

struct JieziThemePalette {
    let paper: Color
    let brand: Color
    let light: Color
    let space: Color
    let ink: Color
    let muted: Color
    let line: Color

    static let cyanGlow = JieziThemePalette(
        paper: Color(hex: "F5F1E7"),
        brand: Color(hex: "426E63"),
        light: Color(hex: "DCBF74"),
        space: Color(hex: "17312D"),
        ink: Color(hex: "202A27"),
        muted: Color(hex: "6E7773"),
        line: Color(hex: "426E63").opacity(0.13)
    )
}

enum JieziTheme {
    static let palette = JieziThemePalette.cyanGlow

    static let paper = palette.paper
    static let ink = palette.ink
    static let muted = palette.muted
    static let mint = palette.brand
    static let brand = palette.brand
    static let gold = palette.light
    static let light = palette.light
    static let space = palette.space
    static let line = palette.line
    static let coral = Color(hex: "B76555")

    static let pageBackground = LinearGradient(
        colors: [
            palette.paper,
            palette.paper.blended(with: palette.brand, amount: 0.035),
            palette.paper.blended(with: palette.light, amount: 0.045)
        ],
        startPoint: .top,
        endPoint: .bottomTrailing
    )

    static let sumeruBackground = RadialGradient(
        colors: [
            palette.brand.blended(with: palette.light, amount: 0.16),
            palette.space,
            palette.space.blended(with: .black, amount: 0.58)
        ],
        center: .center,
        startRadius: 18,
        endRadius: 520
    )

    static let brandWash = LinearGradient(
        colors: [
            palette.brand.opacity(0.92),
            palette.brand.blended(with: palette.space, amount: 0.22)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct JieziPageBackground: View {
    var body: some View {
        ZStack {
            JieziTheme.pageBackground
            RadialGradient(
                colors: [JieziTheme.light.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 260
            )
            LinearGradient(
                colors: [.white.opacity(0.22), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(
                JieziTheme.paper.opacity(0.72),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(JieziTheme.brand.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: JieziTheme.space.opacity(0.08), radius: 22, x: 0, y: 12)
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
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(JieziTheme.brandWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: JieziTheme.brand.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}

struct JieziPressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct JieziMonthSwitcher: View {
    let title: String
    let selectionToken: String
    let canAdvance: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            monthButton(systemImage: "chevron.left", enabled: true, action: onPrevious)
            Spacer(minLength: 12)
            Text(title)
                .font(.headline.monospacedDigit())
                .foregroundStyle(JieziTheme.ink)
            Spacer(minLength: 12)
            monthButton(systemImage: "chevron.right", enabled: canAdvance, action: onNext)
        }
        .sensoryFeedback(.selection, trigger: selectionToken)
    }

    private func monthButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.subheadline.bold())
                .frame(width: 44, height: 44)
                .foregroundStyle(enabled ? JieziTheme.brand : JieziTheme.muted.opacity(0.3))
                .background(.white.opacity(enabled ? 0.82 : 0.4), in: Circle())
                .overlay(Circle().stroke(JieziTheme.brand.opacity(enabled ? 0.1 : 0.04)))
        }
        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.9))
        .disabled(!enabled)
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    func blended(with other: Color, amount: Double) -> Color {
        let ratio = CGFloat(min(max(amount, 0), 1))
        let lhs = UIColor(self)
        let rhs = UIColor(other)
        var lr: CGFloat = 0
        var lg: CGFloat = 0
        var lb: CGFloat = 0
        var la: CGFloat = 0
        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        lhs.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        rhs.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)
        return Color(
            red: Double(lr + (rr - lr) * ratio),
            green: Double(lg + (rg - lg) * ratio),
            blue: Double(lb + (rb - lb) * ratio),
            opacity: Double(la + (ra - la) * ratio)
        )
    }
}
