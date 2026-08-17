import Foundation

enum NativeWalletSnapshotKind: String, Codable {
    case asset
    case liability
}

struct NativeWalletSnapshot: Identifiable {
    let id: String
    let title: String
    let summary: String
    let occurredAt: String
    let createdAt: String
    let payload: [String: AnyCodable]
    let imagePath: String?
    let imageHash: String?
    let linkedAccountId: String?
    let kind: NativeWalletSnapshotKind
    let balance: Double
    let snapshotAt: String

    var accountName: String {
        payload.string("account_name") ?? (title.isEmpty ? "未命名账户" : title)
    }

    var institution: String? {
        payload.string("institution") ?? payload.string("account_name")
    }

    var last4: String? {
        guard let value = payload.string("last4"),
              value.range(of: #"^\d{4}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    var accountType: NativeAccountType {
        let normalized = NativeAccountType.normalized(payload.string("account_type") ?? "other")
        if normalized != .other { return normalized }
        return kind == .liability ? .creditLine : .walletBalance
    }

    var billDay: Int? {
        validDay(payload.double("bill_day"))
    }

    var paymentDueDay: Int? {
        if let day = dateDay(payload.string("due_date")) { return day }
        return validDay(
            payload.double("payment_due_day")
                ?? payload.double("due_day")
                ?? payload.double("repayment_day")
        )
    }

    var cycleMonth: String? {
        [
            payload.string("cycle_month"),
            payload.string("statement_month"),
            payload.string("bill_month"),
            payload.string("due_date"),
            occurredAt,
            createdAt
        ].compactMap(Self.monthKey).first
    }

    var dueDate: String? {
        guard let value = payload.string("due_date"), Self.isDateKey(value) else { return nil }
        return value
    }

    var statementStartDate: String? { validDate("statement_start_date") }
    var statementEndDate: String? { validDate("statement_end_date") }
    var status: NativeRepaymentStatus {
        switch payload.string("status") {
        case "paid": return .paid
        case "ignored": return .ignored
        default: return .pending
        }
    }

    var confidence: Double? {
        let candidates = [
            payload.double("confidence"),
            nestedPayload("time_context")?.double("confidence")
        ]
        guard let value = candidates.compactMap({ $0 }).first, value >= 0 else { return nil }
        return min(value, 1)
    }

    private func validDate(_ key: String) -> String? {
        guard let value = payload.string(key), Self.isDateKey(value) else { return nil }
        return value
    }

    private func nestedPayload(_ key: String) -> [String: AnyCodable]? {
        guard let raw = payload[key]?.value as? [String: Any] else { return nil }
        return raw.mapValues(AnyCodable.init)
    }

    private func validDay(_ value: Double?) -> Int? {
        guard let value, value.rounded() == value, (1...31).contains(Int(value)) else { return nil }
        return Int(value)
    }

    private func dateDay(_ value: String?) -> Int? {
        guard let value, Self.isDateKey(value), let day = Int(value.suffix(2)) else { return nil }
        return day
    }

    private static func monthKey(_ value: String?) -> String? {
        guard let value else { return nil }
        let prefix = String(value.prefix(7))
        guard prefix.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil else {
            return nil
        }
        return prefix
    }

    private static func isDateKey(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }
}

enum NativeWalletSnapshotOutcome: String, Codable, Equatable {
    case created
    case linked
    case replayed
    case needsConfirmation = "needs_confirmation"
}

struct NativeWalletSnapshotLinkResult {
    let accountId: String
    let warnings: [String]
    let outcome: NativeWalletSnapshotOutcome
    let recordId: String?
    let cycle: NativeRepaymentCycle?
    let payment: NativeLiabilityPayment?
    let balanceChanged: Bool
    let reviewRequired: Bool

    var successMessage: String {
        switch outcome {
        case .created: return "已从快照创建账户"
        case .linked: return "已关联账户"
        case .replayed: return "快照关联已存在"
        case .needsConfirmation: return "账户已关联，账期/还款需要确认"
        }
    }

    init(
        accountId: String,
        warnings: [String] = [],
        outcome: NativeWalletSnapshotOutcome = .linked,
        recordId: String? = nil,
        cycle: NativeRepaymentCycle? = nil,
        payment: NativeLiabilityPayment? = nil,
        balanceChanged: Bool = false,
        reviewRequired: Bool = false
    ) {
        self.accountId = accountId
        self.warnings = warnings
        self.outcome = outcome
        self.recordId = recordId
        self.cycle = cycle
        self.payment = payment
        self.balanceChanged = balanceChanged
        self.reviewRequired = reviewRequired
    }
}
