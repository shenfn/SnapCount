import Foundation

struct NativeRecordReference: Hashable {
    let kind: String
    let rawId: String

    init(_ value: String) {
        let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            kind = Self.normalizedKind(parts[0])
            rawId = parts[1]
        } else if value.hasPrefix("tx-") {
            kind = "expense"
            rawId = String(value.dropFirst(3))
        } else if value.hasPrefix("income-") {
            kind = "income"
            rawId = String(value.dropFirst(7))
        } else if value.hasPrefix("data-") {
            kind = "data"
            rawId = String(value.dropFirst(5))
        } else {
            kind = "data"
            rawId = value
        }
    }

    init(kind: String, rawId: String) {
        self.kind = Self.normalizedKind(kind)
        self.rawId = rawId
    }

    var canonicalValue: String { "\(kind)/\(rawId)" }

    func matches(_ detail: NativeRecordDetail) -> Bool {
        canonicalValue == NativeRecordReference(kind: detail.kind, rawId: detail.rawId).canonicalValue
    }

    func matchesReference(_ value: String) -> Bool {
        canonicalValue == NativeRecordReference(value).canonicalValue
    }

    private static func normalizedKind(_ value: String) -> String {
        switch value {
        case "tx", "transaction", "expense": return "expense"
        case "income": return "income"
        case "universal", "data": return "data"
        default: return value
        }
    }
}
