import Foundation

enum NativePendingEntryKind: String, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
}

struct NativePendingResolutionDraft {
    let pendingId: String
    var kind: NativePendingEntryKind
    var amountText: String
    var merchantOrSourceName: String
    var platform: String
    var category: String
    var paymentMethod: String
    var incomeCategory: String
    var accountId: String?

    init(detail: NativeRecordDetail) {
        pendingId = detail.rawId
        kind = detail.kind == "income" ? .income : .expense
        amountText = detail.amount.map { String(format: "%.2f", $0) } ?? ""
        merchantOrSourceName = detail.merchantName ?? ""
        platform = detail.platform ?? ""
        category = detail.category ?? ""
        paymentMethod = detail.paymentMethod ?? ""
        incomeCategory = detail.kind == "income" ? (detail.category ?? "other") : "other"
        accountId = detail.accountId
    }

    var amount: Double? {
        let normalized = amountText.replacingOccurrences(of: "，", with: ".").replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0, value <= 999_999.99 else { return nil }
        return value
    }

    var validationMessage: String? {
        guard amount != nil else { return "请输入有效金额（0.01 ~ 999999.99）" }
        if kind == .expense {
            if platform.isEmpty { return "请选择消费渠道" }
            if category.isEmpty { return "请选择消费分类" }
            if paymentMethod.isEmpty { return "请选择支付方式" }
        } else if incomeCategory.isEmpty {
            return "请选择收入类型"
        }
        return nil
    }
}
