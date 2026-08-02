import Foundation

enum NativePendingEntryKind: String, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
    var title: String { self == .expense ? "支出" : "收入" }
}

enum NativePendingResolutionField: String, CaseIterable, Identifiable {
    case amount
    case platform
    case category
    case paymentMethod
    case incomeCategory

    var id: String { rawValue }
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
        category = NativeFinanceOptionCatalog.categoryCode(for: detail.category) ?? ""
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

    var missingFields: [NativePendingResolutionField] {
        var fields: [NativePendingResolutionField] = []
        if amount == nil { fields.append(.amount) }
        if kind == .expense {
            if platform.isEmpty { fields.append(.platform) }
            if category.isEmpty { fields.append(.category) }
            if paymentMethod.isEmpty { fields.append(.paymentMethod) }
        } else if incomeCategory.isEmpty {
            fields.append(.incomeCategory)
        }
        return fields
    }

    var recognizedSummary: String {
        let amountLabel = amount.map { String(format: "%@¥%.2f", kind == .income ? "+" : "-", $0) }
        let categoryLabel = kind == .expense
            ? NativeFinanceOptionCatalog.categoryTitle(for: category)
            : NativeManualRecordDraft.incomeCategories.first(where: { $0.id == incomeCategory })?.title
        return [
            amountLabel,
            merchantOrSourceName.isEmpty ? nil : merchantOrSourceName,
            kind == .expense && !platform.isEmpty ? platform : nil,
            categoryLabel,
            kind == .expense && !paymentMethod.isEmpty ? paymentMethod : nil
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
