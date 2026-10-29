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
}
