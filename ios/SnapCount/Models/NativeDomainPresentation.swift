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
        let isCurrency = definition.id == "expense" || definition.id == "income" || definition.id == "wallet"
        let primaryFact = primaryFact(for: definition)
        let primaryDimension = primaryDimension(for: definition)

        return NativeDomainPresentation(
            definition: definition,
            metrics: metrics(for: definition, records: records, details: details, dashboard: dashboard, fact: primaryFact),
            trend: weeklyTrend(for: definition, records: records, details: details, fact: primaryFact, now: now),
            distribution: distribution(for: definition, records: records, details: details, fact: primaryFact, dimension: primaryDimension, currency: isCurrency),
            recentRecords: records.prefix(8).map { recentRecord($0, details: details, fact: primaryFact, currency: isCurrency) },
            trendIsCurrency: isCurrency,
            trendScope: records.isEmpty ? "模板预览" : "本周"
        )
    }

    private static func metrics(
        for definition: NativeDomainDefinition,
        records: [NativeDayRecord],
        details: [String: NativeRecordDetail],
        dashboard: DashboardSnapshot,
        fact: DomainField?
    ) -> [NativeDomainMetric] {
        if definition.id == "expense" {
            let amounts = records.compactMap { detail(for: $0, in: details)?.amount }
            return [
                NativeDomainMetric(label: "本月总额", value: currency(dashboard.monthExpense)),
                NativeDomainMetric(label: "记录数", value: "\(records.count)"),
                NativeDomainMetric(label: "今日支出", value: currency(dashboard.todayExpense)),
                NativeDomainMetric(label: "最高单笔", value: currency(amounts.max() ?? 0))
            ]
        }
        if definition.id == "income" {
            let amounts = records.compactMap { detail(for: $0, in: details)?.amount }
            return [
                NativeDomainMetric(label: "本月总额", value: currency(dashboard.monthIncome)),
                NativeDomainMetric(label: "记录数", value: "\(records.count)"),
                NativeDomainMetric(label: "月度结余", value: currency(dashboard.monthIncome - dashboard.monthExpense)),
                NativeDomainMetric(label: "最高单笔", value: currency(amounts.max() ?? 0))
            ]
        }
        guard let fact, !records.isEmpty else {
            return [
                NativeDomainMetric(label: "本月记录", value: "\(records.count)"),
                NativeDomainMetric(label: "历史记录", value: "\(definition.recordCount)"),
                NativeDomainMetric(label: "入库链路", value: definition.recordCount > 0 ? "已接入" : "待接入"),
                NativeDomainMetric(label: "展示组件", value: "已就绪")
            ]
        }
        let values = records.map { factValue(for: $0, details: details, fact: fact, domainKey: definition.id) }
        let total = values.reduce(0, +)
        let maximum = values.max() ?? 0
        let average = values.isEmpty ? 0 : total / Double(values.count)
        return [
            NativeDomainMetric(label: "本月总\(fact.label)", value: formatFact(total, fact: fact, currency: definition.id == "wallet")),
            NativeDomainMetric(label: "本月记录", value: "\(records.count)"),
            NativeDomainMetric(label: "最高单次", value: formatFact(maximum, fact: fact, currency: definition.id == "wallet")),
            NativeDomainMetric(label: "平均", value: formatFact(average, fact: fact, currency: definition.id == "wallet"))
        ]
    }

    private static func weeklyTrend(
        for definition: NativeDomainDefinition,
        records: [NativeDayRecord],
        details: [String: NativeRecordDetail],
        fact: DomainField?,
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
                values[day] += detail(for: record, in: details)?.amount ?? amount(from: record.value)
            } else if let fact {
                values[day] += factValue(for: record, details: details, fact: fact, domainKey: definition.id)
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
        fact: DomainField?,
        dimension: DomainField?,
        currency: Bool
    ) -> [NativeDomainDistributionItem] {
        var grouped: [String: Double] = [:]
        for record in records {
            let detail = detail(for: record, in: details)
            let name = dimension.map { dimensionValue($0, domainKey: definition.id, record: record, detail: detail) }
                ?? dimensionName(for: definition.id, record: record, detail: detail)
            let value: Double
            if definition.id == "expense" || definition.id == "income" {
                value = detail?.amount ?? amount(from: record.value)
            } else if let fact {
                value = factValue(for: record, details: details, fact: fact, domainKey: definition.id)
            } else {
                value = 1
            }
            grouped[name, default: 0] += value
        }
        let entries = grouped.sorted { $0.value > $1.value }.prefix(6)
        let maximum = entries.first?.value ?? 1
        return entries.map { name, value in
            NativeDomainDistributionItem(
                name: name,
                value: value,
                displayValue: fact.map { formatFact(value, fact: $0, currency: currency) }
                    ?? (currency ? Self.currency(value) : "\(Int(value.rounded())) 条"),
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

    private struct DomainField {
        let key: String
        let label: String
        let unit: String
        let isDuration: Bool
    }

    private static func primaryFact(for definition: NativeDomainDefinition) -> DomainField? {
        schemaField(
            definition: definition,
            group: "facts",
            preferredKey: definition.display.string("primary_fact")
        ) ?? fallbackFact(for: definition.id)
    }

    private static func primaryDimension(for definition: NativeDomainDefinition) -> DomainField? {
        schemaField(
            definition: definition,
            group: "dimensions",
            preferredKey: definition.display.string("primary_dimension")
        ) ?? fallbackDimension(for: definition.id)
    }

    private static func schemaField(
        definition: NativeDomainDefinition,
        group: String,
        preferredKey: String?
    ) -> DomainField? {
        guard let values = definition.schema[group]?.value as? [Any] else { return nil }
        let fields = values.compactMap { $0 as? [String: Any] }
        guard let raw = preferredKey.flatMap({ key in fields.first { $0["key"] as? String == key } }) ?? fields.first,
              let key = raw["key"] as? String else { return nil }
        let label = raw["label"] as? String ?? key
        let unit = raw["unit"] as? String ?? ""
        let input = raw["input"] as? String ?? ""
        return DomainField(
            key: key,
            label: label,
            unit: unit,
            isDuration: input == "duration" || key.contains("minutes") || unit == "分钟" || unit == "小时"
        )
    }

    private static func fallbackFact(for domainKey: String) -> DomainField? {
        switch domainKey {
        case "sport": return DomainField(key: "duration_minutes", label: "运动时长", unit: "分钟", isDuration: true)
        case "sleep": return DomainField(key: "sleep_minutes", label: "睡眠时长", unit: "分钟", isDuration: true)
        case "reading": return DomainField(key: "reading_minutes", label: "阅读时长", unit: "分钟", isDuration: true)
        case "food": return DomainField(key: "total_calorie_kcal", label: "总热量", unit: "千卡", isDuration: false)
        case "wallet": return DomainField(key: "amount", label: "金额", unit: "元", isDuration: false)
        default: return nil
        }
    }

    private static func fallbackDimension(for domainKey: String) -> DomainField? {
        switch domainKey {
        case "sport": return DomainField(key: "sport_type", label: "运动类型", unit: "", isDuration: false)
        case "sleep": return DomainField(key: "quality_level", label: "质量等级", unit: "", isDuration: false)
        case "reading": return DomainField(key: "book_name", label: "书名", unit: "", isDuration: false)
        case "food": return DomainField(key: "meal_type", label: "餐次", unit: "", isDuration: false)
        case "wallet": return DomainField(key: "account_name", label: "账户/平台", unit: "", isDuration: false)
        default: return nil
        }
    }

    private static func factValue(
        for record: NativeDayRecord,
        details: [String: NativeRecordDetail],
        fact: DomainField,
        domainKey: String
    ) -> Double {
        let payload = detail(for: record, in: details)?.payload ?? [:]
        switch fact.key {
        case "sleep_minutes":
            return payload.double("sleep_minutes")
                ?? payload.double("duration_minutes")
                ?? payload.double("sleep_hours").map { $0 * 60 }
                ?? payload.double("duration_hours").map { $0 * 60 }
                ?? 0
        case "reading_minutes":
            return payload.double("reading_minutes")
                ?? payload.double("duration_minutes")
                ?? payload.double("reading_hours").map { $0 * 60 }
                ?? 0
        case "calories":
            return payload.double("calories") ?? payload.double("calories_kcal") ?? 0
        case "amount" where domainKey == "wallet":
            return payload.double("amount") ?? payload.double("snapshot_balance") ?? payload.double("current_balance") ?? 0
        default:
            return payload.double(fact.key) ?? 0
        }
    }

    private static func dimensionValue(
        _ dimension: DomainField,
        domainKey: String,
        record: NativeDayRecord,
        detail: NativeRecordDetail?
    ) -> String {
        let raw = detail?.payload?.string(dimension.key)
            ?? dimensionName(for: domainKey, record: record, detail: detail)
        return domainKey == "food" ? mealLabel(raw) ?? raw : raw
    }

    private static func recentRecord(
        _ record: NativeDayRecord,
        details: [String: NativeRecordDetail],
        fact: DomainField?,
        currency: Bool
    ) -> NativeDayRecord {
        guard record.kind != .expense, record.kind != .income, let fact else { return record }
        let value = factValue(for: record, details: details, fact: fact, domainKey: record.domainKey ?? record.kind.rawValue)
        return NativeDayRecord(
            id: record.id,
            reference: record.reference,
            dateKey: record.dateKey,
            kind: record.kind,
            domainKey: record.domainKey,
            title: record.title,
            subtitle: record.subtitle,
            value: formatFact(value, fact: fact, currency: currency),
            timeLabel: record.timeLabel,
            systemImage: record.systemImage
        )
    }

    private static func detail(
        for record: NativeDayRecord,
        in details: [String: NativeRecordDetail]
    ) -> NativeRecordDetail? {
        details[record.reference]
            ?? details[NativeRecordReference(record.reference).canonicalValue]
    }

    private static func formatFact(_ value: Double, fact: DomainField, currency: Bool) -> String {
        if fact.isDuration {
            let minutes = Int(value.rounded())
            return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
        }
        if currency || fact.unit == "元" { return String(format: "¥%.2f", value) }
        let number = value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
        return fact.unit.isEmpty ? number : "\(number) \(fact.unit)"
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
