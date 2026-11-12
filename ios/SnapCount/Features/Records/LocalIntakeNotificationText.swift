import Foundation

struct LocalIntakeNotificationInput {
    let domainKey: String
    let feedback: NativeAIFeedback?
    let confidence: Double?
    let companionMessage: String?
    let amountMinor: Int64?
    let merchantName: String?
    let category: String?
    let sourceName: String?
    let todaySpendMinor: Int64
    let todaySpendCount: Int
    let monthIncomeMinor: Int64
    let isPending: Bool
}

/// 复刻 PWA 后端 ingest-receipt 的通知文案拼接：先算域 fallback，再叠 companion / AI 反馈。
enum LocalIntakeNotificationText {
    static func compose(_ input: LocalIntakeNotificationInput) -> String {
        let fallback = fallbackText(input)
        if let companionLine = compactFeedbackText(input.companionMessage, max: 34) {
            return uniqueNotificationLines([companionLine] + fallbackLines(fallback)).joined(separator: "\n")
        }
        if let feedback = input.feedback,
           input.confidence == nil || input.confidence! >= 0.5 {
            let fallbackLines = fallbackLines(fallback)
            let feedbackLines: [String] = [
                "\(feedback.icon) \(feedback.badge)",
                compactFeedbackText(feedback.emotionLine, max: 34),
                compactFeedbackText(feedback.utilityLine, max: 34) ?? fallbackLines.first
            ].compactMap { $0 } + fallbackLines
            return uniqueNotificationLines(feedbackLines).joined(separator: "\n")
        }
        return fallback
    }

    // MARK: - fallback

    private static func fallbackText(_ input: LocalIntakeNotificationInput) -> String {
        switch input.domainKey {
        case "income": return incomeFallback(input)
        case "expense": return expenseFallback(input)
        default: return domainFallback(input.domainKey)
        }
    }

    private static func domainFallback(_ domainKey: String) -> String {
        let emoji: String
        switch domainKey {
        case "sport": emoji = "🏃"
        case "sleep": emoji = "🌙"
        case "reading": emoji = "📚"
        case "food": emoji = "🍱"
        default: emoji = "✓"
        }
        return "\(emoji) 已归档到\(domainNameFromKey(domainKey) ?? domainKey)"
    }

    private static func incomeFallback(_ input: LocalIntakeNotificationInput) -> String {
        let amount = fmtYuan(input.amountMinor)
        // 后端把「截图识别收入」当内部占位来源，不展示给用户（index.ts:7516）。
        let source = normalized(input.sourceName).flatMap { $0 == "截图识别收入" ? nil : $0 }
        let sourcePart = source.map { " · \($0)" } ?? ""
        return [
            "💰 +\(amount)\(sourcePart)",
            "本月已入 \(fmtYuan(input.monthIncomeMinor))"
        ].joined(separator: "\n")
    }

    private static func expenseFallback(_ input: LocalIntakeNotificationInput) -> String {
        let amount = fmtYuan(input.amountMinor)
        let merchantPart = normalized(input.merchantName).map { " · \($0)" } ?? ""
        let categoryPart = normalized(input.category).map { " · \($0)" } ?? ""
        let primary = input.isPending
            ? "⚠️ -\(amount)\(merchantPart) · 请打开 App 补全"
            : "💸 -\(amount)\(merchantPart)\(categoryPart)"
        let summary = input.todaySpendCount == 0
            ? "今日尚无支出记录"
            : "今日已花 \(fmtYuan(input.todaySpendMinor))（\(input.todaySpendCount) 笔）"
        return [primary, summary].joined(separator: "\n")
    }

    private static func domainNameFromKey(_ key: String) -> String? {
        switch key {
        case "expense": return "消费记账"
        case "income": return "收入记录"
        case "sport": return "运动记录"
        case "sleep": return "睡眠记录"
        case "food": return "饮食记录"
        case "reading": return "阅读记录"
        case "wallet": return "钱包与待还"
        default: return nil
        }
    }

    // MARK: - feedback

    private static func feedbackNotification(_ feedback: NativeAIFeedback) -> String {
        return uniqueNotificationLines([
            "\(feedback.icon) \(feedback.badge)",
            compactFeedbackText(feedback.emotionLine, max: 34) ?? "",
            compactFeedbackText(feedback.utilityLine, max: 34) ?? ""
        ])
            .joined(separator: "\n")
    }

    // MARK: - text helpers

    private static func fallbackLines(_ fallback: String) -> [String] {
        fallback
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 按行去重：比较 key 时把连续空白压成一个空格，保序
    private static func uniqueNotificationLines(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let line = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let key = line
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(line)
        }
        return result
    }

    private static func compactFeedbackText(_ value: String?, max: Int = 42) -> String? {
        guard let normalizedValue = normalized(value) else { return nil }
        let text = collapseLineBreaks(normalizedValue).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return text.count > max ? clipAtNaturalBoundary(text, max: max) : text
    }

    /// 连续换行压成一个空格，和 `/[\r\n]+/g` 一致
    private static func collapseLineBreaks(_ text: String) -> String {
        var result = ""
        var isInBreakRun = false
        for character in text {
            if character == "\n" || character == "\r" {
                if !isInBreakRun { result.append(" ") }
                isInBreakRun = true
            } else {
                result.append(character)
                isInBreakRun = false
            }
        }
        return result
    }

    /// 超长文案在标点处收尾，避免"看来你是真…"这种句中截断
    private static func clipAtNaturalBoundary(_ text: String, max: Int) -> String {
        let characters = Array(text)
        let head = Array(characters.prefix(max))
        let boundaries: [Character] = ["。", "！", "？", "；", "，", ","]
        var cut = -1
        for (index, character) in head.enumerated() where boundaries.contains(character) {
            cut = index
        }
        if cut >= max / 2 {
            return String(head.prefix(cut)) + "。"
        }
        return String(head.prefix(max - 1)) + "…"
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// C locale 下的两位小数，无千分位
    private static func fmtYuan(_ minor: Int64?) -> String {
        String(format: "¥%.2f", Double(minor ?? 0) / 100)
    }
}
