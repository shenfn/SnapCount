import Foundation
import CoreFoundation

/// Matches the existing PWA wallet reader: a present top-level value remains authoritative.
enum LocalHistorySourceCompatibility {
    static func walletValue(_ row: [String: Any], field: String) -> Any? {
        if let value = row[field], !(value is NSNull) { return value }
        let payload = row["payload_jsonb"] as? [String: Any] ?? [:]
        guard let value = payload[field], !(value is NSNull) else { return nil }
        return value
    }

    /// Single money parser for history migration. The same source value reaches
    /// this parser as a Swift `Double` (AnyCodable) and as an `NSNumber`
    /// (JSONSerialization), so the decimal text must be taken from the shortest
    /// round-trip form. `NSNumber.description` is not that form: `8.54` becomes
    /// `8.539999999999999` and would be rejected as a non-integral cent value.
    static func minorValue(_ value: Any) throws -> Int64 {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            throw LocalDataError.invalidRecord
        }
        let text: String
        switch value {
        case let number as NSNumber:
            let type = String(cString: number.objCType)
            text = type == "d" || type == "f" ? number.doubleValue.description : number.stringValue
        case let double as Double:
            text = double.description
        case is NSNull:
            throw LocalDataError.invalidRecord
        default:
            text = String(describing: value)
        }
        // NaN/Infinity 或溢出都会让下面的等值判断失败，不需要额外分支。
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else {
            throw LocalDataError.invalidRecord
        }
        var scaled = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded == scaled,
              rounded >= Decimal(Int64.min), rounded <= Decimal(Int64.max) else {
            throw LocalDataError.invalidRecord
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static func validWalletBalance(_ value: Any) -> Bool {
        guard let minor = try? minorValue(value), minor >= 0 else { return false }
        return true
    }

    /// 云端 PostgREST 返回的 timestamptz 形如 `2026-08-08T10:53:38.059384+00:00`：
    /// 6 位微秒，ISO8601DateFormatter 只稳定支持 3 位。历史迁移的映射与导入校验
    /// 必须共用这一份解析，否则会出现「mapper 建得出归档、导入校验拒收」。
    static func parseTimestamp(_ value: String) -> Date? {
        let normalized = normalizeTimestamp(value)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: normalized) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: normalized) { return date }
        // 本机 DATETIME 落盘形态（UTC、无时区）：严格往返后才接受。
        let sqlite = DateFormatter()
        sqlite.locale = Locale(identifier: "en_US_POSIX")
        sqlite.calendar = Calendar(identifier: .gregorian)
        sqlite.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss"] {
            sqlite.dateFormat = format
            if let date = sqlite.date(from: value), sqlite.string(from: date) == value { return date }
        }
        return nil
    }

    /// 空格分隔 → `T`；微秒截到毫秒；`+HH` 补成 `+HH:00`。
    static func normalizeTimestamp(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "T")

        // 只在末尾识别时区，避免把日期里的 `-` 当成符号。
        var zone = ""
        if text.hasSuffix("Z") {
            text.removeLast()
            zone = "Z"
        } else {
            var cursor = text.endIndex
            while cursor > text.startIndex {
                cursor = text.index(before: cursor)
                let character = text[cursor]
                if character == "+" || character == "-" {
                    let suffix = String(text[text.index(after: cursor)...])
                    if !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber || $0 == ":" }) {
                        zone = String(text[cursor...])
                        text = String(text[..<cursor])
                    }
                    break
                }
                if !(character.isNumber || character == ":") { break }
            }
        }

        if let dot = text.firstIndex(of: ".") {
            let fraction = String(text[text.index(after: dot)...])
            if !fraction.isEmpty, fraction.allSatisfy({ $0.isNumber }) {
                text = String(text[..<dot]) + "." + String(fraction.prefix(3))
            }
        }

        if zone.count == 3, zone.hasPrefix("+") || zone.hasPrefix("-") {
            zone += ":00"
        } else if zone.count == 5, !zone.contains(":") {
            zone = String(zone.prefix(3)) + ":" + String(zone.suffix(2))
        }
        return text + zone
    }
}
