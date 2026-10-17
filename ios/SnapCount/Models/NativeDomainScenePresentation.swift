import Foundation
import os

struct NativeDomainDayValue: Identifiable {
    let dateKey: String
    let value: Double?
    let recordCount: Int

    var id: String { dateKey }
    var dayLabel: String { String(dateKey.suffix(2)) }
}

struct NativeMerchantSummary: Identifiable {
    let name: String
    let total: Double?
    let records: [NativeDayRecord]
    var id: String { name }
}

struct NativeTimelineEntry: Identifiable {
    let record: NativeDayRecord
    let minute: Int
    var id: String { record.reference }
}

struct NativeSleepInterval: Identifiable {
    let record: NativeDayRecord
    let start: Date
    let end: Date
    var id: String { record.reference }
}

struct NativeDomainScenePresentation {
    private static let signposter = OSSignposter(subsystem: "com.jiezi.app", category: "DomainScene")
    let dateKey: String
    let records: [NativeDayRecord]
    let weeklyValues: [NativeDomainDayValue]
    let primaryLabel: String
    let primaryValue: String
    let secondaryLabel: String
    let secondaryValue: String
    let measurementNote: String?
    let highestExpense: NativeDayRecord?
    let knownPrimaryTotal: Double?
    let stateMessage: String?
    let merchants: [NativeMerchantSummary]

    let timeline: [NativeTimelineEntry]
    let sleepRanges: [NativeSleepInterval]
    let periodTypes: [String]
    let highestMeal: NativeDayRecord?
    let previousExpenseTotal: Double?

    var periodRecordCount: Int { weeklyValues.reduce(0) { $0 + $1.recordCount } }
    var validDayCount: Int { weeklyValues.filter { $0.recordCount > 0 && $0.value != nil }.count }
    var periodTotal: Double? {
        let recordedDays = weeklyValues.filter { $0.recordCount > 0 }
        guard !recordedDays.isEmpty, recordedDays.allSatisfy({ $0.value != nil }) else { return nil }
        return recordedDays.compactMap(\.value).reduce(0, +)
    }
    var periodDailyAverage: Double? {
        let values = weeklyValues.filter { $0.recordCount > 0 }.compactMap(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func trendDateKeys(for domain: AppDomain, dateKey: String) -> [String] {
        switch domain {
        case .sleep:
            return (-6...0).compactMap { NativeLocalDate.shiftedDateKey(dateKey, byDays: $0) }
        case .expense, .food, .sport, .reading:
            return NativeLocalDate.weekDateKeys(containing: dateKey)
        }
    }

    static func make(
        domain: AppDomain,
        dateKey: String,
        weekGroups: [NativeDayRecordGroup],
        details: [String: NativeRecordDetail],
        isSignedIn: Bool,
        isLoading: Bool,
        errorMessage: String?,
        todayKey: String = NativeLocalDate.dateKey(Date())
    ) -> Self {
        let interval = signposter.beginInterval("BuildDomainPresentation", id: signposter.makeSignpostID())
        defer { signposter.endInterval("BuildDomainPresentation", interval) }
        let allRecords = weekGroups.flatMap(\.records).filter(NativeRecordQuery.isFormal)
        let dayRecords = allRecords.filter { $0.dateKey == dateKey }
        let records: [NativeDayRecord]
        switch domain {
        case .expense:
            records = dayRecords.filter { isExpense($0) || isIncome($0) }
        case .sleep, .food, .sport, .reading:
            records = dayRecords.filter { ($0.domainKey ?? $0.kind.rawValue) == domain.rawValue }
        }

        let primaryKey = measurementKey(for: domain)
        let primaryValues = records.compactMap { record in
            measurement(for: record, key: primaryKey, details: details)?.value
        }
        let missingPrimaryCount = max(0, records.count - primaryValues.count)
        let primaryTotal = records.isEmpty || missingPrimaryCount > 0 ? nil : primaryValues.reduce(0, +)

        let primaryLabel: String
        let primaryValue: String
        let secondaryLabel: String
        let secondaryValue: String
        let note: String?
        var highest: NativeDayRecord?
        var knownPrimaryTotal = primaryTotal

        switch domain {
        case .expense:
            primaryLabel = "支出"
            let expenseRecords = records.filter(isExpense)
            let expenseValues = expenseRecords.compactMap { record in expenseAmount(for: record, details: details) }
            let missingExpenseCount = max(0, expenseRecords.count - expenseValues.count)
            knownPrimaryTotal = missingExpenseCount == 0 ? expenseValues.reduce(0, +) : nil
            primaryValue = expenseRecords.isEmpty ? "¥0.00" : knownPrimaryTotal.map(currency) ?? "金额字段缺失"
            let incomeRecords = dayRecords.filter(isIncome)
            let incomeValues = incomeRecords.compactMap { expenseAmount(for: $0, details: details) }
            let missingIncomeCount = max(0, incomeRecords.count - incomeValues.count)
            secondaryLabel = "收入"
            if !isSignedIn {
                secondaryValue = "本地暂不可读取"
            } else if missingIncomeCount > 0 {
                secondaryValue = "金额字段缺失"
            } else {
                secondaryValue = currency(incomeValues.reduce(0, +))
            }
            if missingExpenseCount > 0 {
                note = "\(missingExpenseCount) 条支出记录未提供可读取金额"
            } else {
                note = nil
            }
            if let recordAmount = expenseRecords.compactMap({ record -> (NativeDayRecord, Double)? in
                guard let amount = expenseAmount(for: record, details: details) else { return nil }
                return (record, amount)
            }).max(by: { $0.1 < $1.1 }) {
                highest = recordAmount.0
            }
        case .sleep:
            primaryLabel = "睡眠时长"
            primaryValue = measurementText(total: primaryTotal, recordCount: records.count, missingCount: missingPrimaryCount, empty: "暂无睡眠记录", unit: .duration)
            secondaryLabel = "记录数"
            secondaryValue = "\(records.count) 条"
            note = missingPrimaryCount > 0 ? "\(missingPrimaryCount) 条记录未提供睡眠时长" : (primaryTotal == nil ? nil : "按记录中的实际业务日期统计")
        case .food:
            primaryLabel = "估算热量"
            primaryValue = measurementText(total: primaryTotal, recordCount: records.count, missingCount: missingPrimaryCount, empty: "暂无饮食记录", unit: .calories)
            secondaryLabel = "餐次"
            secondaryValue = "\(records.count) 餐"
            note = missingPrimaryCount > 0 ? "\(missingPrimaryCount) 餐未提供热量估算" : (primaryTotal == nil ? nil : "热量为记录中的估算值")
        case .sport:
            primaryLabel = "运动时长"
            primaryValue = measurementText(total: primaryTotal, recordCount: records.count, missingCount: missingPrimaryCount, empty: "暂无运动记录", unit: .duration)
            secondaryLabel = "运动次数"
            secondaryValue = "\(records.count) 次"
            note = missingPrimaryCount > 0 ? "\(missingPrimaryCount) 条记录未提供运动时长" : nil
        case .reading:
            primaryLabel = "阅读时长"
            primaryValue = measurementText(total: primaryTotal, recordCount: records.count, missingCount: missingPrimaryCount, empty: "暂无阅读记录", unit: .duration)
            let pages = records.compactMap { measurement(for: $0, key: "pages", details: details)?.value }
            let missingPages = max(0, records.count - pages.count)
            secondaryLabel = "阅读页数"
            secondaryValue = records.isEmpty ? "暂无阅读记录" : (missingPages == 0 ? "\(Int(pages.reduce(0, +).rounded())) 页" : "未提供完整页数")
            note = missingPrimaryCount > 0 ? "\(missingPrimaryCount) 条记录未提供阅读时长" : "未提供书籍总页数，不显示阅读进度"
        }

        let weeklyValues = trendDateKeys(for: domain, dateKey: dateKey).map { weekDay in
            let dailyRecords = allRecords.filter { $0.dateKey == weekDay }
            let scoped: [NativeDayRecord]
            switch domain {
            case .expense: scoped = dailyRecords.filter(isExpense)
            case .sleep, .food, .sport, .reading:
                scoped = dailyRecords.filter { ($0.domainKey ?? $0.kind.rawValue) == domain.rawValue }
            }
            let value: Double?
            if weekDay > todayKey {
                value = nil
            } else if domain == .expense {
                let amounts = scoped.compactMap { expenseAmount(for: $0, details: details) }
                value = amounts.count == scoped.count ? amounts.reduce(0, +) : nil
            } else if scoped.isEmpty {
                value = nil
            } else {
                let measurements = scoped.compactMap { measurement(for: $0, key: primaryKey, details: details)?.value }
                value = measurements.count == scoped.count ? measurements.reduce(0, +) : nil
            }
            return NativeDomainDayValue(dateKey: weekDay, value: value, recordCount: scoped.count)
        }

        let merchantGroups = Dictionary(grouping: records.filter(isExpense)) { record -> String in
            let raw = detail(for: record, details: details)?.merchantName ?? record.title
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "商户未提供" : name
        }
        let merchants = merchantGroups.map { name, merchantRecords in
            let amounts = merchantRecords.compactMap { expenseAmount(for: $0, details: details) }
            return NativeMerchantSummary(
                name: name,
                total: amounts.count == merchantRecords.count ? amounts.reduce(0, +) : nil,
                records: merchantRecords.sorted(by: chronologicalOrder)
            )
        }.sorted { left, right in
            switch (left.total, right.total) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.name < right.name
            }
        }

        let timeline = domain == .expense ? records.filter(isExpense).compactMap { record -> NativeTimelineEntry? in
            let recordDetail = detail(for: record, details: details)
            let clock = NativeLocalDate.financeTimeKey(occurredAt: recordDetail?.occurredAt)
                ?? recordDetail?.transactionTime ?? record.timeLabel
            guard let occurredAt = NativeLocalDate.financeOccurredAt(dateKey: record.dateKey, timeKey: clock),
                  let normalized = NativeLocalDate.financeTimeKey(occurredAt: occurredAt) else { return nil }
            let parts = normalized.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return nil }
            return NativeTimelineEntry(record: record, minute: parts[0] * 60 + parts[1])
        }.sorted {
            $0.minute == $1.minute ? $0.id < $1.id : $0.minute < $1.minute
        } : []

        let sleepRanges = domain == .sleep ? records.compactMap { record -> NativeSleepInterval? in
            guard let payload = detail(for: record, details: details)?.payload,
                  let start = isoDate(payload.string("sleep_start_at")),
                  let end = isoDate(payload.string("wake_at")), end > start else { return nil }
            return NativeSleepInterval(record: record, start: start, end: end)
        }.sorted { $0.start < $1.start } : []

        let periodDates = Set(trendDateKeys(for: domain, dateKey: dateKey))
        let sportRecords = allRecords.filter { periodDates.contains($0.dateKey) && ($0.domainKey ?? $0.kind.rawValue) == "sport" }
        let periodTypes = domain == .sport ? Set(sportRecords.map { record -> String in
            let payload = detail(for: record, details: details)?.payload
            let type = (payload?.string("sport_type") ?? payload?.string("activity_type") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return type.isEmpty ? "类型未提供" : type
        }).sorted() : []

        let highestMeal = domain == .food ? records.compactMap { record -> (NativeDayRecord, Double)? in
            guard let value = measurement(for: record, key: primaryKey, details: details)?.value else { return nil }
            return (record, value)
        }.max(by: { $0.1 < $1.1 })?.0 : nil

        var previousExpenseTotal: Double?
        if domain == .expense, !isLoading, errorMessage?.isEmpty != false,
           let previousDay = NativeLocalDate.shiftedDateKey(dateKey, byDays: -1) {
            let previous = allRecords.filter { $0.dateKey == previousDay && isExpense($0) }
            let amounts = previous.compactMap { expenseAmount(for: $0, details: details) }
            if amounts.count == previous.count { previousExpenseTotal = amounts.reduce(0, +) }
        }

        let stateMessage: String?
        if let errorMessage, !errorMessage.isEmpty {
            stateMessage = "记录读取失败：\(errorMessage)"
        } else if isLoading {
            stateMessage = "正在读取本机与云端记录…"
        } else {
            stateMessage = nil
        }

        return Self(
            dateKey: dateKey,
            records: records.sorted(by: chronologicalOrder),
            weeklyValues: weeklyValues,
            primaryLabel: primaryLabel,
            primaryValue: primaryValue,
            secondaryLabel: secondaryLabel,
            secondaryValue: secondaryValue,
            measurementNote: note,
            highestExpense: highest,
            knownPrimaryTotal: knownPrimaryTotal,
            stateMessage: stateMessage,
            merchants: merchants,
            timeline: timeline,
            sleepRanges: sleepRanges,
            periodTypes: periodTypes,
            highestMeal: highestMeal,
            previousExpenseTotal: previousExpenseTotal
        )
    }

    private enum MeasurementUnit: Equatable { case duration, calories }

    private static func isoDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) { return date }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: value)
    }

    private static func isExpense(_ record: NativeDayRecord) -> Bool {
        record.kind == .expense && record.transactionType != "income"
    }

    private static func isIncome(_ record: NativeDayRecord) -> Bool {
        record.kind == .income || record.transactionType == "income"
    }

    private static func measurementKey(for domain: AppDomain) -> String {
        switch domain {
        case .expense: return "amount"
        case .sleep: return "sleep_minutes"
        case .food: return "total_calorie_kcal"
        case .sport: return "duration_minutes"
        case .reading: return "reading_minutes"
        }
    }

    private static func measurement(
        for record: NativeDayRecord,
        key: String,
        details: [String: NativeRecordDetail]
    ) -> NativeRecordMeasurement? {
        guard let detail = detail(for: record, details: details) else { return nil }
        return NativeRecordDetailPresentationAdapter.measurements(for: detail).first { $0.key == key }
    }

    private static func expenseAmount(
        for record: NativeDayRecord,
        details: [String: NativeRecordDetail]
    ) -> Double? {
        if let amount = detail(for: record, details: details)?.amount { return amount }
        let value = record.value.filter { $0.isNumber || $0 == "." || $0 == "-" }
        return value.isEmpty ? nil : Double(value)
    }

    private static func detail(for record: NativeDayRecord, details: [String: NativeRecordDetail]) -> NativeRecordDetail? {
        let canonical = NativeRecordReference(record.reference).canonicalValue
        return details[record.reference]
            ?? details[canonical]
            ?? details.values.first { NativeRecordReference($0.id).canonicalValue == canonical }
    }

    private static func measurementText(
        total: Double?,
        recordCount: Int,
        missingCount: Int,
        empty: String,
        unit: MeasurementUnit
    ) -> String {
        guard recordCount > 0 else { return empty }
        guard let total else { return "记录字段缺失" }
        let rounded = Int(total.rounded())
        if unit == .calories { return "\(rounded) 千卡" }
        return rounded >= 60 ? "\(rounded / 60) 小时 \(rounded % 60) 分钟" : "\(rounded) 分钟"
    }

    private static func currency(_ value: Double) -> String { String(format: "¥%.2f", value) }

    private static func chronologicalOrder(_ lhs: NativeDayRecord, _ rhs: NativeDayRecord) -> Bool {
        switch (lhs.timeLabel, rhs.timeLabel) {
        case let (left?, right?): return left > right
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.reference < rhs.reference
        }
    }
}
