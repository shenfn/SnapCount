import Foundation

struct NativeDomainMetric: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct NativeDomainTrendPoint: Identifiable {
    let index: Int
    let label: String
    let value: Double
    var id: Int { index }
}

struct NativeDomainDistributionItem: Identifiable {
    let name: String
    let value: Double
    let displayValue: String
    let fraction: Double
    var id: String { name }
}

struct NativeDomainPresentation {
    let definition: NativeDomainDefinition
    let metrics: [NativeDomainMetric]
    let trend: [NativeDomainTrendPoint]
    let distribution: [NativeDomainDistributionItem]
    let recentRecords: [NativeDayRecord]
    let trendIsCurrency: Bool
    let trendScope: String
}

enum NativeDomainPresentationAdapter {
    static func presentation(for definition: NativeDomainDefinition, dashboard: DashboardSnapshot, now: Date = Date()) -> NativeDomainPresentation {
        let records = dashboard.dayRecordGroups
            .flatMap(\.records)
            .filter { ($0.domainKey ?? $0.kind.rawValue) == definition.id && $0.kind != .staging }
            .sorted { lhs, rhs in
                if lhs.dateKey == rhs.dateKey { return (lhs.timeLabel ?? "") > (rhs.timeLabel ?? "") }
                return lhs.dateKey > rhs.dateKey
            }
        let details = dashboard.recordDetails
        let isCurrency = definition.id == "expense" || definition.id == "income"

        return NativeDomainPresentation(
            definition: definition,
            metrics: metrics(for: definition, records: records, details: details, dashboard: dashboard, now: now),
            trend: weeklyTrend(for: definition, records: records, details: details, now: now),
            distribution: distribution(for: definition, records: records, details: details, currency: isCurrency),
            recentRecords: Array(records.prefix(8)),
            trendIsCurrency: isCurrency,
            trendScope: records.isEmpty ? "暂无数据" : "本周"
        )
    }

    private static func metrics(
        for definition: NativeDomainDefinition,
        records: [NativeDayRecord],
        details: [String: NativeRecordDetail],
        dashboard: DashboardSnapshot,
        now: Date
    ) -> [NativeDomainMetric] {
        if definition.id == "expense" {
            let amounts = records.compactMap { details[$0.reference]?.amount }
            return [
                NativeDomainMetric(label: "本月总额", value: currency(dashboard.monthExpense)),
                NativeDomainMetric(label: "记录数", value: "\(records.count)"),
                NativeDomainMetric(label: "今日支出", value: currency(dashboard.todayExpense)),
                NativeDomainMetric(label: "最高单笔", value: currency(amounts.max() ?? 0))
            ]
        }
        if definition.id == "income" {
            let amounts = records.compactMap { details[$0.reference]?.amount }
            return [
                NativeDomainMetric(label: "本月总额", value: currency(dashboard.monthIncome)),
                NativeDomainMetric(label: "记录数", value: "\(records.count)"),
                NativeDomainMetric(label: "月度结余", value: currency(dashboard.monthIncome - dashboard.monthExpense)),
                NativeDomainMetric(label: "最高单笔", value: currency(amounts.max() ?? 0))
            ]
        }
        return [
            NativeDomainMetric(label: "记录数", value: "\(records.count)"),
            NativeDomainMetric(label: "活跃天数", value: "\(Set(records.map(\.dateKey)).count)"),
            NativeDomainMetric(label: "模板状态", value: records.isEmpty ? "预留" : "运行中"),
            NativeDomainMetric(label: "入库链路", value: records.isEmpty ? "待接入" : "已接入")
        ]
    }

    private static func weeklyTrend(
        for definition: NativeDomainDefinition,
        records: [NativeDayRecord],
        details: [String: NativeRecordDetail],
        now: Date
    ) -> [NativeDomainTrendPoint] {
        let calendar = chinaCalendar
        let weekday = calendar.component(.weekday, from: now)
        let daysFromMonday = weekday == 1 ? 6 : weekday - 2
        guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: calendar.startOfDay(for: now)) else { return [] }
        var values = Array(repeating: 0.0, count: 7)

        for record in records {
            guard let date = dateFormatter.date(from: record.dateKey) else { continue }
            let day = calendar.dateComponents([.day], from: monday, to: calendar.startOfDay(for: date)).day ?? -1
            guard (0..<7).contains(day) else { continue }
            if definition.id == "expense" || definition.id == "income" {
                values[day] += details[record.reference]?.amount ?? amount(from: record.value)
            } else {
                values[day] += 1
            }
        }

        let labels = ["一", "二", "三", "四", "五", "六", "日"]
        return values.enumerated().map { NativeDomainTrendPoint(index: $0.offset, label: labels[$0.offset], value: $0.element) }
    }

    private static func distribution(
        for definition: NativeDomainDefinition,
        records: [NativeDayRecord],
        details: [String: NativeRecordDetail],
        currency: Bool
    ) -> [NativeDomainDistributionItem] {
        var grouped: [String: Double] = [:]
        for record in records {
            let detail = details[record.reference]
            let name = dimensionName(for: definition.id, record: record, detail: detail)
            let value = currency ? (detail?.amount ?? amount(from: record.value)) : 1
            grouped[name, default: 0] += value
        }
        let entries = grouped.sorted { $0.value > $1.value }.prefix(6)
        let maximum = entries.first?.value ?? 1
        return entries.map { name, value in
            NativeDomainDistributionItem(
                name: name,
                value: value,
                displayValue: currency ? Self.currency(value) : "\(Int(value.rounded())) 条",
                fraction: maximum > 0 ? value / maximum : 0
            )
        }
    }

    private static func dimensionName(for domainKey: String, record: NativeDayRecord, detail: NativeRecordDetail?) -> String {
        let payload = detail?.payload ?? [:]
        switch domainKey {
        case "expense": return detail?.category ?? "其他"
        case "income": return incomeCategoryLabel(detail?.category)
        case "sport": return payload.string("sport_type") ?? payload.string("activity_type") ?? payload.string("source_app") ?? record.title
        case "sleep": return payload.string("quality_level") ?? payload.string("source_app") ?? record.title
        case "reading": return payload.string("book_name") ?? payload.string("source_app") ?? record.title
        case "food": return mealLabel(payload.string("meal_type")) ?? record.title
        case "wallet": return payload.string("account_name") ?? payload.string("record_kind") ?? record.title
        default: return record.title
        }
    }

    private static func incomeCategoryLabel(_ value: String?) -> String {
        switch value {
        case "salary": return "工资"
        case "bonus": return "奖金"
        case "freelance": return "副业"
        case "investment": return "投资"
        case "reimbursement": return "报销"
        default: return "其他"
        }
    }

    private static func mealLabel(_ value: String?) -> String? {
        ["breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐", "snack": "加餐"][value ?? ""]
    }

    private static func amount(from value: String) -> Double {
        Double(value.filter { $0.isNumber || $0 == "." || $0 == "-" }) ?? 0
    }

    private static func currency(_ value: Double) -> String {
        String(format: "¥%.0f", value)
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
