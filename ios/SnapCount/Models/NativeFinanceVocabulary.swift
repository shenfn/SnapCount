import Foundation

enum NativeFinanceVocabularyKind: String, Codable, Equatable {
    case platform
    case category
    case payment
}

struct NativeFinanceVocabularyEntry: Identifiable, Decodable, Equatable {
    let id: String
    let kind: NativeFinanceVocabularyKind
    let displayName: String
    let primaryCategory: String?
    let linkedAccountId: String?
    let source: String
    let status: String
    let usageCount: Int
    let lastUsedAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, source, status
        case displayName = "display_name"
        case primaryCategory = "primary_category"
        case linkedAccountId = "linked_account_id"
        case usageCount = "usage_count"
        case lastUsedAt = "last_used_at"
    }
}

enum NativeFinanceOptionCatalog {
    private struct CategoryDefinition {
        let code: String
        let title: String
        let aliases: [String]
    }

    private struct Candidate {
        var value: String
        var usageCount = 0
        var lastUsedAt = ""
        var isCurrent = false
        var starterOrder = Int.max
    }

    private static let categories = [
        CategoryDefinition(code: "food", title: "餐饮", aliases: ["餐饮", "美食", "餐厅"]),
        CategoryDefinition(code: "shopping", title: "购物", aliases: ["购物", "网购"]),
        CategoryDefinition(code: "transport", title: "出行", aliases: ["出行", "交通", "打车", "transportation"]),
        CategoryDefinition(code: "entertainment", title: "娱乐", aliases: ["娱乐", "休闲"]),
        CategoryDefinition(code: "life", title: "生活", aliases: ["生活", "日用", "缴费", "living", "housing", "rent"]),
        CategoryDefinition(code: "health", title: "健康", aliases: ["健康", "医疗", "药品", "medical", "healthcare"]),
        CategoryDefinition(code: "education", title: "教育", aliases: ["教育", "学习", "learning"]),
        CategoryDefinition(code: "other", title: "其他", aliases: ["其他"])
    ]

    private static let starterPlatforms = [
        "美团", "微信", "线下消费", "京东", "拼多多", "淘宝", "抖音", "支付宝", "其他"
    ]

    private static let starterPayments = [
        "微信支付", "花呗", "支付宝", "银行卡", "京东白条", "美团月付", "先用后付"
    ]

    static func categoryCode(for rawValue: String?) -> String? {
        let value = clean(rawValue).lowercased()
        guard !value.isEmpty else { return nil }
        return categories.first { definition in
            definition.code == value || definition.aliases.contains { $0.lowercased() == value }
        }?.code
    }

    static func categoryTitle(for rawValue: String?) -> String? {
        guard let code = categoryCode(for: rawValue) else { return nil }
        return categories.first(where: { $0.code == code })?.title
    }

    static func options(
        kind: NativeFinanceVocabularyKind,
        currentValue: String?,
        vocabulary: [NativeFinanceVocabularyEntry],
        limit: Int = 12
    ) -> [NativeManualRecordOption] {
        var candidates: [String: Candidate] = [:]

        func normalized(_ rawValue: String?) -> String? {
            if kind == .category { return categoryCode(for: rawValue) }
            let value = clean(rawValue)
            return value.isEmpty ? nil : value
        }

        func register(
            _ rawValue: String?,
            usageCount: Int = 0,
            lastUsedAt: String = "",
            isCurrent: Bool = false,
            starterOrder: Int = .max
        ) {
            guard let value = normalized(rawValue) else { return }
            var candidate = candidates[value] ?? Candidate(value: value)
            candidate.usageCount = max(candidate.usageCount, usageCount)
            candidate.lastUsedAt = max(candidate.lastUsedAt, lastUsedAt)
            candidate.isCurrent = candidate.isCurrent || isCurrent
            candidate.starterOrder = min(candidate.starterOrder, starterOrder)
            candidates[value] = candidate
        }

        register(currentValue, isCurrent: true)
        vocabulary
            .filter { $0.kind == kind && $0.status == "active" }
            .forEach {
                register(
                    $0.displayName,
                    usageCount: $0.usageCount,
                    lastUsedAt: $0.lastUsedAt
                )
            }

        let starters: [String]
        switch kind {
        case .platform: starters = starterPlatforms
        case .category: starters = categories.map(\.code)
        case .payment: starters = starterPayments
        }
        for (index, value) in starters.enumerated() {
            register(value, starterOrder: index)
        }

        return candidates.values
            .sorted {
                if $0.isCurrent != $1.isCurrent { return $0.isCurrent }
                if $0.usageCount != $1.usageCount { return $0.usageCount > $1.usageCount }
                if $0.lastUsedAt != $1.lastUsedAt { return $0.lastUsedAt > $1.lastUsedAt }
                return $0.starterOrder < $1.starterOrder
            }
            .prefix(max(1, limit))
            .map { candidate in
                NativeManualRecordOption(
                    id: candidate.value,
                    title: kind == .category
                        ? categoryTitle(for: candidate.value) ?? "其他"
                        : candidate.value,
                    isFrequent: candidate.usageCount >= 2
                )
            }
    }

    private static func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
