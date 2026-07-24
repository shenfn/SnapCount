import SwiftUI

// 芥子按钮族：主 / 次 / 危险 / 幽灵 四态。
// 全部消费 JieziTheme+Generated.swift 的 Token（JieziType.button / JieziRadius.Semantic.button / JieziShadows / JieziGradient）。
// 按压反馈复用手写 JieziPressableButtonStyle（JieziTheme.swift）。

struct JieziPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var palette: JieziGeneratedPalette = .defaultPalette
    let action: () -> Void

    var body: some View {
        Button {
            JieziHaptics.confirm()
            action()
        } label: {
            HStack(spacing: JieziSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(JieziType.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(JieziPressableButtonStyle())
        .foregroundStyle(.white)
        .background(
            JieziGradient.brandWash(palette: palette),
            in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.button, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.Semantic.button, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .jieziShadow(JieziShadows.Semantic.primary_button(palette))
    }
}

struct JieziSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var palette: JieziGeneratedPalette = .defaultPalette
    let action: () -> Void

    var body: some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            HStack(spacing: JieziSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(JieziType.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(JieziPressableButtonStyle())
        .foregroundStyle(palette.brand)
        .background(
            palette.brand.opacity(0.08),
            in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.button, style: .continuous)
        )
    }
}

struct JieziDangerButton: View {
    let title: String
    var systemImage: String? = nil
    var palette: JieziGeneratedPalette = .defaultPalette
    let action: () -> Void

    var body: some View {
        Button {
            JieziHaptics.warning()
            action()
        } label: {
            HStack(spacing: JieziSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(JieziType.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(JieziPressableButtonStyle())
        .foregroundStyle(palette.coral)
        .background(
            palette.coral.opacity(0.10),
            in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.button, style: .continuous)
        )
    }
}

struct JieziGhostButton: View {
    let title: String
    var systemImage: String? = nil
    var palette: JieziGeneratedPalette = .defaultPalette
    let action: () -> Void

    var body: some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            HStack(spacing: JieziSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(JieziType.button)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
        }
        .buttonStyle(JieziPressableButtonStyle())
        .foregroundStyle(palette.ink)
        .background(
            palette.paper.opacity(0.72),
            in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.button, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.Semantic.button, style: .continuous)
                .stroke(palette.brand.opacity(0.18), lineWidth: 1)
        }
    }
}
