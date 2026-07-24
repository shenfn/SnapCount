import SwiftUI

// 芥子空态：金线印章环 + serif 大标题 + 说明 + 可选主按钮。
// 过渡期用 SF Symbol；风格指南的空态插画资产到位后，把 systemImage 换成插画视图即可，布局不变。

struct JieziEmptyState: View {
    var palette: JieziGeneratedPalette = .defaultPalette
    let systemImage: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: JieziSpacing.lg) {
            ZStack {
                let stroke = JieziStroke.goldHairline(palette)
                Circle()
                    .stroke(stroke.color, lineWidth: stroke.width)
                    .frame(width: 72, height: 72)
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(palette.light)
            }
            .padding(.bottom, JieziSpacing.xs)

            Text(title)
                .font(JieziType.displayLarge)
                .foregroundStyle(palette.ink)

            if let message {
                Text(message)
                    .font(JieziFont.subheadline)
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            if let actionTitle, let action {
                JieziPrimaryButton(title: actionTitle, palette: palette, action: action)
                    .frame(maxWidth: 260)
                    .padding(.top, JieziSpacing.sm)
            }
        }
        .padding(.vertical, JieziSpacing.xl5)
        .frame(maxWidth: .infinity)
    }
}
