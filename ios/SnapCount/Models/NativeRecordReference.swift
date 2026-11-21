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

    // Local detail and list projections can use different prefixes for the
    // same record. Keep the original kind for routing and normalize identity here.
    var canonicalValue: String {
        let canonicalKind: String
        switch kind {
        case "local-expense": canonicalKind = "expense"
        case "local-income": canonicalKind = "income"
        case "local-data": canonicalKind = "data"
        default: canonicalKind = kind
        }
        let canonicalRawID = UUID(uuidString: rawId)?.uuidString.lowercased() ?? rawId
        return "\(canonicalKind)/\(canonicalRawID)"
    }

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
        case "local-data": return "local-data"
        case "universal", "data": return "data"
        default: return value
        }
    }
}
