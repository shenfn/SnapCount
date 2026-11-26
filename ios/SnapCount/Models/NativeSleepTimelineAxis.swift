import Foundation

struct NativeSleepTimelineValue: Identifiable {
    let interval: NativeSleepInterval
    let startMinute: Double
    let endMinute: Double
    let startDateKey: String
    let endDateKey: String

    var id: String { interval.id }
    var durationMinutes: Double { max(0, endMinute - startMinute) }
}

enum NativeSleepTimelineAxis {
    static let prototypeStart = 1_260.0 // 21:00
    static let prototypeEnd = 1_980.0 // 次日 09:00
    static let tickSpacing = 180.0 // 3 小时

    static func value(for interval: NativeSleepInterval) -> NativeSleepTimelineValue? {
        var effectiveStart = interval.start
        var durationMinutes = interval.end.timeIntervalSince(effectiveStart) / 60
        guard durationMinutes.isFinite, durationMinutes > 0 else { return nil }
        // 识别模型偶发把凌晨入睡（如 00:25）错写为前一天，导致跨度多出整整 24 小时（如 31h）。
        // 超过 24 小时时按整天对齐到醒来前最近的合理睡眠区间。
        if durationMinutes > 1_440 {
            let extraDays = floor((durationMinutes - 1) / 1_440)
            let shiftedStart = effectiveStart.addingTimeInterval(extraDays * 86_400)
            let shiftedDuration = interval.end.timeIntervalSince(shiftedStart) / 60
            if shiftedDuration > 0, shiftedDuration <= 1_440 {
                effectiveStart = shiftedStart
                durationMinutes = shiftedDuration
            }
        }
        guard let startMinute = clockMinutes(for: effectiveStart) else { return nil }
        return NativeSleepTimelineValue(
            interval: interval,
            startMinute: startMinute,
            endMinute: startMinute + durationMinutes,
            startDateKey: NativeLocalDate.dateKey(effectiveStart),
            endDateKey: NativeLocalDate.dateKey(interval.end)
        )
    }

    private static func clockMinutes(for date: Date) -> Double? {
        let clock = NativeLocalDate.timeKey(date)
        let parts = clock.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else { return nil }
        let value = parts[0] * 60 + parts[1]
        return Double(value < 720 ? value + 1440 : value)
    }

    static func bounds(for ranges: [ClosedRange<Double>]) -> ClosedRange<Double> {
        guard let first = ranges.first else { return prototypeStart...prototypeEnd }
        let lower = ranges.dropFirst().reduce(first.lowerBound) { min($0, $1.lowerBound) }
        let upper = ranges.dropFirst().reduce(first.upperBound) { max($0, $1.upperBound) }
        let expandedLower = min(prototypeStart, floor(lower / 60) * 60)
        let expandedUpper = max(prototypeEnd, ceil(upper / 60) * 60)
        return expandedLower...expandedUpper
    }

    static func label(for minute: Double) -> String {
        NativeSleepSummary.clockLabel(minute)
    }
}
