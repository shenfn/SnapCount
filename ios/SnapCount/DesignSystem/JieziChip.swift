import SwiftUI

// 芥子 Chip：分类筛选胶囊。选中实色品牌底 + 白字，未选 8% 品牌底 + 品牌字。
// 可通过 tint 换成数据域色（JieziDomainColor）。

struct JieziChip: View {
    var palette: JieziGeneratedPalette = .defaultPalette
    let title: String
    var isSelected: Bool = false
    var tint: Color? = nil
    let action: () -> Void

    private var resolvedTint: Color { tint ?? palette.brand }

    var body: some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(JieziType.chip)
                .padding(.horizontal, JieziSpacing.md)
                .padding(.vertical, JieziSpacing.xs + JieziSpacing.xxs)
        }
        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.96))
        .foregroundStyle(isSelected ? Color.white : resolvedTint)
        .background(
            isSelected ? resolvedTint : resolvedTint.opacity(0.08),
            in: Capsule()
        )
    }
}
