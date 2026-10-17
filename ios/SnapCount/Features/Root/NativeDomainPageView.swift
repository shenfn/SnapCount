import SwiftUI

struct NativeDomainPageView: View {
    @EnvironmentObject private var appState: AppState
    let domain: AppDomain

    var body: some View {
        // 每次状态求值只读取一次窗口并创建一次模型；不跨帧缓存，增删改和身份切换自然刷新。
        let dates = NativeDomainScenePresentation.trendDateKeys(for: domain, dateKey: appState.selectedDateKey)
        let first = dates.first ?? appState.selectedDateKey
        let last = dates.last ?? appState.selectedDateKey
        let months = NativeLocalDate.monthKeys(from: first, through: last)
        let groups = appState.recordGroups(from: first, through: last)
        let details = appState.recordDetails(from: first, through: last)
        let loading = appState.loadingRecordMonthKey.map { months.contains($0) } ?? false
        let model = NativeDomainScenePresentation.make(
            domain: domain,
            dateKey: appState.selectedDateKey,
            weekGroups: groups,
            details: details,
            isSignedIn: appState.isSignedIn,
            isLoading: loading,
            errorMessage: months.compactMap { appState.recordMonthMessages[$0] }.first
        )
        NativeDomainPageContent(domain: domain, weekDates: dates, details: details, loadingWindow: loading, model: model)
    }
}

private struct NativeDomainPageContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let domain: AppDomain
    let weekDates: [String]
    let details: [String: NativeRecordDetail]
    let loadingWindow: Bool
    let model: NativeDomainScenePresentation
    @State private var showManualRecordSheet = false

    private var scene: JieziSceneTokens { JieziScene.tokens(for: domain.rawValue) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let stateMessage = model.stateMessage {
                    loadStateCard(stateMessage)
                } else {
                    dailyHero

                    if let measurementNote = model.measurementNote {
                        Text(measurementNote)
                            .font(JieziFont.caption)
                            .foregroundStyle(scene.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    metricShelf
                    weeklyTrend
                    if domain == .expense, let highestExpense = model.highestExpense {
                        highestExpenseCard(highestExpense)
                    }

                    if model.records.isEmpty {
                        emptyState
                    } else {
                        recordsCard
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JieziPrototypeLayout.page_inset)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showManualRecordSheet) {
            manualRecordSheet
        }
    }

    private var dailyHero: some View {
        HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(domain == .expense ? "当日支出" : model.primaryLabel)
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.foreground)
                if domain == .food, !model.records.isEmpty {
                    Text("估算")
                        .font(JieziFont.caption2)
                        .foregroundStyle(scene.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(scene.accent.opacity(0.11), in: Capsule())
                }
            }

            if domain == .expense {
                VStack(alignment: .leading, spacing: 7) {
                        Text(model.primaryValue)
                            .font(JieziType.prototypeHero.monospacedDigit())
                            .foregroundStyle(scene.foreground)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .minimumScaleFactor(0.68)
                    HStack(alignment: .firstTextBaseline) {
                        Text(model.secondaryLabel)
                            .font(JieziFont.caption)
                            .foregroundStyle(scene.muted)
                        Text(model.secondaryValue)
                            .font(JieziType.moneyCard.monospacedDigit())
                            .foregroundStyle(scene.accent)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.75)
                    }
                }
            } else {
                Text(model.primaryValue)
                    .font((domain == .sleep ? JieziType.prototypeSleepHero : JieziType.prototypeHero).monospacedDigit())
                    .foregroundStyle(scene.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.secondaryValue)
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if !dynamicTypeSize.isAccessibilitySize {
            Color.clear.frame(width: JieziPrototypeLayout.cat_width)
                .accessibilityHidden(true)
        }
        }
        .padding(.horizontal, JieziPrototypeLayout.metric_inset - JieziPrototypeLayout.page_inset)
        .frame(minHeight: JieziPrototypeLayout.hero_min_height, alignment: .topLeading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(appState.selectedDateKey)，\(domain.title)，\(model.primaryLabel)\(model.primaryValue)，\(model.secondaryLabel)\(model.secondaryValue)")
    }

    private var metricShelf: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: JieziPrototypeLayout.column_gap))
            : AnyLayout(HStackLayout(spacing: JieziPrototypeLayout.column_gap))
        return layout {
            ForEach(secondaryMetrics, id: \.0) { metric in
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.0)
                        .font(JieziFont.caption2)
                        .foregroundStyle(scene.muted)
                    Text(metric.1)
                        .font(JieziType.cardTitle)
                        .foregroundStyle(scene.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .padding(16)
                .background(scene.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private var secondaryMetrics: [(String, String)] {
        switch domain {
        case .expense:
            let maximum = model.highestExpense.flatMap { expenseAmount(for: $0) }
            return [
                ("支出笔数", "\(model.records.filter(isExpense).count) 笔"),
                ("最大一笔", maximum.map { String(format: "¥%.2f", $0) } ?? "未提供金额")
            ]
        case .sleep:
            let interval = model.records.count == 1 ? sleepInterval(for: model.records[0]) : nil
            return [("睡眠记录", "\(model.records.count) 条"), ("入睡 / 醒来", interval ?? "区间未提供")]
        case .food:
            let meals = Set(model.records.compactMap { detail(for: $0)?.payload?.string("meal_type") }).count
            return [("记录餐次", "\(model.records.count) 餐"), ("餐次类型", meals > 0 ? "\(meals) 类" : "未填写")]
        case .sport:
            let types = model.records.compactMap { detail(for: $0)?.payload?.string("sport_type") ?? detail(for: $0)?.payload?.string("activity_type") }
            return [("运动次数", "\(model.records.count) 次"), ("运动类型", mostFrequent(types) ?? "未填写")]
        case .reading:
            let books = Set(model.records.compactMap { detail(for: $0)?.payload?.string("book_name") }.filter { !$0.isEmpty })
            let pages = model.records.compactMap { measurement(for: $0, key: "pages")?.value }
            let pageValue = pages.count == model.records.count && !pages.isEmpty
                ? "\(Int(pages.reduce(0, +).rounded())) 页"
                : "未提供完整页数"
            return [("涉及书目", books.isEmpty ? "未填写" : "\(books.count) 本"), ("实际页数", pageValue)]
        }
    }

    private var weeklyTrend: some View {
        let maximum = max(model.weeklyValues.compactMap(\.value).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(weekTrendTitle)
                    .font(JieziType.sectionTitle)
                    .foregroundStyle(scene.foreground)
                Spacer()
                Text("\(weekDates.first ?? "") – \(weekDates.last ?? "")")
                    .font(JieziFont.caption2)
                    .foregroundStyle(scene.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(model.weeklyValues) { item in
                    VStack(spacing: 7) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(barColor(for: item))
                            .frame(height: barHeight(for: item, maximum: maximum))
                        Text(item.dayLabel)
                            .font(JieziFont.caption2.monospacedDigit())
                            .foregroundStyle(item.dateKey == appState.selectedDateKey ? scene.accent : scene.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(barAccessibilityLabel(for: item))
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(scene.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var weekTrendTitle: String {
        switch domain {
        case .expense: return "本周支出"
        case .sleep: return "近七日睡眠"
        case .food: return "近七日估算热量"
        case .sport: return "本周运动时长"
        case .reading: return "本周阅读时长"
        }
    }

    private func barHeight(for item: NativeDomainDayValue, maximum: Double) -> CGFloat {
        guard let value = item.value else { return 3 }
        return value == 0 ? 3 : max(7, CGFloat(value / maximum) * 66)
    }

    private func barColor(for item: NativeDomainDayValue) -> Color {
        guard item.value != nil else { return scene.muted.opacity(0.18) }
        return item.dateKey == appState.selectedDateKey ? scene.accent : scene.accent.opacity(0.42)
    }

    private func barAccessibilityLabel(for item: NativeDomainDayValue) -> String {
        guard let value = item.value else {
            return item.recordCount == 0
                ? "\(item.dateKey)，没有正式记录"
                : "\(item.dateKey)，记录未提供完整指标"
        }
        return "\(item.dateKey)，\(formatted(value))，\(item.recordCount) 条记录"
    }

    private func formatted(_ value: Double) -> String {
        if domain == .expense { return String(format: "¥%.2f", value) }
        if domain == .food { return "\(Int(value.rounded())) 千卡" }
        let minutes = Int(value.rounded())
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
    }

    private func highestExpenseCard(_ record: NativeDayRecord) -> some View {
        Button { appState.openDayRecord(record) } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .foregroundStyle(scene.accent)
                    .frame(width: 36, height: 36)
                    .background(scene.accent.opacity(0.11), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("最大一笔")
                        .font(JieziFont.caption2)
                        .foregroundStyle(scene.muted)
                    Text(record.title)
                        .font(JieziType.cardTitle)
                        .foregroundStyle(scene.foreground)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(expenseAmount(for: record).map { String(format: "¥%.2f", $0) } ?? "金额不可用")
                    .font(JieziType.moneyCard.monospacedDigit())
                    .foregroundStyle(scene.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(16)
            .background(scene.surface.opacity(0.76), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("最大一笔，\(record.title)，打开记录详情")
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(domain == .expense ? "收支明细" : "当日记录")
                    .font(JieziType.sectionTitle)
                    .foregroundStyle(scene.foreground)
                Spacer()
                Text("\(model.records.count) 条")
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.muted)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ForEach(model.records) { record in
                recordRow(record)
                if record.id != model.records.last?.id {
                    Rectangle()
                        .fill(scene.foreground.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }
            }
        }
        .background(scene.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func recordRow(_ record: NativeDayRecord) -> some View {
        Button { appState.openDayRecord(record) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(record.timeLabel ?? "—")
                    .font(JieziFont.caption2.monospacedDigit())
                    .foregroundStyle(scene.muted)
                    .frame(width: 42, alignment: .leading)
                    .padding(.top, 3)

                Image(systemName: record.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(scene.accent)
                    .frame(width: 30, height: 30)
                    .background(scene.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(JieziType.cardTitle)
                        .foregroundStyle(scene.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(recordSecondaryText(record))
                        .font(JieziFont.caption2)
                        .foregroundStyle(scene.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Text(recordValue(record))
                    .font(JieziType.moneyInline.monospacedDigit())
                    .foregroundStyle(scene.foreground)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.title)，\(recordSecondaryText(record))，\(recordValue(record))，打开详情")
    }

    private var emptyState: some View {
        JieziEmptyState(
            palette: scene.palette,
            systemImage: domain.systemImage,
            title: "这一天还没有\(domain.title)记录",
            message: domain == .reading ? "已有记录会按实际时长和页数呈现；未提供总页数时不显示进度。" : "添加一条真实记录，之后可以按日期回看。",
            actionTitle: domain == .food ? "记一餐" : "记一条",
            action: { showManualRecordSheet = true }
        )
        .padding(.vertical, 8)
        .background(scene.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func loadStateCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if loadingWindow {
                    ProgressView().tint(scene.accent)
                } else {
                    Image(systemName: "exclamationmark.arrow.circlepath")
                        .foregroundStyle(scene.accent)
                }
                Text(message)
                    .font(JieziFont.body)
                    .foregroundStyle(scene.foreground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !loadingWindow {
                Button {
                    Task { await appState.loadRecordDateWindow(around: appState.selectedDateKey, force: true) }
                } label: {
                    Label("重试读取", systemImage: "arrow.clockwise")
                        .font(JieziType.button)
                        .foregroundStyle(scene.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.84), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func recordValue(_ record: NativeDayRecord) -> String {
        if isIncome(record), !appState.isSignedIn { return "本地暂不可读取" }
        if isIncome(record) {
            return expenseAmount(for: record).map { "+¥\(String(format: "%.2f", $0))" } ?? "金额不可用"
        }
        if isExpense(record) {
            return expenseAmount(for: record).map { "-¥\(String(format: "%.2f", $0))" } ?? "金额不可用"
        }
        if let detail = detail(for: record),
           let measurement = NativeRecordDetailPresentationAdapter.measurements(for: detail).first {
            return measurement.isEstimated ? "约\(measurement.displayValue)" : measurement.displayValue
        }
        return "未提供指标"
    }

    private func recordSecondaryText(_ record: NativeDayRecord) -> String {
        if let detail = detail(for: record) {
            if isExpense(record) || isIncome(record) {
                return [detail.category, detail.platform].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            }
            let rows = NativeRecordDetailPresentationAdapter.extractedRows(for: detail)
            let fields = rows.filter { ["餐次", "质量等级", "运动类型", "书名", "发生时间"].contains($0.label) }
            if !fields.isEmpty { return fields.map { "\($0.label) \($0.value)" }.joined(separator: " · ") }
        }
        return record.subtitle.isEmpty ? "详情可查看原始记录" : record.subtitle
    }

    private func detail(for record: NativeDayRecord) -> NativeRecordDetail? {
        let canonical = NativeRecordReference(record.reference).canonicalValue
        return details[record.reference]
            ?? details[canonical]
            ?? details.values.first { NativeRecordReference($0.id).canonicalValue == canonical }
    }

    private func measurement(for record: NativeDayRecord, key: String) -> NativeRecordMeasurement? {
        guard let detail = detail(for: record) else { return nil }
        return NativeRecordDetailPresentationAdapter.measurements(for: detail).first { $0.key == key }
    }

    private func expenseAmount(for record: NativeDayRecord) -> Double? {
        if let amount = detail(for: record)?.amount { return amount }
        let value = record.value.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return value.isEmpty ? nil : Double(value)
    }

    private func isExpense(_ record: NativeDayRecord) -> Bool {
        record.kind == .expense && record.transactionType != "income"
    }

    private func isIncome(_ record: NativeDayRecord) -> Bool {
        record.kind == .income || record.transactionType == "income"
    }

    private func sleepInterval(for record: NativeDayRecord) -> String? {
        guard let payload = detail(for: record)?.payload,
              let asleep = payload.string("sleep_start_at"),
              let wake = payload.string("wake_at") else { return nil }
        return "\(asleep) – \(wake)"
    }

    private func mostFrequent(_ values: [String]) -> String? {
        Dictionary(grouping: values, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
    }

    @ViewBuilder
    private var manualRecordSheet: some View {
        if domain == .expense {
            UnifiedManualRecordEntry()
        } else {
            ManualRecordSheet(kind: .universal, domainKey: domain.rawValue)
        }
    }
}
