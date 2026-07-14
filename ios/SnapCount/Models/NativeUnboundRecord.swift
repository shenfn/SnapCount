import Foundation

enum NativeUnboundRecordKind: String, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
    var systemImage: String { self == .expense ? "creditcard" : "arrow.down.circle" }
}

struct NativeUnboundRecord: Identifiable {
    let id: String
    let kind: NativeUnboundRecordKind
    let title: String
    let amount: Double
    let date: String
    let time: String?
    let platform: String?
    let category: String?
    let paymentMethod: String?
    let note: String?
    let source: String?
    let imagePath: String?
    let imageHash: String?
    let companionMessage: String?

    var reference: String { kind == .expense ? "expense/\(id)" : "income/\(id)" }
}

struct NativeAccountRecommendation: Identifiable {
    let account: NativeAccount
    let reason: String
    let confidence: String

    var id: String { account.id }
}

struct NativeUnboundBindingCandidate: Identifiable {
    let record: NativeUnboundRecord
    let recommendation: NativeAccountRecommendation

    var id: String { "\(record.kind.rawValue)-\(record.id)" }
}

enum NativeAccountRecommendationEngine {
    static func recommendation(
        for record: NativeUnboundRecord,
        accounts: [NativeAccount]
    ) -> NativeAccountRecommendation? {
        let activeAccounts = accounts.filter { !$0.isArchived }
        let account: NativeAccount?

        switch record.kind {
        case .income:
            account = activeAccounts.first(where: \.isDefaultIncome)
        case .expense:
            account = paymentAccount(for: record.paymentMethod, accounts: activeAccounts)
                ?? activeAccounts.first(where: \.isDefaultExpense)
        }

        guard let account else { return nil }
        let hasPaymentHint = record.kind == .expense
            && !(record.paymentMethod ?? "").isEmpty
            && record.paymentMethod != "?"
        let reason = record.kind == .income
            ? "使用默认收入账户"
            : (hasPaymentHint ? "根据支付方式「\(record.paymentMethod ?? "")」推荐" : "使用默认支出账户")
        return NativeAccountRecommendation(
            account: account,
            reason: reason,
            confidence: hasPaymentHint ? "高" : "默认"
        )
    }

    static func candidates(
        records: [NativeUnboundRecord],
        accounts: [NativeAccount]
    ) -> [NativeUnboundBindingCandidate] {
        records.compactMap { record in
            recommendation(for: record, accounts: accounts).map {
                NativeUnboundBindingCandidate(record: record, recommendation: $0)
            }
        }
    }

    private static func paymentAccount(
        for paymentMethod: String?,
        accounts: [NativeAccount]
    ) -> NativeAccount? {
        var payment = normalized(paymentMethod)
        if payment == normalized("拼多多先用后付") || payment == normalized("花呗（先用后付）") {
            payment = normalized("先用后付")
        }

        return accounts
            .map { account in (account, score(account: account, payment: payment)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .first?.0
    }

    private static func score(account: NativeAccount, payment: String) -> Int {
        guard !payment.isEmpty else { return 0 }
        let name = normalized(account.name)
        let institution = normalized(account.institution)
        let accountText = name + institution
        var score = 0
        if payment.contains("花呗"), account.type == .creditLine, accountText.contains("花呗") { score += 100 }
        if payment.contains("白条"), account.type == .creditLine,
           accountText.contains("白条") || accountText.contains("京东") { score += 100 }
        if payment.contains("月付"), account.type == .creditLine, accountText.contains("月付") { score += 100 }
        if payment.contains("银行卡"), account.type == .debitCard { score += 40 }
        if payment.contains("微信"), account.type == .walletBalance, accountText.contains("微信") { score += 70 }
        if payment.contains("支付宝"), account.type == .walletBalance, accountText.contains("支付宝") { score += 70 }
        if !name.isEmpty, payment.contains(name) { score += 60 }
        if !institution.isEmpty, payment.contains(institution) { score += 50 }
        return score
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}

