import SwiftUI

// 芥子指标块：指标说明（metricLabel muted）+ 大数字（moneyCard rounded 等宽）。
// 用于财务状态卡的 2×2 指标格、统计卡网格等场景。

struct JieziMetric: View {
    var palette: JieziGeneratedPalette = .defaultPalette
    let label: String
    let value: String
    var valueTint: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.xs) {
            Text(label)
                .font(JieziType.metricLabel)
                .foregroundStyle(palette.muted)
            Text(value)
                .font(JieziType.moneyCard)
                .monospacedDigit()
                .foregroundStyle(valueTint ?? palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
