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

    static func validWalletBalance(_ value: Any) -> Bool {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return false }
        guard let decimal = Decimal(string: String(describing: value), locale: Locale(identifier: "en_US_POSIX")), decimal >= 0 else { return false }
        let cents = NSDecimalNumber(decimal: decimal * 100)
        return cents == NSDecimalNumber(value: cents.int64Value)
    }
}
