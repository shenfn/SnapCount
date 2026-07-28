import Foundation
import SwiftUI

struct HomeFinanceInsightCardView: View {
    let key: NativeHomeFinanceCardKey
    let summary: NativeHomeFinanceSummary
    let snapshot: DashboardSnapshot
    let recentSnapshot: DashboardSnapshot
    let accounts: [NativeAccount]
    let selectedDateKey: String

    var body: some View {
        HomeInsightCardFrame(
            title: key.title,
            subtitle: subtitle,
            systemImage: key.systemImage,
            accent: accent
        ) {
            content
        }
    }

    private var subtitle: String {
        switch key {
        case .cashSafety: return "账户状态实时"
        case .spendingRhythm: return "最近 7 天，含没有支出的日子"
        case .expenseStructure: return "按已归档消费记录统计"
        case .repaymentPlan: return "根据账户中的还款日"
        case .accountMix: return "已同步的资产与负债账户"
        }
    }

    private var accent: Color {
        switch key {
        case .cashSafety: return JieziTheme.brand
        case .spendingRhythm: return JieziTheme.mint
        case .expenseStructure: return JieziTheme.coral
        case .repaymentPlan: return JieziTheme.gold
        case .accountMix: return JieziTheme.space
        }
    }

    @ViewBuilder
    private var content: some View {
        switch key {
        case .cashSafety:
            cashSafety
        case .spendingRhythm:
            spendingRhythm
        case .expenseStructure:
            expenseStructure
        case .repaymentPlan:
            repaymentPlan
        case .accountMix:
            accountMix
        }
    }

    private var cashSafety: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HomeInsightMetricCell(label: "可用现金", value: money(summary.availableCash), tint: JieziTheme.brand)
                HomeInsightMetricCell(label: "当前欠款", value: money(summary.liabilityTotal), tint: summary.liabilityTotal > 0 ? JieziTheme.coral : JieziTheme.ink)
            }
            HStack {
                Label(summary.statusLabel, systemImage: summary.netWorthEstimate >= 0 ? "checkmark.shield" : "exclamationmark.shield")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(summary.netWorthEstimate >= 0 ? JieziTheme.brand : JieziTheme.coral)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("净额估算")
                        .font(.caption)
                        .foregroundStyle(JieziTheme.muted)
                    Text(money(summary.netWorthEstimate, signed: true))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(summary.netWorthEstimate >= 0 ? JieziTheme.ink : JieziTheme.coral)
                }
            }
            if let liability = summary.nearestLiability {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("欠款较高账户")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                        Text(liability.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(money(liability.currentBalance))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                        Text(liability.paymentDueDay.map { "每月 \($0) 日" } ?? "未设置还款日")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                    }
                }
                .padding(.top, 2)
            } else {
                Text("添加账户后，这里会同时看到现金和待还压力。")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.muted)
            }
        }
    }

    private var spendingRhythm: some View {
        let days = NativeHomeInsightAnalytics.recentDailySummaries(
            from: recentSnapshot,
            endingAt: selectedDateKey
        )
        let values = days.map(\.expense)
        let total = values.reduce(0, +)
        let average = values.isEmpty ? 0 : total / Double(values.count)
        let activeDays = values.filter { $0 > 0 }.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HomeInsightMetricCell(label: "近 7 日支出", value: money(total), tint: JieziTheme.coral)
                HomeInsightMetricCell(label: "日均支出", value: money(average), tint: JieziTheme.ink)
            }
            InsightBarStrip(
                values: values,
                labels: days.map { String($0.dateKey.suffix(2)) },
                tint: JieziTheme.coral
            )
            HStack {
                Text("有消费的 \(activeDays) 天")
                Spacer()
                Text("当天 \(money(summary.dayExpense))")
            }
            .font(.caption)
            .foregroundStyle(JieziTheme.muted)
        }
    }

    private var expenseStructure: some View {
        let breakdown = NativeHomeInsightAnalytics.expenseBreakdown(from: snapshot)
        let total = NativeHomeInsightAnalytics.confirmedExpenseTotal(from: snapshot)
        let detailsAreReady = NativeHomeInsightAnalytics.hasHydratedExpenseDetails(in: snapshot)
        let top = breakdown.first

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("所选月已确认支出")
                        .font(.caption)
                        .foregroundStyle(JieziTheme.muted)
                    Text(money(total))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                if detailsAreReady, let top {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("最高分类")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                        Text(top.name)
                            .font(.subheadline.weight(.semibold))
                        Text(money(top.amount))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(JieziTheme.coral)
                    }
                }
            }
            if total == 0 {
                HomeInsightEmptyLine(text: "归档几笔消费后，这里会告诉你钱主要花在哪里。")
            } else if !detailsAreReady {
                HomeInsightEmptyLine(text: "连接后会同步消费分类详情。")
            } else {
                ForEach(Array(breakdown.prefix(3))) { item in
                    HStack(spacing: 8) {
                        Text(item.name)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(money(item.amount))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(JieziTheme.muted)
                        ProgressView(value: total > 0 ? item.amount / total : 0)
                            .tint(JieziTheme.coral)
                            .frame(width: 66)
                    }
                }
            }
        }
    }

    private var repaymentPlan: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let liability = summary.nearestLiability {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(JieziTheme.gold)
                        .frame(width: 38, height: 38)
                        .background(JieziTheme.gold.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("欠款较高账户")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                        Text(liability.title)
                            .font(.headline)
                        Text(liability.paymentDueDay.map { "每月 \($0) 日还款" } ?? "还款日尚未设置")
                            .font(.subheadline)
                            .foregroundStyle(JieziTheme.muted)
                    }
                    Spacer()
                    Text(money(liability.currentBalance))
                        .font(.headline.monospacedDigit())
                }
                HStack {
                    Text("负债账户当前欠款")
                    Spacer()
                    Text(money(summary.liabilityTotal))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
            } else {
                HomeInsightEmptyLine(text: "还没有需要关注的待还账户。")
                HStack {
                    Text("可用现金")
                    Spacer()
                    Text(money(summary.availableCash))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
            }
        }
    }

    private var accountMix: some View {
        let activeAccounts = accounts.filter { !$0.isArchived }
        let assets = activeAccounts.filter { !$0.type.isLiability }
        let liabilities = activeAccounts.filter(\.type.isLiability)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HomeInsightMetricCell(label: "资产账户", value: "\(assets.count) 个", tint: JieziTheme.brand)
                HomeInsightMetricCell(label: "负债账户", value: "\(liabilities.count) 个", tint: JieziTheme.coral)
            }
            HStack {
                Label("资产余额", systemImage: "wallet.pass")
                Spacer()
                Text(money(assets.reduce(0) { $0 + $1.currentBalance }))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            HStack {
                Label("负债余额", systemImage: "creditcard")
                Spacer()
                Text(money(liabilities.reduce(0) { $0 + max($1.currentBalance, 0) }))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(JieziTheme.muted)
            .font(.footnote)
        }
    }

    private func money(_ value: Double, signed: Bool = false) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)¥\(Int(value.rounded()))"
    }
}

struct HomeDomainInsightCardView: View {
    let key: NativeHomeDomainCardKey
    let snapshot: DashboardSnapshot
    let selectedDaySummary: NativeDailySummary
    let selectedDateKey: String

    var body: some View {
        HomeInsightCardFrame(
            title: key.title,
            subtitle: subtitle,
            systemImage: key.systemImage,
            accent: accent
        ) {
            content
        }
    }

    private var subtitle: String {
        switch key {
        case .sleepSpending: return "只做同日观察，不代表因果关系"
        case .dailyBalance: return "把同一天的不同记录放在一起看"
        default: return "来自已同步的数据域记录"
        }
    }

    private var accent: Color {
        switch key {
        case .sleepRecovery: return JieziTheme.space
        case .movementRhythm: return JieziTheme.brand
        case .foodEnergy: return JieziTheme.coral
        case .readingProgress: return JieziTheme.gold
        case .sleepSpending: return JieziTheme.mint
        case .dailyBalance: return JieziTheme.brand
        }
    }

    @ViewBuilder
    private var content: some View {
        switch key {
        case .sleepRecovery:
            domainMetricContent(domainKey: "sleep", emptyText: "记录睡眠后，这里会显示时长和质量变化。")
        case .movementRhythm:
            domainMetricContent(domainKey: "sport", emptyText: "记录一次运动后，这里会显示时长和运动类型。")
        case .foodEnergy:
            domainMetricContent(domainKey: "food", emptyText: "记录饮食后，这里会显示热量和餐次分布。")
        case .readingProgress:
            domainMetricContent(domainKey: "reading", emptyText: "记录阅读后，这里会显示阅读时长和书籍分布。")
        case .sleepSpending:
            sleepSpending
        case .dailyBalance:
            dailyBalance
        }
    }

    @ViewBuilder
    private func domainMetricContent(domainKey: String, emptyText: String) -> some View {
        let records = NativeHomeInsightAnalytics.domainRecords(domainKey, from: snapshot)
        if !records.isEmpty,
           !NativeHomeInsightAnalytics.hasHydratedDetails(for: domainKey, in: snapshot) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HomeInsightMetricCell(label: "月内记录", value: "\(records.count)", tint: accent)
                    HomeInsightMetricCell(label: "详细指标", value: "待同步", tint: JieziTheme.ink)
                }
                HomeInsightEmptyLine(text: "连接后会同步时长、热量等详细数据。")
            }
        } else if let presentation = presentation(for: domainKey), !presentation.recentRecords.isEmpty {
            let metrics = presentation.metrics
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    HomeInsightMetricCell(label: metricLabel(metrics, index: 0, fallback: "月内累计"), value: metricValue(metrics, index: 0), tint: accent)
                    HomeInsightMetricCell(label: metricLabel(metrics, index: 1, fallback: "月内记录"), value: metricValue(metrics, index: 1), tint: JieziTheme.ink)
                }
                if let top = presentation.distribution.first {
                    HStack {
                        Text(domainKey == "reading" ? "阅读投入最多" : "主要分布")
                        Spacer()
                        Text(top.name)
                            .font(.subheadline.weight(.semibold))
                        Text(top.displayValue)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(JieziTheme.muted)
                    }
                }
                if let recent = presentation.recentRecords.first {
                    HStack(spacing: 8) {
                        Image(systemName: recent.systemImage)
                            .foregroundStyle(accent)
                        Text(recent.title)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                        Spacer()
                        Text(recent.value)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(JieziTheme.muted)
                    }
                }
            }
        } else {
            HomeInsightEmptyLine(text: emptyText)
        }
    }

    private var sleepSpending: some View {
        let observation = NativeHomeInsightAnalytics.sleepSpendingObservation(from: snapshot)
        return VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                HomeInsightMetricCell(label: "有睡眠记录", value: "\(observation.sleepDays) 天", tint: JieziTheme.space)
                HomeInsightMetricCell(label: "这些天日均支出", value: money(observation.sleepDayAverage), tint: JieziTheme.coral)
            }
            HStack {
                Text("所有有记录日的日均支出")
                Spacer()
                Text(money(observation.allDayAverage))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            .font(.footnote)
            .foregroundStyle(JieziTheme.muted)
            Text(observation.sleepDays == 0 ? "还没有足够的睡眠记录可供比较。" : "只把同一天的数据放在一起看，方便你自己判断。")
                .font(.caption)
                .foregroundStyle(JieziTheme.muted)
        }
    }

    private var dailyBalance: some View {
        let group = snapshot.dayRecordGroups.first { $0.dateKey == selectedDateKey }
        let domainCounts = (group?.records ?? [])
            .filter { $0.kind != .staging && $0.kind != .expense && $0.kind != .income }
            .reduce(into: [String: Int]()) { result, record in
                let key = record.domainKey ?? record.kind.rawValue
                result[key, default: 0] += 1
            }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                HomeInsightMetricCell(label: "支出", value: money(selectedDaySummary.expense), tint: JieziTheme.coral)
                HomeInsightMetricCell(label: "收入", value: money(selectedDaySummary.income, signed: true), tint: JieziTheme.brand)
            }
            HStack {
                Text("当天已有记录")
                Spacer()
                Text("\(NativeHomeInsightAnalytics.recordCount(on: selectedDateKey, in: snapshot)) 条")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }
            .font(.footnote)
            .foregroundStyle(JieziTheme.muted)
            if domainCounts.isEmpty {
                Text("继续记录睡眠、运动、饮食或阅读后，这里会看到当天的组合。")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(domainCounts.sorted(by: { $0.key < $1.key }).prefix(3)), id: \.key) { item in
                        Text("\(domainTitle(item.key)) \(item.value)")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(accent.opacity(0.1), in: Capsule())
                    }
                }
            }
        }
    }

    private func presentation(for domainKey: String) -> NativeDomainPresentation? {
        guard let definition = snapshot.domains.first(where: { $0.id == domainKey }) else { return nil }
        return NativeDomainPresentationAdapter.presentation(for: definition, dashboard: snapshot)
    }

    private func metricLabel(_ metrics: [NativeDomainMetric], index: Int, fallback: String) -> String {
        let label = metrics.indices.contains(index) ? metrics[index].label : fallback
        return label.replacingOccurrences(of: "本月", with: "月内")
    }

    private func metricValue(_ metrics: [NativeDomainMetric], index: Int) -> String {
        metrics.indices.contains(index) ? metrics[index].value : "暂无"
    }

    private func domainTitle(_ key: String) -> String {
        switch key {
        case "sport": return "运动"
        case "sleep": return "睡眠"
        case "food": return "饮食"
        case "reading": return "阅读"
        case "wallet": return "钱包"
        default: return key
        }
    }

    private func money(_ value: Double, signed: Bool = false) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)¥\(Int(value.rounded()))"
    }
}

private struct HomeInsightCardFrame<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(JieziTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(JieziTheme.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(JieziTheme.muted)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jieziCard(palette: JieziTheme.palette, solid: true)
    }
}

private struct HomeInsightMetricCell: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(JieziTheme.muted)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeInsightEmptyLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundStyle(JieziTheme.gold)
            Text(text)
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
        }
    }
}

private struct InsightBarStrip: View {
    let values: [Double]
    let labels: [String]
    let tint: Color

    var body: some View {
        let maximum = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 7) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 5) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(value > 0 ? tint : tint.opacity(0.12))
                        .frame(height: max(5, CGFloat(value / maximum) * 42))
                    if labels.indices.contains(index) {
                        Text(labels[index])
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(JieziTheme.muted)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 64)
    }
}
