import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var range: NativeInsightRange = .fourteen

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("分析范围", selection: $range) {
                        ForEach(NativeInsightRange.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if appState.isLoadingInsights, appState.insightsSnapshot == nil {
                        ProgressView("正在汇总多域数据…")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else if let snapshot = appState.insightsSnapshot, snapshot.range == range {
                        if snapshot.rows.isEmpty {
                            ContentUnavailableView(
                                "暂无可分析数据",
                                systemImage: "chart.xyaxis.line",
                                description: Text("记录消费、睡眠、饮食或运动后，这里会形成跨域日汇总。")
                            )
                            .frame(maxWidth: .infinity, minHeight: 240)
                        } else {
                            summarySection(snapshot)
                            maturitySection(snapshot)
                            financeChart(snapshot)
                            dailySection(snapshot)
                        }
                    } else if let message = appState.insightsMessage {
                        Button("加载失败，点此重试：\(message)") {
                            Task { await appState.loadInsights(range: range, force: true) }
                        }
                        .foregroundStyle(JieziTheme.coral)
                    }
                }
                .padding(16)
            }
            .refreshable { await appState.loadInsights(range: range, force: true) }
        }
        .navigationTitle("分析")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: range) { await appState.loadInsights(range: range) }
    }

    @ViewBuilder
    private func summarySection(_ snapshot: NativeInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("跨域联动").font(.title2.bold())
                    Text("近 \(snapshot.range.rawValue) 天 · \(snapshot.activeDays) 个活跃日")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(snapshot.maturity.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JieziTheme.brand)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                InsightMetric(label: "总消费", value: currency(snapshot.expenseTotal), tint: JieziTheme.coral)
                InsightMetric(label: "总收入", value: currency(snapshot.incomeTotal), tint: JieziTheme.mint)
                InsightMetric(label: "区间净额", value: signedCurrency(snapshot.netBalance), tint: snapshot.netBalance >= 0 ? JieziTheme.mint : JieziTheme.coral)
                InsightMetric(label: "平均睡眠", value: String(format: "%.1f 小时", snapshot.averageSleepHours), tint: JieziTheme.brand)
                InsightMetric(label: "饮食热量", value: String(format: "%.0f 千卡", snapshot.foodCalories), tint: JieziTheme.gold)
                InsightMetric(label: "记录餐次", value: "\(snapshot.foodMeals) 餐", tint: JieziTheme.gold)
            }

            Text(ruleInsight(snapshot))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func maturitySection(_ snapshot: NativeInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("成长进度").font(.title3.bold())
            ForEach(snapshot.growth) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(domainColor(item.domain)).frame(width: 8, height: 8)
                        Text(item.domain.title).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(item.maturity.label).font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: item.maturity.progress)
                        .tint(domainColor(item.domain))
                    Text(item.hint).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func financeChart(_ snapshot: NativeInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("每日收支流水").font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                Chart(snapshot.rows) { row in
                    BarMark(x: .value("日期", row.date), y: .value("支出", -row.expenseTotal))
                        .foregroundStyle(JieziTheme.coral)
                    BarMark(x: .value("日期", row.date), y: .value("收入", row.incomeTotal))
                        .foregroundStyle(JieziTheme.mint)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) { Text("¥\(Int(abs(amount)))") }
                        }
                    }
                }
                .frame(width: max(CGFloat(snapshot.rows.count) * 36, 340), height: 220)
            }
        }
        .padding(16)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func dailySection(_ snapshot: NativeInsightSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("每日明细").font(.title3.bold())
            ForEach(snapshot.rows.reversed()) { row in
                VStack(alignment: .leading, spacing: 7) {
                    Text(row.date).font(.subheadline.weight(.semibold))
                    if row.expenseTotal > 0 { insightLine("支出", currency(row.expenseTotal), JieziTheme.coral) }
                    if row.incomeTotal > 0 { insightLine("收入", currency(row.incomeTotal), JieziTheme.mint) }
                    if row.sleepMinutes > 0 { insightLine("睡眠", duration(row.sleepMinutes), JieziTheme.brand) }
                    if row.sportMinutes > 0 { insightLine("运动", duration(row.sportMinutes), .cyan) }
                    if row.foodCalories > 0 { insightLine("饮食", String(format: "%.0f 千卡 · %d 餐", row.foodCalories, row.foodMeals), JieziTheme.gold) }
                    if row.readingMinutes > 0 { insightLine("阅读", duration(row.readingMinutes), .blue) }
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }

    private func insightLine(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private func ruleInsight(_ snapshot: NativeInsightSnapshot) -> String {
        let stage: String
        switch snapshot.maturity.key {
        case .seed: stage = "记录刚开始，先积累真实日常，不急着下结论。"
        case .sprout: stage = "轮廓已经出现，目前适合观察极值和异常。"
        case .growing: stage = "趋势正在显现，可以开始观察生活节奏。"
        case .mature: stage = "数据量已足以形成跨域关联观察。"
        case .rich: stage = "你已经形成稳定的个人数据基准线。"
        }
        let flow = snapshot.netBalance >= 0
            ? "这段时间净流入 \(currency(snapshot.netBalance))。"
            : "这段时间净流出 \(currency(abs(snapshot.netBalance)))。"
        return stage + " " + flow
    }

    private func domainColor(_ domain: NativeInsightDomain) -> Color {
        switch domain {
        case .expense: return JieziTheme.coral
        case .income: return JieziTheme.mint
        case .sleep: return JieziTheme.brand
        case .sport: return .cyan
        case .food: return JieziTheme.gold
        case .reading: return .blue
        }
    }

    private func currency(_ value: Double) -> String { String(format: "¥%.0f", value) }
    private func signedCurrency(_ value: Double) -> String { String(format: "%@¥%.0f", value >= 0 ? "+" : "-", abs(value)) }
    private func duration(_ minutes: Double) -> String {
        let hours = Int(minutes) / 60
        let remainder = Int(minutes) % 60
        if hours == 0 { return "\(remainder) 分钟" }
        if remainder == 0 { return "\(hours) 小时" }
        return "\(hours) 小时 \(remainder) 分钟"
    }
}

private struct InsightMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }
}
