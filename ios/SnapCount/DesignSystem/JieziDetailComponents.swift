import SwiftUI

struct JieziDetailCard<Content: View>: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    let title: String
    var systemImage: String? = nil
    var tint: Color? = nil
    var solid = true
    @ViewBuilder var content: () -> Content

    private var resolvedTint: Color { tint ?? palette.brand }

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.md) {
            HStack(spacing: JieziSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(resolvedTint)
                        .frame(width: 30, height: 30)
                        .background(
                            resolvedTint.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                        )
                }
                Text(title)
                    .font(JieziType.sectionTitle)
                    .foregroundStyle(palette.ink)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
        }
        .jieziCard(palette: palette, solid: solid)
    }
}

struct JieziDetailRow: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    let label: String
    let value: String
    var valueTint: Color? = nil
    var showDivider = false

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.xs) {
            Text(label)
                .font(JieziFont.caption.weight(.semibold))
                .foregroundStyle(palette.muted)
            Text(value)
                .font(JieziFont.subheadline)
                .foregroundStyle(valueTint ?? palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, JieziSpacing.md)
        .overlay(alignment: .bottom) {
            if showDivider {
                let stroke = JieziStroke.divider(palette)
                Rectangle()
                    .fill(stroke.color)
                    .frame(height: stroke.width)
            }
        }
    }
}
