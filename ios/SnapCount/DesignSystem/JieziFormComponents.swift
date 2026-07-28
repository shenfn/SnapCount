import SwiftUI

struct JieziFormTopBar: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    let title: String
    let primaryTitle: String
    let isWorking: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(JieziType.cardTitle)
                .foregroundStyle(palette.ink)
                .lineLimit(1)

            HStack(spacing: JieziSpacing.md) {
                Button {
                    JieziHaptics.tap()
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .foregroundStyle(palette.ink)
                        .background(palette.paper.opacity(0.78), in: Circle())
                        .overlay(Circle().stroke(palette.brand.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.92))
                .disabled(isWorking)
                .accessibilityLabel("取消")

                Spacer(minLength: 88)

                Button {
                    JieziHaptics.confirm()
                    onSubmit()
                } label: {
                    HStack(spacing: JieziSpacing.xs) {
                        if isWorking {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                        }
                        Text(primaryTitle)
                    }
                    .font(JieziFont.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, JieziSpacing.md)
                    .frame(minWidth: 80, minHeight: 40)
                    .background(palette.brand, in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.input, style: .continuous))
                }
                .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.96))
                .disabled(isWorking)
            }
        }
        .padding(.horizontal, JieziSpacing.Semantic.page_padding)
        .padding(.vertical, JieziSpacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(palette.brand.opacity(0.08))
                .frame(height: 1)
        }
    }
}

struct JieziFormSection<Content: View>: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.sm) {
            JieziSectionHeader(palette: palette, title: title, subtitle: subtitle)
                .padding(.horizontal, JieziSpacing.xs)

            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, JieziSpacing.Semantic.item_gap)
            .background(
                palette.paper.opacity(0.86),
                in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.input, style: .continuous)
            )
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.input, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: JieziRadius.Semantic.input, style: .continuous)
                    .stroke(palette.brand.opacity(0.10), lineWidth: 1)
            }
            .jieziShadow(JieziShadows.Semantic.card(palette))
        }
    }
}

struct JieziFormRow<Content: View>: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    var showsDivider = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: JieziSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.brand)
                        .frame(width: 18)
                }
                Text(title)
                    .font(JieziFont.caption.weight(.semibold))
                    .foregroundStyle(palette.muted)
                Spacer(minLength: 0)
            }

            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle {
                Text(subtitle)
                    .font(JieziFont.caption)
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, JieziSpacing.md)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(palette.brand.opacity(0.09))
                    .frame(height: 1)
            }
        }
    }
}

struct JieziFormMessage: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    let message: String
    var isError = true

    var body: some View {
        Label(message, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
            .font(JieziFont.footnote)
            .foregroundStyle(isError ? palette.coral : palette.brand)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(JieziSpacing.md)
            .background(
                (isError ? palette.coral : palette.brand).opacity(0.08),
                in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.input, style: .continuous)
            )
    }
}

private struct JieziInputSurfaceModifier: ViewModifier {
    let palette: JieziGeneratedPalette

    func body(content: Content) -> some View {
        content
            .font(JieziFont.body)
            .foregroundStyle(palette.ink)
            .padding(.horizontal, JieziSpacing.md)
            .frame(minHeight: 46)
            .background(
                palette.brand.opacity(0.055),
                in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                    .stroke(palette.brand.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func jieziInputSurface(palette: JieziGeneratedPalette = JieziThemeManager.shared.palette) -> some View {
        modifier(JieziInputSurfaceModifier(palette: palette))
    }
}
