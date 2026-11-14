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

/// The provider-independent expression fields used by every local delivery
/// surface. Hosted and BYOK responses may use different transport models, but
/// notification composition must apply the same precedence and de-duplication.
struct LocalIntakeNotificationFeedback: Equatable {
    let icon: String
    let badge: String
    let confidence: Double?
    let emotionLine: String
    let utilityLine: String

    init(
        icon: String,
        badge: String,
        confidence: Double? = nil,
        emotionLine: String,
        utilityLine: String
    ) {
        self.icon = icon
        self.badge = badge
        self.confidence = confidence
        self.emotionLine = emotionLine
        self.utilityLine = utilityLine
    }

    init(_ feedback: NativeAIFeedback, confidence: Double? = nil) {
        self.init(
            icon: feedback.icon,
            badge: feedback.badge,
            confidence: confidence,
            emotionLine: feedback.emotionLine,
            utilityLine: feedback.utilityLine
        )
    }

    init(_ feedback: ShortcutAIFeedback) {
        self.init(
            icon: feedback.icon ?? "✨",
            badge: feedback.badge ?? "即时反馈",
            confidence: feedback.confidence,
            emotionLine: feedback.emotionLine ?? "",
            utilityLine: feedback.utilityLine ?? ""
        )
    }
}

/// 复刻 PWA 后端 ingest-receipt 的通知文案拼接：先算域 fallback，再叠 companion / AI 反馈。
enum LocalIntakeNotificationText {
    static func compose(_ input: LocalIntakeNotificationInput) -> String {
        let fallback = fallbackText(input)
        return merge(
            baseText: fallback,
            companionMessage: input.companionMessage,
            feedbackParts: input.feedback.map { LocalIntakeNotificationFeedback($0, confidence: input.confidence) }
        )
    }

    /// Composes one delivery block for AppState, Shortcut and the in-app
    /// result sheet. Fixed receipt facts are always retained after an
    /// expression, while duplicate lines are removed in their first-seen
    /// order.
    static func merge(
        baseText: String?,
        companionMessage: String?,
        feedbackParts: LocalIntakeNotificationFeedback?
    ) -> String {
        let fallbackLines = fallbackLines(baseText ?? "")
        if let companionLine = compactFeedbackText(companionMessage, max: 34) {
            return uniqueNotificationLines([companionLine] + fallbackLines).joined(separator: "\n")
        }
        if let feedback = feedbackParts,
           feedback.confidence == nil || feedback.confidence! >= 0.5 {
            let feedbackLines: [String?] = [
                "\(feedback.icon) \(feedback.badge)",
                compactFeedbackText(feedback.emotionLine, max: 34),
                compactFeedbackText(feedback.utilityLine, max: 34) ?? fallbackLines.first
            ]
            return uniqueNotificationLines(feedbackLines.compactMap { $0 } + fallbackLines)
                .joined(separator: "\n")
        }
        return fallbackLines.joined(separator: "\n")
    }

    /// Compatibility seam for existing local callers that already hold a
    /// native feedback model and a separate confidence value.
    /// Keeps the already-composed fixed receipt facts when a later local
    /// Companion call finishes. This mirrors the PWA notification contract:
    /// expression first, stable receipt facts after it.
    static func merge(
        baseText: String?,
        companionMessage: String?,
        feedback: NativeAIFeedback? = nil,
        confidence: Double? = nil
    ) -> String {
        merge(
            baseText: baseText,
            companionMessage: companionMessage,
            feedbackParts: feedback.map { LocalIntakeNotificationFeedback($0, confidence: confidence) }
        )
    }

    static func compose(
        baseText: String?,
        companionMessage: String?,
        feedback: LocalIntakeNotificationFeedback?
    ) -> String {
        merge(
            baseText: baseText,
            companionMessage: companionMessage,
            feedbackParts: feedback
        )
    }

    /// Keeps the system notification's line breaks while enforcing the
    /// existing 160-character budget.
    static func boundedNotificationText(_ text: String, maxCharacters: Int = 160) -> String {
        guard maxCharacters > 0 else { return "" }
        var lines: [String] = []
        var remaining = maxCharacters
        for raw in text.split(whereSeparator: \.isNewline) {
            guard remaining > 0 else { break }
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let available = max(0, remaining - (lines.isEmpty ? 0 : 1))
            guard available > 0 else { break }
            let clipped = line.count > available ? String(line.prefix(available)) : line
            lines.append(clipped)
            remaining -= clipped.count + (lines.count == 1 ? 0 : 1)
        }
        return lines.joined(separator: "\n")
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
