import Foundation

enum NativeSleepFacts {
    static func timestamp(_ value: String?) -> Date? {
        NativeLocalDate.timestamp(value)
    }

    static func businessDate(domainKey: String, payload: [String: AnyCodable], fallback: String) -> String {
        guard domainKey == "sleep",
              let wake = payload.string("wake_at"),
              let date = NativeLocalDate.financeDateKey(occurredAt: wake, legacyDate: nil) else { return fallback }
        return date
    }

    static func hasInvalidInterval(_ payload: [String: AnyCodable]) -> Bool {
        guard let start = timestamp(payload.string("sleep_start_at")),
              let end = timestamp(payload.string("wake_at")) else { return false }
        return end <= start
    }
}

struct NativeSleepBaseline {
    let sampleCount: Int
    let median: Double?

    init(_ values: [Double]) {
        let sorted = values.filter(\.isFinite).sorted()
        sampleCount = sorted.count
        guard sorted.count >= 7 else { median = nil; return }
        let middle = sorted.count / 2
        median = sorted.count.isMultiple(of: 2)
            ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
    }

    var evidence: String {
        median == nil ? "此前30天仅\(sampleCount)晚有效记录，至少7晚才比较"
            : "此前30天中位数 · \(sampleCount)晚"
    }
}

struct NativeSleepSummary {
    let mainRecord: NativeDayRecord?
    let mainMinutesByDay: [String: Double]
    let duration: NativeSleepBaseline
    let bedtime: NativeSleepBaseline
    let wake: NativeSleepBaseline

    static func make(records: [NativeDayRecord], details: [String: NativeRecordDetail], dateKey: String) -> Self {
        func payload(_ record: NativeDayRecord) -> [String: AnyCodable] {
            details[record.reference]?.payload
                ?? details[NativeRecordReference(record.reference).canonicalValue]?.payload ?? [:]
        }
        func minutes(_ record: NativeDayRecord) -> Double? {
            let facts = payload(record)
            guard let value = facts.double("sleep_minutes") ?? facts.double("sleep_hours").map({ $0 * 60 }),
                  value.isFinite, value > 0 else { return nil }
            return value
        }
        func clock(_ record: NativeDayRecord, key: String) -> Double? {
            let facts = payload(record)
            if NativeSleepFacts.hasInvalidInterval(facts) { return nil }
            return clockMinutes(facts.string(key))
        }
        let sleeps = records.filter { ($0.domainKey ?? $0.kind.rawValue) == "sleep" }
        let days = Dictionary(grouping: sleeps) {
            NativeSleepFacts.businessDate(domainKey: "sleep", payload: payload($0), fallback: $0.dateKey)
        }
        var main: [String: NativeDayRecord] = [:]
        for (day, records) in days {
            guard records.allSatisfy({ minutes($0) != nil }) else { continue }
            main[day] = records.sorted {
                let left = minutes($0) ?? 0, right = minutes($1) ?? 0
                return left == right ? $0.reference < $1.reference : left > right
            }.first
        }
        let start = NativeLocalDate.shiftedDateKey(dateKey, byDays: -30) ?? dateKey
        let history = main.filter { $0.key >= start && $0.key < dateKey }.map(\.value)
        return Self(
            mainRecord: main[dateKey],
            mainMinutesByDay: main.compactMapValues(minutes),
            duration: NativeSleepBaseline(history.compactMap(minutes)),
            bedtime: NativeSleepBaseline(history.compactMap { clock($0, key: "sleep_start_at") }),
            wake: NativeSleepBaseline(history.compactMap { clock($0, key: "wake_at") })
        )
    }

    /// 以中午为日界展开夜间钟点，23:30 与 00:30 分别为1410、1470分钟。
    static func clockMinutes(_ raw: String?) -> Double? {
        guard let clock = NativeLocalDate.financeTimeKey(occurredAt: raw) else { return nil }
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let value = parts[0] * 60 + parts[1]
        return Double(value < 720 ? value + 1440 : value)
    }

    static func clockLabel(_ minutes: Double) -> String {
        let value = (Int(minutes.rounded()) % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func clockDifference(_ value: Double, baseline: Double) -> Int {
        let delta = Int((value - baseline).rounded())
        return ((delta + 2160) % 1440) - 720
    }
}
