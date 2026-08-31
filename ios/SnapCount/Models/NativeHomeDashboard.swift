import Foundation

enum NativeHomeWidgetKey: String, Codable, CaseIterable, Identifiable {
    case finance
    case today
    case pending
    case domains
    case daily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finance: return "财务状态"
        case .today: return "今日记录"
        case .pending: return "因缘流转"
        case .domains: return "数据域"
        case .daily: return "每日明细"
        }
    }

    var detail: String {
        switch self {
        case .finance: return "现金、欠款与收支概览"
        case .today: return "今天各数据域的记录"
        case .pending: return "待补全、待分类与识别失败"
        case .domains: return "睡眠、运动、饮食与阅读组合"
        case .daily: return "按日期浏览本月记录"
        }
    }

    var systemImage: String {
        switch self {
        case .finance: return "wallet.pass"
        case .today: return "sun.max"
        case .pending: return "arrow.triangle.2.circlepath"
        case .domains: return "square.stack.3d.up"
        case .daily: return "calendar"
        }
    }
}

struct NativeHomeWidgetConfiguration: Codable, Identifiable, Equatable {
    let key: NativeHomeWidgetKey
    var isEnabled: Bool
    var order: Int

    var id: String { key.rawValue }
}

enum NativeHomeWidgetPreferences {
    static let storageKey = "snapcount-home-widgets-v1"

    static var defaults: [NativeHomeWidgetConfiguration] {
        NativeHomeWidgetKey.allCases.enumerated().map { index, key in
            NativeHomeWidgetConfiguration(key: key, isEnabled: true, order: index)
        }
    }

    static func load(defaultsStore: UserDefaults = .standard) -> [NativeHomeWidgetConfiguration] {
        guard let data = defaultsStore.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([NativeHomeWidgetConfiguration].self, from: data) else {
            return defaults
        }
        return normalized(decoded)
    }

    static func save(_ configuration: [NativeHomeWidgetConfiguration], defaultsStore: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(normalized(configuration)) else { return }
        defaultsStore.set(data, forKey: storageKey)
    }

    static func normalized(_ configuration: [NativeHomeWidgetConfiguration]) -> [NativeHomeWidgetConfiguration] {
        var existing: [NativeHomeWidgetKey: NativeHomeWidgetConfiguration] = [:]
        configuration.sorted { $0.order < $1.order }.forEach { item in
            if existing[item.key] == nil { existing[item.key] = item }
        }

        var result = configuration
            .sorted { $0.order < $1.order }
            .compactMap { item -> NativeHomeWidgetConfiguration? in
                guard existing.removeValue(forKey: item.key) != nil else { return nil }
                return item
            }

        for fallback in defaults where existing[fallback.key] == nil && !result.contains(where: { $0.key == fallback.key }) {
            result.append(fallback)
        }

        return result.enumerated().map { index, item in
            NativeHomeWidgetConfiguration(key: item.key, isEnabled: item.isEnabled, order: index)
        }
    }
}

enum NativeHomeFinanceCardKey: String, Codable, CaseIterable, Identifiable, Hashable {
    case cashSafety
    case spendingRhythm
    case expenseStructure
    case repaymentPlan
    case accountMix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cashSafety: return "现金与还款"
        case .spendingRhythm: return "消费节奏"
        case .expenseStructure: return "月度花到哪里"
        case .repaymentPlan: return "还款准备"
        case .accountMix: return "账户覆盖"
        }
    }

    var detail: String {
        switch self {
        case .cashSafety: return "可用现金、欠款与净额"
        case .spendingRhythm: return "近 7 日支出与日均节奏"
        case .expenseStructure: return "分类占比与最高支出"
        case .repaymentPlan: return "负债账户与每月还款日"
        case .accountMix: return "资产账户与负债账户"
        }
    }

    var systemImage: String {
        switch self {
        case .cashSafety: return "shield.lefthalf.filled"
        case .spendingRhythm: return "chart.bar.xaxis"
        case .expenseStructure: return "chart.pie"
        case .repaymentPlan: return "calendar.badge.clock"
        case .accountMix: return "rectangle.3.group"
        }
    }

    var destination: NativeHomeFinanceCardDestination {
        switch self {
        case .cashSafety, .accountMix: return .accounts
        case .spendingRhythm: return .records
        case .expenseStructure: return .expenseDomain
        case .repaymentPlan: return .nearestLiability
        }
    }
}

enum NativeHomeFinanceCardDestination: Equatable {
    case accounts
    case records
    case expenseDomain
    case nearestLiability
}

struct NativeHomeFinanceCardConfiguration: Codable, Identifiable, Equatable {
    let key: NativeHomeFinanceCardKey
    var isEnabled: Bool
    var order: Int

    var id: String { key.rawValue }
}

enum NativeHomeDomainCardKey: String, Codable, CaseIterable, Identifiable, Hashable {
    case sleepRecovery
    case movementRhythm
    case foodEnergy
    case readingProgress
    case sleepSpending
    case dailyBalance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepRecovery: return "睡眠恢复"
        case .movementRhythm: return "运动节奏"
        case .foodEnergy: return "饮食能量"
        case .readingProgress: return "阅读进度"
        case .sleepSpending: return "睡眠 × 支出"
        case .dailyBalance: return "当天生活"
        }
    }

    var detail: String {
        switch self {
        case .sleepRecovery: return "睡眠时长、质量与最近记录"
        case .movementRhythm: return "运动时长、次数与类型"
        case .foodEnergy: return "热量、餐次与最近记录"
        case .readingProgress: return "阅读时长、记录次数与书籍"
        case .sleepSpending: return "有睡眠记录日的支出观察"
        case .dailyBalance: return "同一天的财务与生活记录"
        }
    }

    var systemImage: String {
        switch self {
        case .sleepRecovery: return "moon.stars"
        case .movementRhythm: return "figure.run"
        case .foodEnergy: return "fork.knife"
        case .readingProgress: return "book.closed"
        case .sleepSpending: return "moon.and.half.sun"
        case .dailyBalance: return "circle.grid.2x2"
        }
    }

    var destination: NativeHomeDomainCardDestination {
        switch self {
        case .sleepRecovery: return .domain("sleep")
        case .movementRhythm: return .domain("sport")
        case .foodEnergy: return .domain("food")
        case .readingProgress: return .domain("reading")
        case .sleepSpending: return .allDomains
        case .dailyBalance: return .selectedDay
        }
    }
}

enum NativeHomeDomainCardDestination: Equatable {
    case domain(String)
    case allDomains
    case selectedDay
}

struct NativeHomeDomainCardConfiguration: Codable, Identifiable, Equatable {
    let key: NativeHomeDomainCardKey
    var isEnabled: Bool
    var order: Int

    var id: String { key.rawValue }
}

enum NativeHomeInsightPreferences {
    static let maximumEnabledCards = 3
    private static let financeStorageKey = "snapcount-home-finance-cards-v1"
    private static let domainStorageKey = "snapcount-home-domain-cards-v1"

    static var financeDefaults: [NativeHomeFinanceCardConfiguration] {
        let enabled: Set<NativeHomeFinanceCardKey> = [.cashSafety, .spendingRhythm, .expenseStructure]
        return NativeHomeFinanceCardKey.allCases.enumerated().map { index, key in
            NativeHomeFinanceCardConfiguration(key: key, isEnabled: enabled.contains(key), order: index)
        }
    }

    static var domainDefaults: [NativeHomeDomainCardConfiguration] {
        let enabled: Set<NativeHomeDomainCardKey> = [.sleepRecovery, .foodEnergy, .sleepSpending]
        return NativeHomeDomainCardKey.allCases.enumerated().map { index, key in
            NativeHomeDomainCardConfiguration(key: key, isEnabled: enabled.contains(key), order: index)
        }
    }

    static func loadFinance(defaultsStore: UserDefaults = .standard) -> [NativeHomeFinanceCardConfiguration] {
        guard let data = defaultsStore.data(forKey: financeStorageKey),
              let decoded = try? JSONDecoder().decode([NativeHomeFinanceCardConfiguration].self, from: data) else {
            return financeDefaults
        }
        return normalizedFinance(decoded)
    }

    static func loadDomains(defaultsStore: UserDefaults = .standard) -> [NativeHomeDomainCardConfiguration] {
        guard let data = defaultsStore.data(forKey: domainStorageKey),
              let decoded = try? JSONDecoder().decode([NativeHomeDomainCardConfiguration].self, from: data) else {
            return domainDefaults
        }
        return normalizedDomains(decoded)
    }

    static func saveFinance(_ configuration: [NativeHomeFinanceCardConfiguration], defaultsStore: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(normalizedFinance(configuration)) else { return }
        defaultsStore.set(data, forKey: financeStorageKey)
    }

    static func saveDomains(_ configuration: [NativeHomeDomainCardConfiguration], defaultsStore: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(normalizedDomains(configuration)) else { return }
        defaultsStore.set(data, forKey: domainStorageKey)
    }

    static func normalizedFinance(_ configuration: [NativeHomeFinanceCardConfiguration]) -> [NativeHomeFinanceCardConfiguration] {
        var existing: [NativeHomeFinanceCardKey: NativeHomeFinanceCardConfiguration] = [:]
        configuration.sorted { $0.order < $1.order }.forEach { item in
            if existing[item.key] == nil { existing[item.key] = item }
        }
        var result = configuration.sorted { $0.order < $1.order }.compactMap { item -> NativeHomeFinanceCardConfiguration? in
            guard existing.removeValue(forKey: item.key) != nil else { return nil }
            return item
        }
        for fallback in financeDefaults where existing[fallback.key] == nil && !result.contains(where: { $0.key == fallback.key }) {
            result.append(fallback)
        }
        var enabledCount = 0
        return result.enumerated().map { index, item in
            let isEnabled = item.isEnabled && enabledCount < maximumEnabledCards
            if isEnabled { enabledCount += 1 }
            return NativeHomeFinanceCardConfiguration(key: item.key, isEnabled: isEnabled, order: index)
        }
    }

    static func normalizedDomains(_ configuration: [NativeHomeDomainCardConfiguration]) -> [NativeHomeDomainCardConfiguration] {
        var existing: [NativeHomeDomainCardKey: NativeHomeDomainCardConfiguration] = [:]
        configuration.sorted { $0.order < $1.order }.forEach { item in
            if existing[item.key] == nil { existing[item.key] = item }
        }
        var result = configuration.sorted { $0.order < $1.order }.compactMap { item -> NativeHomeDomainCardConfiguration? in
            guard existing.removeValue(forKey: item.key) != nil else { return nil }
            return item
        }
        for fallback in domainDefaults where existing[fallback.key] == nil && !result.contains(where: { $0.key == fallback.key }) {
            result.append(fallback)
        }
        var enabledCount = 0
        return result.enumerated().map { index, item in
            let isEnabled = item.isEnabled && enabledCount < maximumEnabledCards
            if isEnabled { enabledCount += 1 }
            return NativeHomeDomainCardConfiguration(key: item.key, isEnabled: isEnabled, order: index)
        }
    }

    static func updatingFinance(
        _ configuration: [NativeHomeFinanceCardConfiguration],
        key: NativeHomeFinanceCardKey,
        isEnabled: Bool
    ) -> [NativeHomeFinanceCardConfiguration] {
        let normalized = normalizedFinance(configuration)
        guard let index = normalized.firstIndex(where: { $0.key == key }) else { return normalized }
        if isEnabled,
           !normalized[index].isEnabled,
           normalized.filter(\.isEnabled).count >= maximumEnabledCards {
            return normalized
        }
        var updated = normalized
        updated[index].isEnabled = isEnabled
        return updated
    }

    static func updatingDomain(
        _ configuration: [NativeHomeDomainCardConfiguration],
        key: NativeHomeDomainCardKey,
        isEnabled: Bool
    ) -> [NativeHomeDomainCardConfiguration] {
        let normalized = normalizedDomains(configuration)
        guard let index = normalized.firstIndex(where: { $0.key == key }) else { return normalized }
        if isEnabled,
           !normalized[index].isEnabled,
           normalized.filter(\.isEnabled).count >= maximumEnabledCards {
            return normalized
        }
        var updated = normalized
        updated[index].isEnabled = isEnabled
        return updated
    }
}

struct NativeHomeExpenseCategory: Identifiable, Equatable {
    let name: String
    let amount: Double

    var id: String { name }
}

struct NativeHomeSleepSpendingObservation: Equatable {
    let sleepDays: Int
    let sleepDayTotal: Double
    let sleepDayAverage: Double
    let allDayAverage: Double
}

enum NativeHomeInsightAnalytics {
    static func dailySummaries(from snapshot: DashboardSnapshot) -> [NativeDailySummary] {
        guard !snapshot.dayRecordGroups.isEmpty else {
            return snapshot.dailySummaries.sorted { $0.dateKey > $1.dateKey }
        }

        return snapshot.dayRecordGroups
            .sorted { $0.dateKey > $1.dateKey }
            .map { group in
                NativeDailySummary(
                    dateKey: group.dateKey,
                    expense: amountTotal(in: group.records, kind: .expense, snapshot: snapshot),
                    income: amountTotal(in: group.records, kind: .income, snapshot: snapshot),
                    pendingCount: group.records.filter {
                        $0.kind == .staging || isPendingExpense($0, snapshot: snapshot)
                    }.count,
                    recordCount: group.records.count
                )
            }
    }

    static func dailySummary(on dateKey: String, from snapshot: DashboardSnapshot) -> NativeDailySummary {
        dailySummaries(from: snapshot).first(where: { $0.dateKey == dateKey })
            ?? NativeDailySummary(dateKey: dateKey, expense: 0, income: 0, pendingCount: 0, recordCount: 0)
    }

    static func monthKeysForRecentWindow(endingAt dateKey: String, dayCount: Int = 7) -> [String] {
        guard dayCount > 0, let endDate = dateFormatter.date(from: dateKey) else { return [] }
        var monthKeys: [String] = []
        for offset in 0..<dayCount {
            guard let date = chinaCalendar.date(byAdding: .day, value: -offset, to: endDate) else { continue }
            let key = String(dateFormatter.string(from: date).prefix(7))
            if !monthKeys.contains(key) { monthKeys.append(key) }
        }
        return monthKeys
    }

    static func combining(_ snapshots: [DashboardSnapshot]) -> DashboardSnapshot {
        var recordsByDate: [String: [String: NativeDayRecord]] = [:]
        var details: [String: NativeRecordDetail] = [:]

        for snapshot in snapshots {
            for group in snapshot.dayRecordGroups {
                for record in group.records {
                    recordsByDate[group.dateKey, default: [:]][record.id] = record
                }
            }
            for (reference, detail) in snapshot.recordDetails {
                details[reference] = detail
            }
        }

        var combined = DashboardSnapshot()
        combined.dayRecordGroups = recordsByDate.map { dateKey, records in
            NativeDayRecordGroup(
                dateKey: dateKey,
                records: records.values.sorted { ($0.timeLabel ?? "") > ($1.timeLabel ?? "") }
            )
        }.sorted { $0.dateKey > $1.dateKey }
        combined.recordDetails = details
        combined.domains = snapshots.first(where: { !$0.domains.isEmpty })?.domains ?? []
        return combined
    }

    static func recentDailySummaries(
        from snapshot: DashboardSnapshot,
        endingAt dateKey: String,
        dayCount: Int = 7
    ) -> [NativeDailySummary] {
        guard dayCount > 0, let endDate = dateFormatter.date(from: dateKey) else { return [] }
        let calendar = chinaCalendar
        let summaries = Dictionary(uniqueKeysWithValues: dailySummaries(from: snapshot).map { ($0.dateKey, $0) })
        return (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - (dayCount - 1), to: endDate) else { return nil }
            let key = dateFormatter.string(from: date)
            return summaries[key] ?? NativeDailySummary(dateKey: key, expense: 0, income: 0, pendingCount: 0, recordCount: 0)
        }
    }

    static func expenseBreakdown(from snapshot: DashboardSnapshot) -> [NativeHomeExpenseCategory] {
        var totals: [String: Double] = [:]
        for record in snapshot.dayRecordGroups.flatMap(\.records) where record.kind == .expense {
            let detail = detail(for: record, snapshot: snapshot)
            guard isConfirmedExpense(record, snapshot: snapshot) else { continue }
            let rawCategory = detail?.category?.isEmpty == false ? detail?.category ?? "其他" : "其他"
            let category = NativeFinanceOptionCatalog.categoryTitle(for: rawCategory) ?? rawCategory
            totals[category, default: 0] += amount(for: record, detail: detail)
        }
        return totals
            .map { NativeHomeExpenseCategory(name: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    static func confirmedExpenseTotal(from snapshot: DashboardSnapshot) -> Double {
        snapshot.dayRecordGroups.flatMap(\.records).reduce(0) { total, record in
            guard record.kind == .expense, isConfirmedExpense(record, snapshot: snapshot) else { return total }
            return total + amount(for: record, detail: detail(for: record, snapshot: snapshot))
        }
    }

    static func hasHydratedExpenseDetails(in snapshot: DashboardSnapshot) -> Bool {
        let records = snapshot.dayRecordGroups.flatMap(\.records).filter {
            $0.kind == .expense && isConfirmedExpense($0, snapshot: snapshot)
        }
        return records.isEmpty || records.allSatisfy { detail(for: $0, snapshot: snapshot) != nil }
    }

    static func domainRecords(_ domainKey: String, from snapshot: DashboardSnapshot) -> [NativeDayRecord] {
        snapshot.dayRecordGroups
            .flatMap(\.records)
            .filter { ($0.domainKey ?? $0.kind.rawValue) == domainKey && $0.kind != .staging }
    }

    static func hasHydratedDetails(for domainKey: String, in snapshot: DashboardSnapshot) -> Bool {
        let records = domainRecords(domainKey, from: snapshot)
        let metricKeys: [String]
        switch domainKey {
        case "sleep":
            metricKeys = ["sleep_minutes", "duration_minutes", "sleep_hours", "duration_hours"]
        case "sport":
            metricKeys = ["duration_minutes"]
        case "reading":
            metricKeys = ["reading_minutes", "duration_minutes", "reading_hours"]
        case "food":
            metricKeys = ["total_calorie_kcal", "calories", "calories_kcal"]
        default:
            metricKeys = []
        }
        return records.isEmpty || records.allSatisfy { record in
            guard let payload = detail(for: record, snapshot: snapshot)?.payload else { return false }
            return metricKeys.isEmpty || metricKeys.contains { payload.double($0) != nil }
        }
    }

    static func sleepSpendingObservation(from snapshot: DashboardSnapshot) -> NativeHomeSleepSpendingObservation {
        let sleepDays = Set(domainRecords("sleep", from: snapshot).map(\.dateKey))
        let expenseByDay = Dictionary(
            grouping: snapshot.dayRecordGroups.flatMap(\.records).filter {
                $0.kind == .expense && isConfirmedExpense($0, snapshot: snapshot)
            },
            by: \.dateKey
        )
            .mapValues { records in
                records.reduce(0) { total, record in
                    total + amount(for: record, detail: detail(for: record, snapshot: snapshot))
                }
            }
        let sleepDayTotal = sleepDays.reduce(0) { $0 + (expenseByDay[$1] ?? 0) }
        let allDays = Set(
            snapshot.dayRecordGroups.flatMap(\.records).filter {
                $0.kind != .staging && ($0.kind != .expense || isConfirmedExpense($0, snapshot: snapshot))
            }.map(\.dateKey)
        )
        let allDayTotal = allDays.reduce(0) { $0 + (expenseByDay[$1] ?? 0) }
        return NativeHomeSleepSpendingObservation(
            sleepDays: sleepDays.count,
            sleepDayTotal: sleepDayTotal,
            sleepDayAverage: sleepDays.isEmpty ? 0 : sleepDayTotal / Double(sleepDays.count),
            allDayAverage: allDays.isEmpty ? 0 : allDayTotal / Double(allDays.count)
        )
    }

    static func recordCount(on dateKey: String, in snapshot: DashboardSnapshot) -> Int {
        snapshot.dayRecordGroups.first(where: { $0.dateKey == dateKey })?.records.filter { $0.kind != .staging }.count ?? 0
    }

    private static func amountTotal(
        in records: [NativeDayRecord],
        kind: NativeDayRecordKind,
        snapshot: DashboardSnapshot
    ) -> Double {
        records.filter {
            $0.kind == kind && (kind != .expense || isConfirmedExpense($0, snapshot: snapshot))
        }.reduce(0) { total, record in
            total + amount(for: record, detail: detail(for: record, snapshot: snapshot))
        }
    }

    private static func isConfirmedExpense(_ record: NativeDayRecord, snapshot: DashboardSnapshot) -> Bool {
        guard record.kind == .expense else { return true }
        if let transactionType = record.transactionType, transactionType != "expense" {
            return false
        }
        if let status = record.status ?? detail(for: record, snapshot: snapshot)?.status {
            // Local GRDB facts are already committed user records. They use
            // `local` until the cloud acknowledges their outbox operation,
            // but must still count in the same home-day aggregates.
            return status == "done" || status == "local"
        }
        return record.systemImage != "clock"
    }

    private static func isPendingExpense(_ record: NativeDayRecord, snapshot: DashboardSnapshot) -> Bool {
        guard record.kind == .expense else { return false }
        if let status = record.status ?? detail(for: record, snapshot: snapshot)?.status {
            return status == "pending"
        }
        return record.systemImage == "clock"
    }

    private static func amount(for record: NativeDayRecord, detail: NativeRecordDetail?) -> Double {
        detail?.amount ?? Double(
            record.value
                .replacingOccurrences(of: "¥", with: "")
                .replacingOccurrences(of: "+", with: "")
                .replacingOccurrences(of: ",", with: "")
        ) ?? 0
    }

    private static func detail(for record: NativeDayRecord, snapshot: DashboardSnapshot) -> NativeRecordDetail? {
        snapshot.recordDetails[record.reference]
            ?? snapshot.recordDetails[NativeRecordReference(record.reference).canonicalValue]
    }

    private static var chinaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct NativeHomeFinanceSummary {
    let availableCash: Double
    let liabilityTotal: Double
    let netWorthEstimate: Double
    let nearestLiability: NativeAccount?
    let dayExpense: Double
    let dayIncome: Double

    var statusLabel: String {
        if availableCash == 0, liabilityTotal == 0 { return "缺少钱包快照" }
        if netWorthEstimate < 0 { return "待还压力偏高" }
        if liabilityTotal > availableCash * 0.5 { return "近期需预留还款" }
        return "短期现金安全"
    }

    static func make(
        accounts: [NativeAccount],
        dayExpense: Double,
        dayIncome: Double
    ) -> NativeHomeFinanceSummary {
        let activeAccounts = accounts.filter { !$0.isArchived }
        let availableCash = activeAccounts
            .filter { !$0.type.isLiability }
            .reduce(0) { $0 + $1.currentBalance }
        let liabilityAccounts = activeAccounts.filter { $0.type.isLiability && $0.currentBalance > 0 }
        let liabilityTotal = liabilityAccounts.reduce(0) { $0 + $1.currentBalance }
        let nearestLiability = liabilityAccounts.sorted {
            if $0.currentBalance == $1.currentBalance {
                return ($0.paymentDueDay ?? 99) < ($1.paymentDueDay ?? 99)
            }
            return $0.currentBalance > $1.currentBalance
        }.first

        return NativeHomeFinanceSummary(
            availableCash: availableCash,
            liabilityTotal: liabilityTotal,
            netWorthEstimate: availableCash - liabilityTotal,
            nearestLiability: nearestLiability,
            dayExpense: dayExpense,
            dayIncome: dayIncome
        )
    }
}

struct NativeHomePendingSummary {
    let total: Int
    let pendingExpenses: Int
    let failed: Int
    let repair: Int
    let routing: Int
    let review: Int

    static func make(dashboard: DashboardSnapshot) -> NativeHomePendingSummary {
        let items = NativeInboxPresentation.items(
            pendingExpenses: dashboard.pendingExpenses,
            stagingRecords: dashboard.stagingRecords
        )
        return NativeHomePendingSummary(
            total: items.count,
            pendingExpenses: NativeInboxPresentation.filtered(items, by: .pendingExpense).count,
            failed: NativeInboxPresentation.filtered(items, by: .failed).count,
            repair: NativeInboxPresentation.filtered(items, by: .repair).count,
            routing: NativeInboxPresentation.filtered(items, by: .routing).count,
            review: NativeInboxPresentation.filtered(items, by: .review).count
        )
    }
}
