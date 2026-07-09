import SwiftUI

struct InsightsView: View {
    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(JieziTheme.mint)
                Text("分析页地基")
                    .font(.title2.weight(.semibold))
                Text("首版会先做轻量月度摘要，完整跨域分析留到后续版本。")
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .navigationTitle("分析")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
