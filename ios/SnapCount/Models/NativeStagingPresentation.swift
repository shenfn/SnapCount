import Foundation

struct NativeStagingDisplayField: Identifiable, Equatable {
    let key: String
    let label: String
    let value: String

    var id: String { key }
}

enum NativeStagingDetailPresentation {
    private static let fields: [(key: String, label: String)] = [
        ("amount", "金额"),
        ("merchant_name", "商家名称"),
        ("source_name", "来源名称"),
        ("platform", "消费渠道"),
        ("category", "分类"),
        ("payment_method", "支付方式"),
        ("income_category", "收入类型"),
        ("transaction_date", "消费日期"),
        ("income_date", "到账日期"),
        ("occurred_at", "发生时间"),
        ("sport_type", "运动类型"),
        ("activity_type", "运动类型"),
        ("duration_minutes", "时长"),
        ("distance_km", "距离"),
        ("calories", "消耗热量"),
        ("sleep_minutes", "睡眠时长"),
        ("quality_level", "质量等级"),
        ("quality_score", "质量评分"),
        ("book_name", "书名"),
        ("reading_minutes", "阅读时长"),
        ("pages", "阅读页数"),
        ("meal_type", "餐次"),
        ("total_calorie_kcal", "总热量"),
        ("account_name", "账户名称"),
        ("snapshot_balance", "账户金额"),
        ("account_type", "账户类型"),
        ("due_date", "还款日期"),
        ("note", "备注"),
        ("title", "标题"),
        ("summary", "摘要")
    ]

    private static let hiddenKeys: Set<String> = [
        "ai_feedback", "ai_summary", "companion_message", "confidence", "failure_reason",
        "image_type", "payload_jsonb", "raw_text", "record_type", "time_context"
    ]

    private static let aliases: [String: [String]] = [
        "calories": ["calories_kcal"],
        "sleep_minutes": ["sleep_hours"],
        "pages": ["pages_read"]
    ]

    static func fields(for record: NativeStagingRecord) -> [NativeStagingDisplayField] {
        let nestedPayload = record.extracted.dictionary("payload_jsonb") ?? [:]
        let merged = record.extracted.merging(nestedPayload) { current, _ in current }
        return fields.compactMap { key, label in
            guard !hiddenKeys.contains(key),
                  let (resolvedKey, raw) = resolvedValue(for: key, in: merged),
                  let value = displayValue(raw, key: resolvedKey) else {
                return nil
            }
            return NativeStagingDisplayField(key: key, label: label, value: value)
        }
    }

    private static func resolvedValue(
        for key: String,
        in values: [String: AnyCodable]
    ) -> (String, AnyCodable)? {
        for candidate in [key] + (aliases[key] ?? []) {
            if let value = values[candidate], !(value.value is NSNull) {
                return (candidate, value)
            }
        }
        return nil
    }

    static func errorSummary(_ message: String) -> String {
        let lowered = message.lowercased()
        if lowered.contains("row-level security") || lowered.contains("rls") {
            return "归档权限校验失败，请刷新登录状态后重试。"
        }
        if lowered.contains("token limit") || lowered.contains("exceeded model token") {
            return "识别内容超过模型处理上限，请重新识别。"
        }
        if lowered.contains("timed out") || lowered.contains("timeout") {
            return "AI 服务本次未能在时限内完成识别，请稍后重试。"
        }
        if lowered.contains("unsupported model") || lowered.contains("all vision providers failed") {
            return "当前识别服务暂时不可用，请稍后重新识别。"
        }
        return message.count > 120 ? String(message.prefix(120)) + "…" : message
    }

    private static func displayValue(_ raw: AnyCodable, key: String) -> String? {
        if raw.value is NSNull { return nil }
        if let number = raw.value as? NSNumber {
            let value = number.doubleValue
            switch key {
            case "amount", "snapshot_balance": return String(format: "¥%.2f", value)
            case "duration_minutes", "sleep_minutes", "reading_minutes": return "\(Int(value.rounded())) 分钟"
            case "sleep_hours": return String(format: "%.2f 小时", value)
            case "distance_km": return String(format: "%.2f km", value)
            case "calories", "calories_kcal", "total_calorie_kcal": return "\(Int(value.rounded())) 千卡"
            case "pages", "pages_read": return "\(Int(value.rounded())) 页"
            default: return number.stringValue
            }
        }
        guard let value = raw.value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if key == "meal_type" {
            return ["breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐", "snack": "加餐"][trimmed] ?? trimmed
        }
        return trimmed
    }
}
