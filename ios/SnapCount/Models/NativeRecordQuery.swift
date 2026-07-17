import Foundation

struct NativeRecordMonthSnapshot {
    let groups: [NativeDayRecordGroup]
    let details: [String: NativeRecordDetail]
}

enum NativeMonthKey {
    static func current(referenceDate: Date = Date()) -> String {
        key(from: referenceDate)
    }

    static func shifted(_ value: String, by offset: Int) -> String? {
        guard let date = date(from: value),
              let shifted = calendar.date(byAdding: .month, value: offset, to: date) else {
            return nil
        }
        return key(from: shifted)
    }

    static func title(_ value: String) -> String {
        guard let components = components(from: value),
              let year = components.year,
              let month = components.month else {
            return value
        }
        return "\(year)年\(month)月"
    }

    private static let calendar = Calendar(identifier: .gregorian)

    private static func date(from value: String) -> Date? {
        guard let components = components(from: value) else { return nil }
        return calendar.date(from: components)
    }

    private static func components(from value: String) -> DateComponents? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return nil
        }
        return DateComponents(calendar: calendar, year: year, month: month, day: 1)
    }

    private static func key(from date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }
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
