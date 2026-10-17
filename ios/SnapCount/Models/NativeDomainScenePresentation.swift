import Foundation

struct NativeDomainDayValue: Identifiable {
    let dateKey: String
    let value: Double?
    let recordCount: Int

    var id: String { dateKey }
    var dayLabel: String { String(dateKey.suffix(2)) }
}

struct NativeDomainScenePresentation {
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

    static func trendDateKeys(for domain: AppDomain, dateKey: String) -> [String] {
        switch domain {
        case .sleep, .food:
            return (-6...0).compactMap { NativeLocalDate.shiftedDateKey(dateKey, byDays: $0) }
        case .expense, .sport, .reading:
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
            stateMessage: stateMessage
        )
    }

    private enum MeasurementUnit: Equatable { case duration, calories }

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
