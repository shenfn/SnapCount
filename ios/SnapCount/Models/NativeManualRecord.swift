import Foundation

enum NativeManualRecordKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case universal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: return "支出"
        case .income: return "收入"
        case .universal: return "数据域"
        }
    }
}

struct NativeManualRecordOption: Identifiable, Hashable {
    let id: String
    let title: String
}

struct NativeManualDomainMetadata: Equatable {
    let primaryKey: String
    let primaryLabel: String
    let dimensionKey: String
    let dimensionLabel: String
    let defaultTitle: String
    let defaultDimension: String
    let maximumValue: Double

    static func resolve(_ definition: NativeDomainDefinition?) -> NativeManualDomainMetadata {
        let domainKey = definition?.id ?? "sport"
        let primaryKey = definition?.display.string("primary_fact")
            ?? firstSchemaKey(definition?.schema, group: "facts")
            ?? fallbackPrimaryKey(domainKey)
        let dimensionKey = definition?.display.string("primary_dimension")
            ?? firstSchemaKey(definition?.schema, group: "dimensions")
            ?? fallbackDimensionKey(domainKey)

        return NativeManualDomainMetadata(
            primaryKey: primaryKey,
            primaryLabel: schemaLabel(definition?.schema, group: "facts", key: primaryKey) ?? fallbackPrimaryLabel(domainKey),
            dimensionKey: dimensionKey,
            dimensionLabel: schemaLabel(definition?.schema, group: "dimensions", key: dimensionKey) ?? fallbackDimensionLabel(domainKey),
            defaultTitle: definition?.shortName.appending("记录") ?? "数据记录",
            defaultDimension: domainKey == "sleep" ? "良好" : domainKey == "wallet" ? "微信余额" : "",
            maximumValue: primaryKey.contains("minutes") ? 1_440 : primaryKey == "amount" ? 1_000_000 : 99_999
        )
    }

    private static func firstSchemaKey(_ schema: [String: AnyCodable]?, group: String) -> String? {
        guard let values = schema?[group]?.value as? [[String: Any]] else { return nil }
        return values.first?["key"] as? String
    }

    private static func schemaLabel(_ schema: [String: AnyCodable]?, group: String, key: String) -> String? {
        guard let values = schema?[group]?.value as? [[String: Any]] else { return nil }
        return values.first(where: { $0["key"] as? String == key })?["label"] as? String
    }

    private static func fallbackPrimaryKey(_ domainKey: String) -> String {
        switch domainKey {
        case "sport": return "duration_minutes"
        case "sleep": return "sleep_minutes"
        case "reading": return "reading_minutes"
        case "food": return "total_calorie_kcal"
        case "wallet": return "amount"
        default: return "value"
        }
    }

    private static func fallbackDimensionKey(_ domainKey: String) -> String {
        switch domainKey {
        case "sport": return "sport_type"
        case "sleep": return "quality_level"
        case "reading": return "book_name"
        case "food": return "meal_type"
        case "wallet": return "account_name"
        default: return "category"
        }
    }

    private static func fallbackPrimaryLabel(_ domainKey: String) -> String {
        switch domainKey {
        case "sport": return "运动时长（分钟）"
        case "sleep": return "睡眠时长（分钟）"
        case "reading": return "阅读时长（分钟）"
        case "food": return "总热量（千卡）"
        case "wallet": return "金额"
        default: return "数值"
        }
    }

    private static func fallbackDimensionLabel(_ domainKey: String) -> String {
        switch domainKey {
        case "sport": return "运动类型"
        case "sleep": return "质量等级"
        case "reading": return "书名"
        case "food": return "餐次"
        case "wallet": return "账户/平台"
        default: return "分类"
        }
    }
}

struct NativeManualRecordDraft: Equatable {
    var kind: NativeManualRecordKind = .expense
    var domainKey = "sport"
    var amountText = ""
    var title = ""
    var platform = "线下消费"
    var category = "other"
    var paymentMethod = "微信支付"
    var date = Date()
    var time = Date()
    var includesTime = false
    var note = ""
    var accountId: String?
    var primaryValueText = ""
    var dimension = ""
    var walletRecordKind = "cash_snapshot"
    var walletAccountType = "wechat"
    var walletDueDate = ""
    var walletBillDay = ""

    var amount: Double? { positiveNumber(amountText) }
    var primaryValue: Double? { positiveNumber(primaryValueText) }

    func validationMessage(domain: NativeDomainDefinition?) -> String? {
        switch kind {
        case .expense:
            guard let amount, amount <= 999_999.99 else { return "请输入有效金额（0.01 ~ 999999.99）" }
            guard !platform.isEmpty, !category.isEmpty, !paymentMethod.isEmpty else { return "请选择消费渠道、分类和支付方式" }
        case .income:
            guard let amount, amount <= 999_999.99 else { return "请输入有效金额（0.01 ~ 999999.99）" }
            guard !category.isEmpty else { return "请选择收入类型" }
        case .universal:
            let metadata = NativeManualDomainMetadata.resolve(domain)
            guard let primaryValue, primaryValue <= metadata.maximumValue else { return "请输入有效(metadata.primaryLabel)" }
            guard !dimension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "请填写(metadata.dimensionLabel)" }
            if domainKey == "wallet", walletRecordKind == "liability_snapshot", !walletBillDay.isEmpty {
                guard let billDay = Int(walletBillDay), (1...31).contains(billDay) else { return "每月还款日必须是 1-31 之间的整数" }
            }
        }
        return nil
    }

    func universalPayload(domain: NativeDomainDefinition?) -> [String: AnyCodable] {
        let metadata = NativeManualDomainMetadata.resolve(domain)
        let value = primaryValue ?? 0
        let cleanDimension = dimension.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload: [String: AnyCodable] = [
            metadata.primaryKey: AnyCodable(value),
            metadata.dimensionKey: AnyCodable(cleanDimension),
            "source_app": AnyCodable("manual")
        ]

        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["note"] = AnyCodable(note.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if domainKey == "sleep" {
            payload["sleep_minutes"] = AnyCodable(Int(value.rounded()))
            payload["sleep_hours"] = AnyCodable((value / 60 * 100).rounded() / 100)
        }
        if domainKey == "wallet" {
            payload["record_kind"] = AnyCodable(walletRecordKind)
            payload["account_type"] = AnyCodable(walletAccountType)
            payload["snapshot_balance"] = AnyCodable(value)
            payload["account_snapshot_kind"] = AnyCodable(walletRecordKind == "liability_snapshot" ? "liability" : "asset")
            if !walletDueDate.isEmpty { payload["due_date"] = AnyCodable(walletDueDate) }
            if let billDay = Int(walletBillDay), (1...31).contains(billDay) { payload["bill_day"] = AnyCodable(billDay) }
        }
        return payload
    }

    func resolvedTitle(domain: NativeDomainDefinition?) -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanTitle.isEmpty { return cleanTitle }
        let cleanDimension = dimension.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleanDimension.isEmpty ? NativeManualDomainMetadata.resolve(domain).defaultTitle : cleanDimension
    }

    func resolvedSummary(domain: NativeDomainDefinition?) -> String {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanNote.isEmpty { return cleanNote }
        let metadata = NativeManualDomainMetadata.resolve(domain)
        return "\(metadata.dimensionLabel)：\(dimension.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    var dateKey: String { Self.dateFormatter.string(from: date) }
    var timeKey: String? { includesTime ? Self.timeFormatter.string(from: time) : nil }

    var occurredAt: String {
        let timeValue = includesTime ? Self.timeFormatter.string(from: time) : "12:00:00"
        return "\(dateKey)T\(timeValue)\(Self.timeZoneOffset)"
    }

    private func positiveNumber(_ text: String) -> Double? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static var timeZoneOffset: String {
        let seconds = TimeZone.current.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let absolute = abs(seconds)
        return String(format: "%@%02d:%02d", sign, absolute / 3600, (absolute % 3600) / 60)
    }
}

extension NativeManualRecordDraft {
    static let expensePlatforms = [
        NativeManualRecordOption(id: "美团", title: "美团"),
        NativeManualRecordOption(id: "微信", title: "微信"),
        NativeManualRecordOption(id: "线下消费", title: "线下消费"),
        NativeManualRecordOption(id: "京东", title: "京东"),
        NativeManualRecordOption(id: "拼多多", title: "拼多多"),
        NativeManualRecordOption(id: "淘宝", title: "淘宝"),
        NativeManualRecordOption(id: "抖音", title: "抖音"),
        NativeManualRecordOption(id: "支付宝", title: "支付宝"),
        NativeManualRecordOption(id: "其他", title: "其他")
    ]

    static let expenseCategories = [
        NativeManualRecordOption(id: "food", title: "餐饮"),
        NativeManualRecordOption(id: "shopping", title: "购物"),
        NativeManualRecordOption(id: "transport", title: "出行"),
        NativeManualRecordOption(id: "entertainment", title: "娱乐"),
        NativeManualRecordOption(id: "life", title: "生活"),
        NativeManualRecordOption(id: "health", title: "健康"),
        NativeManualRecordOption(id: "education", title: "教育"),
        NativeManualRecordOption(id: "other", title: "其他")
    ]

    static let expensePayments = [
        NativeManualRecordOption(id: "微信支付", title: "微信支付"),
        NativeManualRecordOption(id: "花呗", title: "花呗"),
        NativeManualRecordOption(id: "支付宝", title: "支付宝"),
        NativeManualRecordOption(id: "银行卡", title: "银行卡"),
        NativeManualRecordOption(id: "京东白条", title: "京东白条"),
        NativeManualRecordOption(id: "美团月付", title: "美团月付"),
        NativeManualRecordOption(id: "先用后付", title: "先用后付")
    ]

    static let incomeCategories = [
        NativeManualRecordOption(id: "salary", title: "工资"),
        NativeManualRecordOption(id: "bonus", title: "奖金"),
        NativeManualRecordOption(id: "freelance", title: "兼职"),
        NativeManualRecordOption(id: "investment", title: "投资收益"),
        NativeManualRecordOption(id: "reimbursement", title: "报销"),
        NativeManualRecordOption(id: "other", title: "其他")
    ]
}
