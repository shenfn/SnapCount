import SwiftUI
import Charts

struct NativeDomainPageView: View {
    @EnvironmentObject private var appState: AppState
    let domain: AppDomain
    var browsingDateKey: String? = nil
    var isDrillDown = false
    var onSelectDate: ((String) -> Void)? = nil

    var body: some View {
        // 每次状态求值只读取一次窗口并创建一次模型；不跨帧缓存，增删改和身份切换自然刷新。
        let dateKey = browsingDateKey ?? appState.selectedDateKey
        let dates = NativeDomainScenePresentation.trendDateKeys(for: domain, dateKey: dateKey)
        let trendStart = dates.first ?? dateKey
        let previousDay = NativeLocalDate.shiftedDateKey(dateKey, byDays: -1) ?? trendStart
        let first = domain == .sleep ? (NativeLocalDate.shiftedDateKey(dateKey, byDays: -30) ?? trendStart)
            : domain == .expense ? min(trendStart, previousDay) : trendStart
        let last = dates.last ?? dateKey
        let months = NativeLocalDate.monthKeys(from: first, through: last)
        let groups = appState.recordGroups(from: first, through: last)
        let details = appState.recordDetails(from: first, through: last)
        let loading = months.contains { appState.isLoadingRecordMonth($0) }
        let model = NativeDomainScenePresentation.make(
            domain: domain,
            dateKey: dateKey,
            weekGroups: groups,
            details: details,
            isSignedIn: appState.isSignedIn,
            isLoading: loading,
            errorMessage: months.compactMap { appState.recordMonthMessages[$0] }.first
                ?? (months.contains(NativeMonthKey.current()) ? appState.dashboardMessage : nil)
        )
        NativeDomainPageContent(domain: domain, weekDates: dates, details: details, loadingWindow: loading, model: model,
                                isDrillDown: isDrillDown, onSelectDate: onSelectDate)
    }
}

struct NativeDomainPageContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let domain: AppDomain
    let weekDates: [String]
    let details: [String: NativeRecordDetail]
    let loadingWindow: Bool
    let model: NativeDomainScenePresentation
    var isDrillDown = false
    var onSelectDate: ((String) -> Void)? = nil
    @State private var showManualRecordSheet = false
    @State private var showDayRecords = false
    @State private var selectedMinute: Int?
    @State private var showsEnergyReference = false


    private var scene: JieziSceneTokens { JieziScene.tokens(for: domain.rawValue) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let stateMessage = model.stateMessage {
                    loadStateCard(stateMessage)
                } else {
                    if isDrillDown {
                        Text("\(model.primaryLabel) · \(model.primaryValue)")
                            .font(JieziType.moneyCard).foregroundStyle(scene.foreground)
                    } else { dailyHero }

                    if let refreshMessage = model.refreshMessage {
                        loadStateCard(refreshMessage)
                    }

                    if let measurementNote = model.measurementNote {
                        Text(measurementNote)
                            .font(JieziFont.caption)
                            .foregroundStyle(scene.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    domainSections
                    if isDrillDown { currentCandidates } else { observationEntry }
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
        .sheet(isPresented: $showDayRecords) {
            NavigationStack {
                recordDrill(records: model.records)
                    .navigationTitle("\(model.dateKey) · \(domain.title)")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showDayRecords = false }
                        }
                    }
            }
        }
        .alert("通用营养参考", isPresented: $showsEnergyReference) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("2,000 千卡是营养标签使用的通用参考值，个人需要可能不同。这不是你的个人目标或超标线，也不表示还能吃多少。点位只对应已记录的餐食，不代表全天完整摄入。")
        }
    }

    @ViewBuilder
    private var domainSections: some View {
        switch domain {
        case .expense:
            expenseTimeline
            if isDrillDown { merchantRanking }
            else {
                NavigationLink(value: NativeDomainDrillRoute(domain: .expense, dateKey: model.dateKey)) { merchantRanking }
                    .buttonStyle(.plain).accessibilityHint("查看这一天全部记账记录")
            }
            if isDrillDown { expenseComparison }
            else if let highest = model.highestExpense {
                pairedCards { previousDayComparison } second: { highestExpenseCard(highest) }
            } else { previousDayComparison }
            if isDrillDown { recordsOrEmpty }
        case .sleep:
            if !model.records.isEmpty { sleepIntervals }
            if let record = model.sleep?.mainRecord {
                pairedCards {
                    sleepClockCard(record, key: "sleep_start_at", label: "入睡")
                } second: {
                    sleepClockCard(record, key: "wake_at", label: "醒来")
                }
            }
            weeklyTrend
            sleepBaselineEvidence
            recordsOrEmpty
        case .food:
            foodEnergyReference
            recordsOrEmpty
            pairedCards {
                if let meal = model.highestMeal { highestMealCard(meal) }
                else { metricCard("最大一餐", value: "暂无可比较记录", caption: "需要可读取的热量估算") }
            } second: { periodSummaryEntry }
        case .sport:
            weeklyTrend
            pairedCards {
                metricCard("本周次数", value: "\(model.periodRecordCount) 次",
                    caption: model.periodTypes.isEmpty ? "类型尚未提供" : model.periodTypes.joined(separator: " · "))
            } second: { periodSummaryEntry }
            recordsOrEmpty
        case .reading:
            if !model.records.isEmpty { readingBooks }
            pairedCards {
                metricCard("当日阅读", value: model.primaryValue, caption: model.secondaryValue)
            } second: { periodSummaryEntry }
            recordsOrEmpty
        }
    }

    private func pairedCards<First: View, Second: View>(@ViewBuilder first: () -> First, @ViewBuilder second: () -> Second) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: JieziPrototypeLayout.column_gap))
            : AnyLayout(HStackLayout(alignment: .top, spacing: JieziPrototypeLayout.column_gap))
        return layout { first(); second() }
    }

    private func metricCard(_ label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            JieziMetric(palette: scene.palette, label: label, value: value)
            Text(caption).font(JieziFont.caption2).foregroundStyle(scene.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    @ViewBuilder
    private var periodSummaryEntry: some View {
        if domain == .sport && !isDrillDown {
            NavigationLink(value: NativeDomainDrillRoute(domain: domain, dateKey: model.dateKey)) { periodSummary }
                .buttonStyle(.plain)
        } else { Menu {
            ForEach(model.weeklyValues) { item in
                Button { selectDate(item.dateKey) } label: { Text(barAccessibilityLabel(for: item)) }
            }
        } label: { periodSummary }
        .buttonStyle(.plain)
        .accessibilityHint("选择日期查看\(domain.title)记录")
        }
    }

    private func sleepClockCard(_ record: NativeDayRecord, key: String, label: String) -> some View {
        let raw = detail(for: record)?.payload?.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let clock = raw.flatMap { NativeLocalDate.financeTimeKey(occurredAt: $0) }
        let date = NativeLocalDate.financeDateKey(occurredAt: raw, legacyDate: nil)
        let baseline = key == "wake_at" ? model.sleep?.wake : model.sleep?.bedtime
        let comparison: String
        if NativeSleepFacts.hasInvalidInterval(detail(for: record)?.payload ?? [:]) {
            comparison = "入睡与醒来顺序无效，暂不比较"
        } else if let median = baseline?.median, let actual = NativeSleepSummary.clockMinutes(raw) {
            let difference = NativeSleepSummary.clockDifference(actual, baseline: median)
            comparison = "平时 \(NativeSleepSummary.clockLabel(median)) · \(difference == 0 ? "相同" : "\(difference > 0 ? "晚" : "早")\(abs(difference))分钟")\n\(baseline?.evidence ?? "")"
        } else { comparison = baseline?.evidence ?? "尚无可比较记录" }
        return Button { appState.openDayRecord(record) } label: {
            metricCard("主要睡眠 · \(label)", value: clock ?? (raw?.isEmpty == false ? "时间不可读取" : "未提供"), caption: "\(date ?? "原记录未提供日期")\n\(comparison)")
        }
        .buttonStyle(.plain)
    }

    private var sleepBaselineEvidence: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("近七夜只统计每日主要睡眠；当天总时长包含午休。")
            if !model.records.isEmpty && model.sleep?.mainRecord == nil {
                Text("当天时长信息不完整，暂不能选出主要睡眠或比较入睡/醒来。")
            }
            if let baseline = model.sleep?.duration {
                Text(baseline.median.map { "平时主要睡眠 \(Int($0.rounded()))分钟 · \(baseline.evidence)" } ?? baseline.evidence)
                if let median = baseline.median, let actual = model.sleep?.mainMinutesByDay[model.dateKey] {
                    let difference = Int((actual - median).rounded())
                    Text(difference == 0 ? "主要睡眠和平时相同" : "主要睡眠比平时\(difference > 0 ? "多" : "少")\(abs(difference))分钟")
                }
            }
        }
        .font(JieziFont.caption).foregroundStyle(scene.muted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func selectDate(_ dateKey: String) {
        if let onSelectDate { onSelectDate(dateKey) } else { appState.selectedDateKey = dateKey }
    }

    private var currentCandidates: some View {
        let candidates = appState.dashboard.stagingRecords.filter { ($0.domainKey ?? $0.recordType) == domain.rawValue }
        let expenses = domain == .expense ? appState.dashboard.pendingExpenses : []
        return VStack(alignment: .leading, spacing: 12) {
            Text("当前待处理候选").font(JieziType.cardTitle)
            Text("最新候选，不是所选历史日期的快照；未确认，不计入上方统计。")
                .font(JieziFont.caption).fixedSize(horizontal: false, vertical: true)
            if let message = appState.inboxFinanceMessage {
                Text(message).font(JieziFont.caption)
                Button("重读候选") { Task { await appState.refreshInboxProjection() } }
            } else if candidates.isEmpty && expenses.isEmpty { Text("当前没有这一领域的候选").font(JieziFont.caption) }
            ForEach(expenses) { pending in
                Button { appState.openPendingExpense(pending) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pending.title).font(JieziType.cardTitle)
                        Text("\(pending.dateKey) · 待确认支出 · \(String(format: "¥%.2f", pending.amount))").font(JieziFont.caption)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
            }
            ForEach(candidates) { candidate in
                Button {
                    appState.presentedOverlay = .inbox
                    appState.inboxPath = NavigationPath([NativeInboxRoute.staging(recordId: candidate.id)])
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.title).font(JieziType.cardTitle)
                        Text("\(candidate.dateKey) · \(candidate.statusLabel)").font(JieziFont.caption)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(scene.foreground).padding(JieziPrototypeLayout.card_inset)
        .overlay(RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius).stroke(scene.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private var expenseTimeline: some View {
        let minutes = Array(Set(model.timeline.map(\.minute))).sorted()
        let selected = selectedMinute.flatMap { value in minutes.min(by: { abs($0 - value) < abs($1 - value) }) } ?? minutes.last
        let selectedEntries = model.timeline.filter { $0.minute == selected }
        let maximum = isDrillDown ? max(model.timeline.compactMap(\.cumulativeAmount).max() ?? 0,
                                        model.timeline.compactMap(\.amount).max() ?? 0, 1) : 1
        return VStack(alignment: .leading, spacing: 12) {
            Text(isDrillDown ? "金额 · 按时间" : "时间分布").font(JieziType.cardTitle)
            if isDrillDown {
                Text("柱为单笔支出，虚线为图中支出累计；缺业务时间的记录见下方明细。")
                    .font(JieziFont.caption2).foregroundStyle(scene.muted)
            }
            if minutes.isEmpty {
                Text("暂无可读取的业务发生时间；全部记录仍可在明细查看。")
                    .font(JieziFont.caption).foregroundStyle(scene.muted)
            } else {
                Chart {
                    ForEach(model.timeline) { entry in
                        if isDrillDown {
                            if let amount = entry.amount {
                                BarMark(x: .value("业务时间", entry.minute), y: .value("单笔支出", amount), width: .fixed(8))
                                    .foregroundStyle(scene.dataAccent)
                                    .accessibilityLabel("\(clockLabel(entry.minute))，\(entry.record.title)，\(formatted(amount))")
                            }
                            if let cumulative = entry.cumulativeAmount {
                                LineMark(x: .value("业务时间", entry.minute), y: .value("已知累计", cumulative))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundStyle(scene.accent)
                            }
                        } else { PointMark(x: .value("业务时间", entry.minute), y: .value("记录", 0))
                            .symbolSize(entry.minute == selected ? 65 : 30)
                            .foregroundStyle(scene.dataAccent.opacity(entry.minute == selected ? 1 : 0.4))
                            .accessibilityLabel("\(clockLabel(entry.minute))，\(entry.record.title)")
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("选中时间", selected))
                            .foregroundStyle(scene.dataAccent.opacity(0.4))
                            .annotation(position: .top, alignment: selected < 480 ? .leading : selected > 960 ? .trailing : .center) {
                                if !dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(clockLabel(selected)) · \(selectedEntries.count)笔").font(JieziFont.caption2)
                                    ForEach(Array(selectedEntries.prefix(2))) { entry in
                                        Text("\(entry.record.title) · \(recordValue(entry.record))")
                                            .font(JieziFont.caption2).lineLimit(2)
                                    }
                                    if selectedEntries.count > 2 { Text("其余记录见下方").font(JieziFont.caption2) }
                                }
                                .foregroundStyle(scene.foreground).padding(6)
                                .frame(maxWidth: 180, alignment: .leading)
                                .background(scene.surface, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                    }
                }
                .chartXScale(domain: 0...1440)
                .chartYScale(domain: (isDrillDown ? 0.0 : -1.0)...maximum)
                .chartYAxis(isDrillDown ? .visible : .hidden)
                .chartXAxis {
                    AxisMarks(values: dynamicTypeSize.isAccessibilitySize ? [0, 720, 1440] : [0, 360, 720, 1080, 1440]) { value in
                        AxisValueLabel {
                            if let minute = value.as(Int.self) { Text(clockLabel(minute)).foregroundStyle(scene.muted) }
                        }
                    }
                }
                .chartXSelection(value: $selectedMinute)
                .frame(height: isDrillDown ? 200 : 140)
                Picker("选中业务时间", selection: Binding(
                    get: { selected ?? minutes[0] }, set: { selectedMinute = $0 }
                )) {
                    ForEach(minutes, id: \.self) { minute in Text(clockLabel(minute)).tag(minute) }
                }
                .pickerStyle(.menu)
                .tint(scene.dataAccent)
                ForEach(selectedEntries) { entry in
                    recordRow(entry.record, timeLabel: clockLabel(entry.minute))
                    Text("时间来源：\(entry.timeSourceLabel)").font(JieziFont.caption2).foregroundStyle(scene.muted)
                }
                Text("相同时间的记录分别列出；上传时间不参与分布。")
                    .font(JieziFont.caption2).foregroundStyle(scene.muted)
            }
            let missingTimeCount = model.records.filter { $0.kind == .expense && $0.transactionType != "income" }.count - model.timeline.count
            if missingTimeCount > 0 {
                Text("\(missingTimeCount)笔支出缺少有效业务时间，保留在整日记账明细中。")
                    .font(JieziFont.caption2).foregroundStyle(scene.muted)
            }
        }
        .foregroundStyle(scene.foreground)
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    private func clockLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private var previousDayComparison: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("与前一天比较").font(JieziFont.caption)
            if let current = model.knownPrimaryTotal, let previous = model.previousExpenseTotal {
                let delta = current - previous
                Text(delta == 0 ? "持平" : "\(delta > 0 ? "+" : "−")\(formatted(abs(delta)))")
                    .font(JieziType.moneyCard.monospacedDigit())
                VStack(alignment: .leading, spacing: 4) {
                    Text("前一天 \(formatted(previous))")
                    Text("当天 \(formatted(current))")
                }
                .font(JieziFont.caption.monospacedDigit())
                .foregroundStyle(scene.muted)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("金额或读取结果不完整，暂不能比较。")
                    .font(JieziFont.caption).foregroundStyle(scene.muted)
            }
        }
        .foregroundStyle(scene.foreground)
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    private var expenseComparison: some View {
        let count = model.records.filter { $0.kind == .expense && $0.transactionType != "income" }.count
        return VStack(alignment: .leading, spacing: 14) {
            Text("与前一天比较").font(JieziType.cardTitle)
            comparisonRow("金额", current: model.knownPrimaryTotal.map { formatted($0) } ?? "金额字段缺失",
                          previous: model.previousExpenseTotal.map { formatted($0) } ?? "暂不可比较")
            comparisonRow("笔数", current: "\(count)笔",
                          previous: model.previousExpenseCount.map { "\($0)笔" } ?? "暂不可比较")
            comparisonRow("最高一笔", current: model.highestExpense.map {
                "\(model.knownPrimaryTotal == nil ? "最大已知 " : "")\(recordValue($0)) · \($0.title)"
            } ?? (count == 0 ? "暂无支出" : "金额字段缺失"),
                          previous: model.previousHighestExpense.map { "\(recordValue($0)) · \($0.title)" }
                            ?? (model.previousExpenseCount == 0 ? "暂无支出" : "暂不可比较"))
        }
        .foregroundStyle(scene.foreground).padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    private func comparisonRow(_ label: String, current: String, previous: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(JieziFont.caption).foregroundStyle(scene.muted)
            Text("当天 \(current)").font(JieziType.moneyInline)
            Text("前一天 \(previous)").font(JieziFont.body)
        }.fixedSize(horizontal: false, vertical: true)
    }

    private var periodSummary: some View {
        if domain == .food {
            return metricCard("本周日均（估算）", value: model.periodDailyAverage.map { formatted($0) } ?? "暂无完整指标日",
                caption: "基于 \(model.validDayCount) 个指标完整的记录日；缺指标和未记录日不计入平均。")
        }
        return metricCard("本周累计", value: model.periodTotal.map { formatted($0) }
            ?? (model.periodRecordCount == 0 ? "暂无正式记录" : "指标字段不完整"),
            caption: "\(model.validDayCount) 个指标完整日 · 查看日期 ›")
    }

    private var foodEnergyReference: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("能量参考尺").font(JieziType.cardTitle)
            Button { showsEnergyReference = true } label: {
                Label("2,000 千卡 · 通用营养参考", systemImage: "info.circle")
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.accent)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("查看通用参考与个人需要的区别")
            if model.records.isEmpty {
                Text("记录餐食后，在这里回看已记录的食物能量。")
                    .font(JieziFont.body)
            } else if let energy = model.knownPrimaryTotal, energy.isFinite, energy >= 0 {
                Chart {
                    RuleMark(y: .value("参考尺", 0.5))
                        .foregroundStyle(scene.foreground.opacity(0.18))
                    RuleMark(x: .value("通用参考", 2_000.0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(scene.muted)
                        .accessibilityLabel("2,000 千卡通用参考，不是个人目标")
                    PointMark(x: .value("已记录食物能量", energy), y: .value("参考尺", 0.5))
                        .symbolSize(JieziPrototypeLayout.food_energy_point_size)
                        .foregroundStyle(scene.dataAccent)
                        .accessibilityLabel("已记录食物能量约 \(String(format: "%.0f", energy)) 千卡")
                }
                .chartXScale(domain: .automatic(includesZero: true))
                .chartYScale(domain: 0.0...1.0)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 4)) { value in
                        AxisTick().foregroundStyle(scene.muted)
                        AxisValueLabel {
                            if let energy = value.as(Double.self) {
                                Text(energy, format: .number.precision(.fractionLength(0)))
                                    .font(JieziFont.caption2.monospacedDigit())
                                    .foregroundStyle(scene.muted)
                            }
                        }
                    }
                }
                .frame(height: JieziPrototypeLayout.food_energy_reference_height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("能量参考尺")
                .accessibilityValue("已记录约 \(String(format: "%.0f", energy)) 千卡；2,000 千卡为通用参考，不是个人目标")
            } else {
                Text("部分餐次未提供完整估算，暂不标出总能量。")
                    .font(JieziFont.body)
            }
            Text("千卡 · 仅对应已记录餐食；未估算的餐次不按零处理。")
                .font(JieziFont.caption2)
                .foregroundStyle(scene.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(scene.foreground)
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    private func highestMealCard(_ record: NativeDayRecord) -> some View {
        Button { appState.openDayRecord(record) } label: {
            metricCard(model.knownPrimaryTotal == nil ? "最大已知一餐" : "最大一餐",
                value: recordValue(record), caption: record.title)
        }
        .buttonStyle(.plain)
    }

    private var merchantRanking: some View {
        let maximum = max(model.merchants.compactMap(\.total).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("商户排行").font(JieziType.cardTitle)
                Text("By merchant").font(JieziFont.caption2).foregroundStyle(scene.muted)
            }
            if model.merchants.isEmpty {
                Text("这一天还没有可汇总的商户记录")
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.muted)
            }
            ForEach(model.merchants) { merchant in
                Group {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(merchant.name)
                                .font(JieziFont.body)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 4)
                            Text(merchant.total.map { formatted($0) } ?? "金额字段缺失")
                                .font(JieziType.moneyInline.monospacedDigit())
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(scene.foreground.opacity(0.08))
                                if let total = merchant.total {
                                    Capsule().fill(scene.dataAccent.opacity(0.75))
                                        .frame(width: geometry.size.width * CGFloat(min(max(total / maximum, 0), 1)))
                                }
                            }
                        }
                        .frame(height: 5)
                        .accessibilityHidden(true)
                        Text(isDrillDown ? "\(merchant.records.count) 笔" : "\(merchant.records.count) 笔 · 查看整日")
                            .font(JieziFont.caption2)
                            .foregroundStyle(scene.muted)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(scene.foreground)
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    private func recordDrill(records: [NativeDayRecord]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text(model.dateKey)
                    .font(JieziFont.caption)
                    .foregroundStyle(JieziTheme.muted)
                if let message = model.stateMessage {
                    Text(message).foregroundStyle(JieziTheme.muted)
                    Button("重试读取") {
                        Task { await appState.loadRecordDateWindow(around: model.dateKey, force: true) }
                    }
                    .disabled(loadingWindow)
                } else if records.isEmpty {
                    ContentUnavailableView("这一天还没有正式记录", systemImage: "list.bullet")
                }
                ForEach(records) { record in
                    HStack(alignment: .top, spacing: 0) {
                        if domain == .food {
                            FoodRecordThumbnail(record: record, detail: detail(for: record)).padding(.top, 12)
                        }
                        NavigationLink {
                        RecordDetailView(reference: record.reference)
                    } label: {
                        recordRowContent(record, neutral: true, showsIcon: domain != .food)
                    }
                    .buttonStyle(.plain)
                    }
                }
            }
            .padding(JieziPrototypeLayout.page_inset)
        }
        .background(JieziScene.expense.surface)
    }

    @ViewBuilder
    private var recordsOrEmpty: some View {
        if model.records.isEmpty { emptyState } else { recordsCard }
    }

    private var sleepIntervals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("入睡与醒来")
                .font(JieziType.cardTitle)
            if !model.sleepRanges.isEmpty {
                Chart(model.sleepRanges) { interval in
                    BarMark(xStart: .value("入睡", interval.start), xEnd: .value("醒来", interval.end),
                            y: .value("记录", interval.id), height: .fixed(16))
                        .foregroundStyle(scene.dataAccent)
                        .cornerRadius(8)
                        .accessibilityLabel("\(sleepInterval(for: interval.record) ?? "完整睡眠区间")")
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(NativeLocalDate.timeKey(date)).foregroundStyle(scene.muted) }
                        }
                    }
                }
                .frame(height: CGFloat(max(1, model.sleepRanges.count)) * 32 + 30)
            }
            if model.sleepRanges.isEmpty {
                Text("缺少完整起止时间，区间图留空。")
                    .font(JieziFont.body).foregroundStyle(scene.muted)
            }
            Text("入睡和醒来时间见下方原始记录。")
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
        }
        .foregroundStyle(scene.foreground)
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    private var readingBooks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("这一天的书目")
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
            ForEach(model.records) { record in
                Button { appState.openDayRecord(record) } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "book.closed")
                            .font(JieziType.display)
                            .foregroundStyle(scene.accent)
                            .frame(width: 48, height: 64)
                            .background(scene.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(bookTitle(for: record))
                                .font(JieziType.cardTitle)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(recordValue(record))
                                .font(JieziType.moneyInline.monospacedDigit())
                                .foregroundStyle(scene.muted)
                            Text("整书进度未提供")
                                .font(JieziFont.caption2).foregroundStyle(scene.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(scene.foreground)
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
    }

    private var observationEntry: some View {
        Button { appState.presentedOverlay = .insights } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                Text("查看观察与月报").font(JieziType.cardTitle)
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(scene.foreground)
            .padding(JieziPrototypeLayout.card_inset)
            .frame(minHeight: 44)
            .background(scene.surface.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziPrototypeLayout.card_radius))
        }
        .buttonStyle(.plain)
    }

    private var dailyHero: some View {
        HStack(alignment: .top, spacing: 0) {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(domain == .expense ? "当日支出" : domain == .reading ? "本日书目 · Reading" : model.primaryLabel)
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
                            .font(model.secondaryValue.hasPrefix("¥") ? JieziType.moneyCard.monospacedDigit() : JieziFont.caption)
                            .foregroundStyle(model.secondaryValue.hasPrefix("¥") ? scene.accent : scene.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.75)
                    }
                    Text("\(model.records.filter(isExpense).count) 笔支出")
                        .font(JieziFont.caption2)
                        .foregroundStyle(scene.muted)
                }
            } else if domain == .reading {
                if let record = model.records.first {
                    Text(bookTitle(for: record))
                        .font(JieziType.prototypeBook)
                        .foregroundStyle(scene.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(model.records.count) 条正式阅读记录")
                        .font(JieziFont.caption).foregroundStyle(scene.muted)
                } else {
                    Text("这一天还没有阅读记录")
                        .font(JieziType.cardTitle).foregroundStyle(scene.foreground)
                }
            } else {
                nonFinancialMetric
                    .foregroundStyle(scene.foreground)
                    .minimumScaleFactor(0.8)
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
        .accessibilityLabel(heroAccessibilityLabel)
    }

    private var heroAccessibilityLabel: String {
        if domain == .reading {
            let book = model.records.first.map { bookTitle(for: $0) } ?? "暂无阅读记录"
            return "\(model.dateKey)，本日书目，\(book)，\(model.records.count) 条正式阅读记录，当日时长\(model.primaryValue)"
        }
        return "\(model.dateKey)，\(domain.title)，\(model.primaryLabel)\(model.primaryValue)，\(model.secondaryLabel)\(model.secondaryValue)"
    }

    @ViewBuilder
    private var nonFinancialMetric: some View {
        if let value = model.knownPrimaryTotal {
            let number = domain == .sleep ? JieziType.prototypeSleepHero : JieziType.prototypeHero
            let rounded = Int(value.rounded())
            if domain == .food {
                (Text("约 ").font(JieziFont.body) + Text("\(rounded)").font(number) + Text(" 千卡").font(JieziFont.body))
                    .monospacedDigit()
            } else if rounded >= 60 {
                (Text("\(rounded / 60)").font(number) + Text(" 小时 ").font(JieziFont.body)
                 + Text("\(rounded % 60)").font(number) + Text(" 分钟").font(JieziFont.body))
                    .monospacedDigit()
            } else {
                (Text("\(rounded)").font(number) + Text(" 分钟").font(JieziFont.body))
                    .monospacedDigit()
            }
        } else {
            Text(model.primaryValue)
                .font(JieziType.cardTitle)
        }
    }

    private var weeklyTrend: some View {
        let maximum = max(model.weeklyValues.compactMap(\.value).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(weekTrendTitle)
                        .font(JieziType.sectionTitle)
                        .foregroundStyle(scene.foreground)
                    Text("\(weekDates.first ?? "") – \(weekDates.last ?? "")")
                        .font(JieziFont.caption2)
                        .foregroundStyle(scene.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if !isDrillDown && (domain == .sleep || domain == .sport) {
                    NavigationLink(value: NativeDomainDrillRoute(domain: domain, dateKey: model.dateKey)) {
                        Label("查看", systemImage: "chevron.right")
                            .font(JieziFont.caption).foregroundStyle(scene.accent).frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.plain)
                } else { Menu {
                    ForEach(model.weeklyValues) { item in
                        Button { selectDate(item.dateKey) } label: {
                            Text(barAccessibilityLabel(for: item))
                        }
                    }
                } label: {
                    Label("查看", systemImage: "chevron.down")
                        .font(JieziFont.caption)
                        .foregroundStyle(scene.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("按日期查看\(domain.title)明细")
                }
            }

            if domain == .sleep { sleepWeeklyChart }
            else { HStack(alignment: .bottom, spacing: 8) {
                ForEach(model.weeklyValues) { item in
                    VStack(spacing: 7) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(barColor(for: item))
                            .frame(height: barHeight(for: item, maximum: maximum))
                        Text(item.dayLabel)
                            .font(JieziFont.caption2.monospacedDigit())
                            .foregroundStyle(item.dateKey == model.dateKey ? scene.dataAccent : scene.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 104)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(barAccessibilityLabel(for: item))
                    .accessibilityAction(named: Text("查看当天记录")) { selectDate(item.dateKey) }
                }
            }
            .padding(.top, 4)
            }
        }
        .padding(16)
        .background(scene.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var weekTrendTitle: String {
        switch domain {
        case .expense: return "本周支出"
        case .sleep: return "近七夜主要睡眠"
        case .food: return "本周估算热量"
        case .sport: return "本周运动时长"
        case .reading: return "本周阅读时长"
        }
    }

    private var sleepWeeklyChart: some View {
        Chart {
            ForEach(model.weeklyValues) { item in
                if let value = item.value {
                    BarMark(x: .value("日期", item.dateKey), y: .value("主要睡眠分钟", value))
                        .foregroundStyle(item.dateKey == model.dateKey ? scene.dataAccent : scene.dataAccent.opacity(0.5))
                        .accessibilityLabel(barAccessibilityLabel(for: item))
                }
            }
            if let median = model.sleep?.duration.median {
                RuleMark(y: .value("此前30天主要睡眠中位数", median))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(scene.foreground.opacity(0.7))
                    .accessibilityLabel("平时主要睡眠\(Int(median.rounded()))分钟")
            }
        }
        .chartXScale(domain: weekDates)
        .chartXAxis { AxisMarks(values: weekDates) { value in
            AxisValueLabel { if let day = value.as(String.self) { Text(String(day.suffix(2))).foregroundStyle(scene.muted) } }
        } }
        .frame(height: 156)
    }

    private func barHeight(for item: NativeDomainDayValue, maximum: Double) -> CGFloat {
        guard let value = item.value else { return 3 }
        return value == 0 ? 3 : max(7, CGFloat(value / maximum) * 66)
    }

    private func barColor(for item: NativeDomainDayValue) -> Color {
        guard item.value != nil else { return scene.muted.opacity(0.18) }
        return item.dateKey == model.dateKey ? scene.dataAccent : scene.dataAccent.opacity(0.42)
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
            metricCard(model.knownPrimaryTotal == nil ? "最大已知一笔" : "最大一笔",
                value: expenseAmount(for: record).map { String(format: "¥%.2f", $0) } ?? "金额不可用",
                caption: record.title)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(model.knownPrimaryTotal == nil ? "最大已知一笔" : "最大一笔")，\(record.title)，打开记录详情")
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(domain == .expense ? "收支明细" : domain == .food ? "餐次明细" : "当日记录")
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

            ForEach(isDrillDown ? model.records : Array(model.records.prefix(3))) { record in
                recordRow(record)
                if record.id != (isDrillDown ? model.records.last?.id : model.records.prefix(3).last?.id) {
                    Rectangle()
                        .fill(scene.foreground.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }
            }
            if !isDrillDown { Button { showDayRecords = true } label: {
                HStack {
                    Text("查看全部 \(model.records.count) 条记录")
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(JieziType.button)
                .foregroundStyle(scene.accent)
                .padding(16)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            }
        }
        .background(scene.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func recordRow(_ record: NativeDayRecord, timeLabel: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if domain == .food {
                FoodRecordThumbnail(record: record, detail: detail(for: record))
                    .padding(.leading, 12).padding(.top, 12)
            }
            Button { appState.openDayRecord(record) } label: {
                recordRowContent(record, timeLabel: timeLabel, showsIcon: domain != .food)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(timeLabel ?? record.timeLabel ?? "时间未提供")，\(record.title)，\(recordSecondaryText(record))，\(recordValue(record))，打开详情")
        }
    }

    private func recordRowContent(_ record: NativeDayRecord, neutral: Bool = false, timeLabel: String? = nil, showsIcon: Bool = true) -> some View {
        let rowScene = neutral ? JieziScene.expense : scene
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return rowLayout {
                Text(timeLabel ?? record.timeLabel ?? "—")
                    .font(JieziFont.caption2.monospacedDigit())
                    .foregroundStyle(rowScene.muted)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 42, alignment: .leading)
                    .padding(.top, 3)

                if showsIcon { Image(systemName: record.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(rowScene.accent)
                    .frame(width: 30, height: 30)
                    .background(rowScene.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.title)
                        .font(JieziType.cardTitle)
                        .foregroundStyle(rowScene.foreground)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                    Text(recordSecondaryText(record))
                        .font(JieziFont.caption2)
                        .foregroundStyle(rowScene.muted)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Text(recordValue(record))
                    .font(JieziType.moneyInline.monospacedDigit())
                    .foregroundStyle(rowScene.foreground)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
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

    private func bookTitle(for record: NativeDayRecord) -> String {
        guard let title = detail(for: record)?.payload?.string("book_name")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { return "书名未提供" }
        return title
    }

    private func sleepInterval(for record: NativeDayRecord) -> String? {
        guard let payload = detail(for: record)?.payload,
              let asleep = payload.string("sleep_start_at"),
              let wake = payload.string("wake_at") else { return nil }
        let start = NativeLocalDate.financeTimeKey(occurredAt: asleep) ?? asleep
        let end = NativeLocalDate.financeTimeKey(occurredAt: wake) ?? wake
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private var manualRecordSheet: some View {
        UnifiedManualRecordEntry(domain: domain)
    }
}
