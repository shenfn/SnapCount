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
    var isFrequent = false
}

struct NativeManualDomainMetadata: Equatable {
    let primaryKey: String
    let primaryLabel: String
    let dimensionKey: String
    let dimensionLabel: String
    let defaultTitle: String
    let defaultDimension: String
    let maximumValue: Double

    static func resolve(
        _ definition: NativeDomainDefinition?,
        fallbackDomainKey: String = "sport"
    ) -> NativeManualDomainMetadata {
        let domainKey = definition?.id ?? fallbackDomainKey
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

struct NativeManualRecordDraft {
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
    var existingRawId: String?
    var originalPayload: [String: AnyCodable] = [:]
    var imagePath: String?
    var imageHash: String?

    init(kind: NativeManualRecordKind = .expense, domainKey: String = "sport") {
        self.kind = kind
        self.domainKey = domainKey
    }

    init(detail: NativeRecordDetail) {
        self.init(kind: .universal, domainKey: detail.category ?? "sport")
        existingRawId = detail.rawId
        originalPayload = detail.payload ?? [:]
        title = detail.title
        note = detail.note ?? ""
        imagePath = detail.imagePath
        imageHash = detail.imageHash
        if let recordDate = detail.recordDate, let parsedDate = Self.dateFormatter.date(from: recordDate) {
            date = parsedDate
        }
        if detail.subtitle.count >= 16 {
            let start = detail.subtitle.index(detail.subtitle.startIndex, offsetBy: 11)
            let availableLength = detail.subtitle.distance(from: start, to: detail.subtitle.endIndex)
            let end = detail.subtitle.index(start, offsetBy: min(8, availableLength))
            let timeText = String(detail.subtitle[start..<end])
            if let parsedTime = Self.timeFormatter.date(from: timeText.count == 5 ? timeText + ":00" : timeText) {
                time = parsedTime
                includesTime = true
            }
        }
        if domainKey == "wallet" {
            walletRecordKind = originalPayload.string("record_kind") ?? "cash_snapshot"
            walletAccountType = originalPayload.string("account_type") ?? "other"
            walletDueDate = originalPayload.string("due_date") ?? ""
            walletBillDay = originalPayload.double("bill_day").map { String(Int($0)) } ?? ""
        }
    }

    init(stagingRecord record: NativeStagingRecord, domainKey: String) {
        let kind: NativeManualRecordKind
        switch domainKey {
        case "expense": kind = .expense
        case "income": kind = .income
        default: kind = .universal
        }
        self.init(kind: kind, domainKey: domainKey)

        let nestedPayload = record.extracted.dictionary("payload_jsonb") ?? [:]
        let payload = record.extracted.merging(nestedPayload) { current, _ in current }
        originalPayload = payload
        imagePath = record.imagePath
        imageHash = record.imageHash
        accountId = payload.string("account_id")
        amountText = payload.double("amount").map { String($0) } ?? ""
        platform = payload.string("platform") ?? ""
        paymentMethod = payload.string("payment_method") ?? ""
        category = domainKey == "income"
            ? payload.string("income_category") ?? ""
            : payload.string("category") ?? ""
        title = payload.string("title")
            ?? payload.string(domainKey == "income" ? "source_name" : "merchant_name")
            ?? ""
        note = payload.string("note")
            ?? (kind == .universal ? payload.string("summary") ?? "" : record.summary)

        if let parsedDate = Self.dateFormatter.date(from: record.dateKey) {
            date = parsedDate
        }
        let occurredAt = payload.string("occurred_at") ?? payload.string("order_finished_at")
        let rawTime = payload.string("transaction_time")
            ?? occurredAt.flatMap { value in
                guard value.count >= 16 else { return nil }
                let start = value.index(value.startIndex, offsetBy: 11)
                let end = value.index(start, offsetBy: 5)
                return String(value[start..<end]) + ":00"
            }
        if let rawTime, let parsedTime = Self.timeFormatter.date(from: rawTime.count == 5 ? rawTime + ":00" : rawTime) {
            time = parsedTime
            includesTime = true
        }

        let metadata = NativeManualDomainMetadata.resolve(nil, fallbackDomainKey: domainKey)
        primaryValueText = payload.double(metadata.primaryKey).map { String($0) } ?? ""
        dimension = payload.string(metadata.dimensionKey) ?? ""
        if domainKey == "wallet" {
            walletRecordKind = payload.string("record_kind") ?? "cash_snapshot"
            walletAccountType = payload.string("account_type") ?? "other"
            walletDueDate = payload.string("due_date") ?? ""
            walletBillDay = payload.double("bill_day").map { String(Int($0)) } ?? ""
        }
    }

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
            let metadata = NativeManualDomainMetadata.resolve(domain, fallbackDomainKey: domainKey)
            guard let primaryValue, primaryValue <= metadata.maximumValue else { return "请输入有效(metadata.primaryLabel)" }
            guard !dimension.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "请填写(metadata.dimensionLabel)" }
            if domainKey == "wallet", walletRecordKind == "liability_snapshot", !walletBillDay.isEmpty {
                guard let billDay = Int(walletBillDay), (1...31).contains(billDay) else { return "每月还款日必须是 1-31 之间的整数" }
            }
        }
        return nil
    }

    func universalPayload(domain: NativeDomainDefinition?) -> [String: AnyCodable] {
        let metadata = NativeManualDomainMetadata.resolve(domain, fallbackDomainKey: domainKey)
        let value = primaryValue ?? 0
        let cleanDimension = dimension.trimmingCharacters(in: .whitespacesAndNewlines)
        var payload = originalPayload
        payload[metadata.primaryKey] = AnyCodable(value)
        payload[metadata.dimensionKey] = AnyCodable(cleanDimension)
        payload["source_app"] = AnyCodable("manual")

        if !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["note"] = AnyCodable(note.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            payload["note"] = AnyCodable(NSNull())
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
        return cleanDimension.isEmpty
            ? NativeManualDomainMetadata.resolve(domain, fallbackDomainKey: domainKey).defaultTitle
            : cleanDimension
    }

    func resolvedSummary(domain: NativeDomainDefinition?) -> String {
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanNote.isEmpty { return cleanNote }
        let metadata = NativeManualDomainMetadata.resolve(domain, fallbackDomainKey: domainKey)
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

extension NativeStagingRecord {
    func applyingArchiveDraft(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?
    ) -> NativeStagingRecord {
        var payload = draft.originalPayload
        let cleanTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSummary = draft.resolvedSummary(domain: domain)

        switch draft.kind {
        case .expense:
            if let amount = draft.amount { payload["amount"] = AnyCodable(amount) }
            payload["merchant_name"] = AnyCodable(cleanTitle)
            payload["platform"] = AnyCodable(draft.platform)
            payload["category"] = AnyCodable(draft.category)
            payload["payment_method"] = AnyCodable(draft.paymentMethod)
            payload["account_id"] = AnyCodable(draft.accountId.map { $0 as Any } ?? NSNull())
            payload["transaction_time"] = AnyCodable(draft.timeKey.map { $0 as Any } ?? NSNull())
        case .income:
            if let amount = draft.amount { payload["amount"] = AnyCodable(amount) }
            payload["source_name"] = AnyCodable(cleanTitle)
            payload["income_category"] = AnyCodable(draft.category)
            payload["account_id"] = AnyCodable(draft.accountId.map { $0 as Any } ?? NSNull())
        case .universal:
            payload = draft.universalPayload(domain: domain)
            payload["title"] = AnyCodable(draft.resolvedTitle(domain: domain))
        }

        payload["occurred_at"] = AnyCodable(draft.occurredAt)
        payload["summary"] = AnyCodable(cleanSummary)

        return NativeStagingRecord(
            id: id,
            dateKey: draft.dateKey,
            title: cleanTitle.isEmpty ? title : cleanTitle,
            summary: cleanSummary,
            status: status,
            statusLabel: statusLabel,
            recordTypeLabel: recordTypeLabel,
            createdAtLabel: createdAtLabel,
            occurredAtLabel: draft.includesTime
                ? "\(draft.dateKey) \(draft.timeKey.map { String($0.prefix(5)) } ?? "")"
                : draft.dateKey,
            confidencePercent: confidencePercent,
            lastErrorMessage: lastErrorMessage,
            retryCount: retryCount,
            systemImage: systemImage,
            imagePath: imagePath,
            imageURL: imageURL,
            imageLoadError: imageLoadError,
            recordType: draft.domainKey,
            domainKey: draft.domainKey,
            domainName: domain?.shortName ?? domainName,
            extracted: payload,
            companionMessage: companionMessage,
            targetRecordId: targetRecordId,
            imageHash: imageHash
        )
    }
}

extension NativeManualRecordDraft {
    static var expensePlatforms: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(kind: .platform, currentValue: nil, vocabulary: [])
    }

    static var expenseCategories: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(kind: .category, currentValue: nil, vocabulary: [])
    }

    static var expensePayments: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(kind: .payment, currentValue: nil, vocabulary: [])
    }

    static let incomeCategories = [
        NativeManualRecordOption(id: "salary", title: "工资"),
        NativeManualRecordOption(id: "bonus", title: "奖金"),
        NativeManualRecordOption(id: "freelance", title: "兼职"),
        NativeManualRecordOption(id: "investment", title: "投资收益"),
        NativeManualRecordOption(id: "reimbursement", title: "报销"),
        NativeManualRecordOption(id: "other", title: "其他")
    ]
}
