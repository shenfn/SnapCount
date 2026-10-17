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

struct NativeDomainPageContent: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let domain: AppDomain
    let weekDates: [String]
    let details: [String: NativeRecordDetail]
    let loadingWindow: Bool
    let model: NativeDomainScenePresentation
    @State private var showManualRecordSheet = false
    @State private var selectedMerchant: MerchantSelection?
    @State private var showDayRecords = false

    private struct MerchantSelection: Identifiable { let id: String }

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

                    domainSections
                    observationEntry
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
        .sheet(item: $selectedMerchant) { selection in
            merchantDrill(id: selection.id)
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
    }

    @ViewBuilder
    private var domainSections: some View {
        switch domain {
        case .expense:
            merchantRanking
            if let highest = model.highestExpense { highestExpenseCard(highest) }
            recordsOrEmpty
        case .sleep:
            if !model.records.isEmpty { sleepIntervals }
            weeklyTrend
            recordsOrEmpty
        case .food:
            recordsOrEmpty
            metricShelf
            weeklyTrend
        case .sport:
            weeklyTrend
            metricShelf
            recordsOrEmpty
        case .reading:
            if !model.records.isEmpty { readingBooks }
            weeklyTrend
            metricShelf
            recordsOrEmpty
        }
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
                Button { selectedMerchant = MerchantSelection(id: merchant.id) } label: {
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
                        Text("\(merchant.records.count) 笔 · 查看明细")
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

    private func merchantDrill(id: String) -> some View {
        NavigationStack {
            Group {
                if let message = model.stateMessage {
                    loadStateCard(message)
                } else if let merchant = model.merchants.first(where: { $0.id == id }) {
                    recordDrill(records: merchant.records)
                        .navigationTitle(merchant.name)
                } else {
                    ContentUnavailableView("这一天已没有该商户记录", systemImage: "list.bullet")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { selectedMerchant = nil }
                }
            }
        }
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
                } else if records.isEmpty {
                    ContentUnavailableView("这一天还没有正式记录", systemImage: "list.bullet")
                }
                ForEach(records) { record in
                    NavigationLink {
                        RecordDetailView(reference: record.reference)
                    } label: {
                        recordRowContent(record, neutral: true)
                    }
                    .buttonStyle(.plain)
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
            ForEach(model.records) { record in
                Button { appState.openDayRecord(record) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(sleepInterval(for: record) ?? "区间未提供", systemImage: "moon.zzz")
                            .font(JieziFont.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recordValue(record))
                            .font(JieziType.moneyCard.monospacedDigit())
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("睡眠记录，\(sleepInterval(for: record) ?? "区间未提供")，\(recordValue(record))，打开详情")
            }
            Text("未记录完整区间时，仅显示睡眠时长。")
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
                            Text(detail(for: record)?.payload?.string("book_name") ?? "书名未提供")
                                .font(JieziType.prototypeBook)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(recordValue(record))
                                .font(JieziType.moneyInline.monospacedDigit())
                                .foregroundStyle(scene.muted)
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
                            .font(model.secondaryValue.hasPrefix("¥") ? JieziType.moneyCard.monospacedDigit() : JieziFont.caption)
                            .foregroundStyle(model.secondaryValue.hasPrefix("¥") ? scene.accent : scene.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .minimumScaleFactor(0.75)
                    }
                    Text("\(model.records.filter(isExpense).count) 笔支出")
                        .font(JieziFont.caption2)
                        .foregroundStyle(scene.muted)
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
        .accessibilityLabel("\(appState.selectedDateKey)，\(domain.title)，\(model.primaryLabel)\(model.primaryValue)，\(model.secondaryLabel)\(model.secondaryValue)")
    }

    @ViewBuilder
    private var nonFinancialMetric: some View {
        if let value = model.knownPrimaryTotal {
            let number = domain == .sleep ? JieziType.prototypeSleepHero : JieziType.prototypeHero
            let rounded = Int(value.rounded())
            if domain == .food {
                (Text("\(rounded)").font(number) + Text(" 千卡").font(JieziFont.body))
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
        case .expense, .sleep:
            return []
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
                            .foregroundStyle(item.dateKey == appState.selectedDateKey ? scene.dataAccent : scene.muted)
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
        case .sleep: return "近七夜睡眠"
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
        return item.dateKey == appState.selectedDateKey ? scene.dataAccent : scene.dataAccent.opacity(0.42)
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
                    Text(model.knownPrimaryTotal == nil ? "最大已知一笔" : "最大一笔")
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

            ForEach(Array(model.records.prefix(3))) { record in
                recordRow(record)
                if record.id != model.records.prefix(3).last?.id {
                    Rectangle()
                        .fill(scene.foreground.opacity(0.08))
                        .frame(height: 0.5)
                        .padding(.leading, 62)
                }
            }
            Button { showDayRecords = true } label: {
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
        .background(scene.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func recordRow(_ record: NativeDayRecord) -> some View {
        Button { appState.openDayRecord(record) } label: {
            recordRowContent(record)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.title)，\(recordSecondaryText(record))，\(recordValue(record))，打开详情")
    }

    private func recordRowContent(_ record: NativeDayRecord, neutral: Bool = false) -> some View {
        let rowScene = neutral ? JieziScene.expense : scene
        let rowLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return rowLayout {
                Text(record.timeLabel ?? "—")
                    .font(JieziFont.caption2.monospacedDigit())
                    .foregroundStyle(rowScene.muted)
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 42, alignment: .leading)
                    .padding(.top, 3)

                Image(systemName: record.systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(rowScene.accent)
                    .frame(width: 30, height: 30)
                    .background(rowScene.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
        let start = NativeLocalDate.financeTimeKey(occurredAt: asleep) ?? asleep
        let end = NativeLocalDate.financeTimeKey(occurredAt: wake) ?? wake
        return "\(start) – \(end)"
    }

    private func mostFrequent(_ values: [String]) -> String? {
        Dictionary(grouping: values, by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
    }

    @ViewBuilder
    private var manualRecordSheet: some View {
        UnifiedManualRecordEntry(domain: domain)
    }
}
