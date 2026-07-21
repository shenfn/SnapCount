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
        case .domains: return "本月活跃数据域"
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
            ($0.paymentDueDay ?? 99, -$0.currentBalance) < ($1.paymentDueDay ?? 99, -$1.currentBalance)
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
            routing: NativeInboxPresentation.filtered(items, by: .routing).count,
            review: NativeInboxPresentation.filtered(items, by: .review).count
        )
    }
}
