import Foundation

enum NativeDayRecordKind: String, CaseIterable, Identifiable {
    case all, expense, income, sport, sleep, food, reading, wallet, staging
    var id: String { rawValue }
    var title: String { switch self { case .all: return "全部"; case .expense: return "支出"; case .income: return "收入"; case .sport: return "运动"; case .sleep: return "睡眠"; case .food: return "饮食"; case .reading: return "阅读"; case .wallet: return "钱包"; case .staging: return "待处理" } }
    var systemImage: String { switch self { case .all: return "square.grid.2x2"; case .expense: return "creditcard"; case .income: return "arrow.down.circle"; case .sport: return "figure.run"; case .sleep: return "moon"; case .food: return "fork.knife"; case .reading: return "book"; case .wallet: return "wallet.pass"; case .staging: return "tray" } }
}

struct NativeDayRecord: Identifiable {
    let id: String
    let reference: String
    let dateKey: String
    let kind: NativeDayRecordKind
    let domainKey: String?
    let title: String
    let subtitle: String
    let value: String
    let timeLabel: String?
    let systemImage: String
    let transactionType: String?
    let status: String?

    init(
        id: String,
        reference: String,
        dateKey: String,
        kind: NativeDayRecordKind,
        domainKey: String?,
        title: String,
        subtitle: String,
        value: String,
        timeLabel: String?,
        systemImage: String,
        transactionType: String? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.reference = reference
        self.dateKey = dateKey
        self.kind = kind
        self.domainKey = domainKey
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.timeLabel = timeLabel
        self.systemImage = systemImage
        self.transactionType = transactionType
        self.status = status
    }
}

struct NativeDayRecordGroup: Identifiable {
    let dateKey: String
    let records: [NativeDayRecord]
    var id: String { dateKey }
    func records(for kind: NativeDayRecordKind) -> [NativeDayRecord] { kind == .all ? records : records.filter { $0.kind == kind } }
    var availableKinds: [NativeDayRecordKind] { let present = Set(records.map(\.kind)); return [.all] + NativeDayRecordKind.allCases.filter { $0 != .all && present.contains($0) } }
}

struct NativeDayDetailRoute: Hashable {
    let dateKey: String
    let kind: NativeDayRecordKind
}

extension DashboardSnapshot {
    func mergingUnavailableSections(from previous: DashboardSnapshot) -> DashboardSnapshot {
        guard !unavailableSections.isEmpty else { return self }
        var merged = self
        merged.dayRecordGroups = mergedRecordGroups(from: previous)

        if unavailableSections.contains(.expense) {
            merged.monthExpense = previous.monthExpense
            merged.todayExpense = previous.todayExpense
            if unavailableSections.contains(.pendingExpense) {
                merged.pendingExpenses = previous.pendingExpenses
            }
        }
        if unavailableSections.contains(.pendingExpense),
           !unavailableSections.contains(.expense) {
            let monthPrefix = String(NativeLocalDate.dateKey(Date()).prefix(7))
            let currentMonthPending = merged.pendingExpenses.filter { $0.dateKey.hasPrefix(monthPrefix) }
            let olderPending = previous.pendingExpenses.filter { !$0.dateKey.hasPrefix(monthPrefix) }
            merged.pendingExpenses = (currentMonthPending + olderPending).sorted {
                if $0.dateKey != $1.dateKey { return $0.dateKey > $1.dateKey }
                let leftOccurredAt = $0.occurredAtLabel ?? ""
                let rightOccurredAt = $1.occurredAtLabel ?? ""
                if leftOccurredAt != rightOccurredAt {
                    return leftOccurredAt > rightOccurredAt
                }
                return $0.id > $1.id
            }
        }
        if unavailableSections.contains(.income) {
            merged.monthIncome = previous.monthIncome
            merged.todayIncome = previous.todayIncome
        }
        if unavailableSections.contains(.staging) {
            merged.stagingRecords = previous.stagingRecords
        }

        merged.dailySummaries = mergedDailySummaries(from: previous, groups: merged.dayRecordGroups)
        merged.todayCount = merged.dayRecordGroups
            .first(where: { $0.dateKey == Self.localDateKey })?
            .records.filter { $0.kind != .staging }.count ?? 0
        merged.monthCount = merged.dayRecordGroups.flatMap(\.records).filter { $0.kind != .staging }.count
        merged.pendingCount = merged.pendingExpenses.count + merged.stagingRecords.count
        merged.recordDetails = mergedRecordDetails(from: previous)
        if !unavailableSections.isSubset(of: Set([DashboardDataSection.pendingExpense])) {
            merged.recentRecords = previous.recentRecords
        }
        return merged
    }

    private func mergedRecordGroups(from previous: DashboardSnapshot) -> [NativeDayRecordGroup] {
        let currentRecords = dayRecordGroups.flatMap(\.records).filter { !shouldPreserve($0.kind) }
        let preservedRecords = previous.dayRecordGroups.flatMap(\.records).filter { shouldPreserve($0.kind) }
        let records = currentRecords + preservedRecords
        return Dictionary(grouping: records, by: \.dateKey)
            .map { NativeDayRecordGroup(dateKey: $0.key, records: $0.value.sorted { ($0.timeLabel ?? "") > ($1.timeLabel ?? "") }) }
            .sorted { $0.dateKey > $1.dateKey }
    }

    private func mergedDailySummaries(
        from previous: DashboardSnapshot,
        groups: [NativeDayRecordGroup]
    ) -> [NativeDailySummary] {
        let currentByDate = Dictionary(uniqueKeysWithValues: dailySummaries.map { ($0.dateKey, $0) })
        let previousByDate = Dictionary(uniqueKeysWithValues: previous.dailySummaries.map { ($0.dateKey, $0) })
        return groups.map { group in
            let current = currentByDate[group.dateKey]
            let old = previousByDate[group.dateKey]
            let pendingCount = group.records.filter {
                $0.kind == .staging || ($0.kind == .expense && $0.systemImage == "clock")
            }.count
            return NativeDailySummary(
                dateKey: group.dateKey,
                expense: unavailableSections.contains(.expense) ? old?.expense ?? 0 : current?.expense ?? 0,
                income: unavailableSections.contains(.income) ? old?.income ?? 0 : current?.income ?? 0,
                pendingCount: pendingCount,
                recordCount: group.records.count
            )
        }
    }

    private func mergedRecordDetails(from previous: DashboardSnapshot) -> [String: NativeRecordDetail] {
        var details = recordDetails.filter { !shouldPreserve(detailKind($0.value)) }
        for (key, detail) in previous.recordDetails where shouldPreserve(detailKind(detail)) {
            details[key] = detail
        }
        return details
    }

    private func detailKind(_ detail: NativeRecordDetail) -> NativeDayRecordKind {
        switch detail.kind {
        case "expense": return .expense
        case "income": return .income
        default: return NativeDayRecordKind(rawValue: detail.kind) ?? .all
        }
    }

    private func shouldPreserve(_ kind: NativeDayRecordKind) -> Bool {
        switch kind {
        case .expense: return unavailableSections.contains(.expense)
        case .income: return unavailableSections.contains(.income)
        case .staging: return unavailableSections.contains(.staging)
        default: return unavailableSections.contains(.universal)
        }
    }

    private static var localDateKey: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
