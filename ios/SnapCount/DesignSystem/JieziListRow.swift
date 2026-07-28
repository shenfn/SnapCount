import SwiftUI

// 芥子列表行：替代系统裸 List 行的基础单元。
// 结构：40pt 圆角图标块 + 标题/副题 + 尾部金额/计数 + chevron。
// 分隔线使用 JieziStroke.divider（ink 8% 0.5pt），不用系统粗灰线。

struct JieziListRow: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    var systemImage: String? = nil
    var iconTint: Color? = nil
    let title: String
    var subtitle: String? = nil
    var subtitleLineLimit = 1
    var trailingText: String? = nil
    var trailingSubtitle: String? = nil
    var trailingTint: Color? = nil
    var trailingIsMoney: Bool = false
    var showsChevron: Bool = true
    var showDivider: Bool = false
    var action: (() -> Void)? = nil

    private var resolvedTint: Color { iconTint ?? palette.brand }

    var body: some View {
        let row = HStack(spacing: JieziSpacing.Semantic.item_gap) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(resolvedTint)
                    .frame(width: JieziIcon.Semantic.list_row_block, height: JieziIcon.Semantic.list_row_block)
                    .background(
                        resolvedTint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: JieziRadius.md, style: .continuous)
                    )
            }

            VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                Text(title)
                    .font(JieziType.cardTitle)
                    .foregroundStyle(palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(JieziFont.footnote)
                        .foregroundStyle(palette.muted)
                        .lineLimit(subtitleLineLimit)
                }
            }

            Spacer(minLength: JieziSpacing.sm)

            if trailingText != nil || trailingSubtitle != nil {
                VStack(alignment: .trailing, spacing: JieziSpacing.xxs) {
                    if let trailingText {
                        Text(trailingText)
                            .font(trailingIsMoney ? JieziType.moneyInline : JieziFont.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(trailingTint ?? palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    if let trailingSubtitle {
                        Text(trailingSubtitle)
                            .font(JieziFont.caption)
                            .foregroundStyle(palette.muted)
                            .lineLimit(1)
                    }
                }
                .layoutPriority(1)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(JieziFont.caption.weight(.bold))
                    .foregroundStyle(palette.muted.opacity(0.6))
            }
        }
        .padding(.horizontal, JieziSpacing.Semantic.item_gap)
        .padding(.vertical, JieziSpacing.md)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showDivider {
                let stroke = JieziStroke.divider(palette)
                Rectangle()
                    .fill(stroke.color)
                    .frame(height: stroke.width)
                    .padding(.leading, systemImage != nil
                        ? JieziIcon.Semantic.list_row_block + JieziSpacing.Semantic.item_gap * 2
                        : JieziSpacing.Semantic.item_gap)
            }
        }

        if let action {
            Button {
                JieziHaptics.tap()
                action()
            } label: { row }
            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.99))
        } else {
            row
        }
    }
}

struct JieziRecordRow: View {
    var palette: JieziGeneratedPalette = JieziThemeManager.shared.palette
    let systemImage: String
    let iconTint: Color
    let title: String
    let subtitle: String
    let value: String
    let timeLabel: String
    var valueTint: Color? = nil
    var showsChevron = true
    var showDivider = false

    var body: some View {
        JieziListRow(
            palette: palette,
            systemImage: systemImage,
            iconTint: iconTint,
            title: title,
            subtitle: subtitle,
            subtitleLineLimit: 1,
            trailingText: value,
            trailingSubtitle: timeLabel,
            trailingTint: valueTint,
            trailingIsMoney: true,
            showsChevron: showsChevron,
            showDivider: showDivider
        )
    }
}
