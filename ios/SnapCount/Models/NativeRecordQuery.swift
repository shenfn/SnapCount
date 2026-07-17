import Foundation

struct NativeRecordMonthSnapshot {
    let groups: [NativeDayRecordGroup]
    let details: [String: NativeRecordDetail]
}

struct NativeRecordQuery {
    var monthKey: String
    var kind: NativeDayRecordKind = .all

    func groups(from source: [NativeDayRecordGroup]) -> [NativeDayRecordGroup] {
        source.compactMap { group in
            guard group.dateKey.hasPrefix(monthKey) else { return nil }
            let records = group.records(for: kind).filter { $0.kind != .staging }
            return records.isEmpty ? nil : NativeDayRecordGroup(dateKey: group.dateKey, records: records)
        }
    }

    func availableKinds(from source: [NativeDayRecordGroup]) -> [NativeDayRecordKind] {
        let present = Set(source.flatMap(\.records).filter { $0.kind != .staging }.map(\.kind))
        return [.all] + NativeDayRecordKind.allCases.filter { $0 != .all && $0 != .staging && present.contains($0) }
    }
}
