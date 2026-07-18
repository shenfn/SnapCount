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
