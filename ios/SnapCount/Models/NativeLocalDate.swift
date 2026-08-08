import Foundation

enum NativeLocalDate {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    static func dateKey(_ value: String, fallback: Date = Date()) -> String {
        if value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return value
        }
        guard let date = parse(value) else {
            return value.count >= 10 ? String(value.prefix(10)) : dateKey(fallback)
        }
        return dateKey(date)
    }

    static func dateKey(_ date: Date) -> String {
        formatter("yyyy-MM-dd").string(from: date)
    }

    static func timeKey(_ value: String) -> String? {
        guard let date = parse(value) else {
            guard value.count >= 16 else { return nil }
            let start = value.index(value.startIndex, offsetBy: 11)
            let end = value.index(start, offsetBy: 5)
            return String(value[start..<end])
        }
        return formatter("HH:mm").string(from: date)
    }

    static func dateTimeLabel(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return value
        }
        if let date = parse(value) {
            return formatter("yyyy-MM-dd HH:mm").string(from: date)
        }
        guard value.count >= 10 else { return value }
        let date = String(value.prefix(10))
        guard value.count >= 16 else { return date }
        let start = value.index(value.startIndex, offsetBy: 11)
        let end = value.index(start, offsetBy: 5)
        return "\(date) \(value[start..<end])"
    }

    static func financeDateKey(occurredAt: String?, legacyDate: String?) -> String? {
        if let occurredAt,
           let date = parse(occurredAt) {
            return dateKey(date)
        }
        guard let legacyDate = legacyDate?.trimmingCharacters(in: .whitespacesAndNewlines),
              legacyDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return legacyDate
    }

    static func financeTimeKey(occurredAt: String?) -> String? {
        guard let occurredAt,
              let date = parse(occurredAt) else {
            return nil
        }
        return formatter("HH:mm").string(from: date)
    }

    static func financeOccurredAt(dateKey: String, timeKey: String?) -> String? {
        let cleanDate = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              let timeKey = timeKey?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        let dateParts = cleanDate.split(separator: "-").compactMap { Int($0) }
        let timeParts = timeKey.split(separator: ":", omittingEmptySubsequences: false)
        guard dateParts.count == 3,
              (2...3).contains(timeParts.count) else {
            return nil
        }
        let secondValue = timeParts.count == 3 ? Int(timeParts[2]) : 0
        guard let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]),
              let second = secondValue,
              (0...23).contains(hour),
              (0...59).contains(minute),
              (0...59).contains(second) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: timeZone,
            year: dateParts[0],
            month: dateParts[1],
            day: dateParts[2],
            hour: hour,
            minute: minute,
            second: second
        )) else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
