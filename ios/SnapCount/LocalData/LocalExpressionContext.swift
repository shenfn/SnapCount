import Foundation

enum LocalExpressionProviderMode: String, Equatable {
    case hosted
    case byok
    case deterministic
}

struct LocalExpressionFact: Equatable {
    let id: String
    let domainKey: String
    let title: String
    let summary: String
    let recordDate: String?
    let recordTime: String?
    let amount: Double?
    let category: String?
    let payloadJSON: String?

    init(detail: NativeRecordDetail) {
        id = detail.rawId
        if let domainKey = detail.domainKey, !domainKey.isEmpty {
            self.domainKey = domainKey
        } else {
            self.domainKey = detail.kind
        }
        title = detail.title
        summary = detail.value
        recordDate = detail.recordDate
        recordTime = detail.transactionTime
        amount = detail.amount
        category = detail.category
        if let payload = detail.payload,
           let data = try? JSONEncoder().encode(payload) {
            payloadJSON = String(data: data, encoding: .utf8)
        } else {
            payloadJSON = nil
        }
    }

    init(
        id: String,
        domainKey: String,
        title: String,
        summary: String,
        recordDate: String?,
        recordTime: String?,
        amount: Double?,
        category: String?,
        payloadJSON: String? = nil
    ) {
        self.id = id
        self.domainKey = domainKey
        self.title = title
        self.summary = summary
        self.recordDate = recordDate
        self.recordTime = recordTime
        self.amount = amount
        self.category = category
        self.payloadJSON = payloadJSON
    }
}

struct LocalExpressionContext: Equatable {
    let currentFact: LocalExpressionFact
    let recentFacts: [LocalExpressionFact]
    let memoryContextJSON: String?
    let plannerCandidates: [NativeAIFeedback]
    let providerMode: LocalExpressionProviderMode
    var expressionPreferences = LocalCompanionExpressionPreferences.default
    var clientLocalTime: String? = nil
    var weekday: String? = nil
    var recentCompanionLines: [String] = []
}

struct LocalCompanionExpressionPreferences: Equatable {
    let persona: String
    let memoryStrength: String
    let expressionStyle: String
    let customNote: String?

    static let `default` = LocalCompanionExpressionPreferences(
        persona: "observer",
        memoryStrength: "balanced",
        expressionStyle: "plain",
        customNote: nil
    )

    init(settings: NativeUserSettings) {
        persona = settings.companionPersona
        memoryStrength = settings.companionMemoryStrength
        expressionStyle = settings.companionExpressionStyle
        let note = settings.companionCustomNote.trimmingCharacters(in: .whitespacesAndNewlines)
        customNote = note.isEmpty ? nil : String(note.prefix(80))
    }

    private init(persona: String, memoryStrength: String, expressionStyle: String, customNote: String?) {
        self.persona = persona
        self.memoryStrength = memoryStrength
        self.expressionStyle = expressionStyle
        self.customNote = customNote
    }
}

/// Deterministic local Planner seed. It supplies stable, evidence-backed
/// candidates while Hosted/BYOK composition is still optional.
enum LocalPlannerCandidateEngine {
    static let supportedDomains: Set<String> = [
        "expense", "income", "food", "sleep", "sport", "reading", "wallet"
    ]

    static func makeContext(
        for detail: NativeRecordDetail,
        recentFacts: [LocalExpressionFact] = [],
        memoryContextJSON: String? = nil,
        providerMode: LocalExpressionProviderMode = .deterministic,
        expressionPreferences: LocalCompanionExpressionPreferences = .default,
        clientLocalTime: String? = nil,
        weekday: String? = nil,
        recentCompanionLines: [String] = [],
        now: Date = Date()
    ) -> LocalExpressionContext {
        let currentFact = LocalExpressionFact(detail: detail)
        let localTime = Self.localTimeContext(for: now)
        return LocalExpressionContext(
            currentFact: currentFact,
            recentFacts: recentFacts,
            memoryContextJSON: memoryContextJSON,
            plannerCandidates: candidates(for: currentFact, memoryContextJSON: memoryContextJSON),
            providerMode: providerMode,
            expressionPreferences: expressionPreferences,
            clientLocalTime: clientLocalTime ?? localTime.time,
            weekday: weekday ?? localTime.weekday,
            recentCompanionLines: Array(recentCompanionLines.prefix(5))
        )
    }

    static func candidates(
        for fact: LocalExpressionFact,
        memoryContextJSON: String? = nil
    ) -> [NativeAIFeedback] {
        let domain = supportedDomains.contains(fact.domainKey) ? fact.domainKey : "expense"
        let semanticKey = "local_\(domain)_current_fact"
        let fingerprint = LocalImageStore.sha256(Data([
            domain, fact.id, fact.title, fact.summary, fact.recordDate ?? "", fact.recordTime ?? "",
            fact.amount.map { String(format: "%.2f", $0) } ?? "", fact.category ?? "",
            fact.payloadJSON ?? ""
        ].joined(separator: "|").utf8))
        let candidateID = "local-planner-\(domain)-\(String(fingerprint.prefix(16)))"
        let title = fact.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = title.isEmpty ? domainLabel(domain) : title
        let emotionLine: String
        let utilityLine: String
        let detailReason: String
        switch domain {
        case "expense":
            let amount = fact.amount.map { String(format: "¥%.2f", $0) } ?? "这笔"
            emotionLine = "这笔\(subject)消费已记录，金额为\(amount)。"
            utilityLine = "保留分类和时间，之后可以和近期同类消费对照。"
            detailReason = "候选来自当前消费的金额、商户和分类字段。"
        case "income":
            emotionLine = "这笔\(subject)收入已记录。"
            utilityLine = "保留来源和日期，之后可以观察收入节奏。"
            detailReason = "候选来自当前收入的来源、金额和日期字段。"
        case "food":
            emotionLine = "这条饮食记录已保留。"
            utilityLine = "之后可以结合近期饮食记录观察自己的选择。"
            detailReason = "候选来自当前饮食记录的结构化字段。"
        case "sleep":
            emotionLine = "这条睡眠记录已保留。"
            utilityLine = "之后可以结合近期记录观察作息变化。"
            detailReason = "候选来自当前睡眠记录的时长和时间字段。"
        case "sport":
            emotionLine = "这条运动记录已保留。"
            utilityLine = "之后可以结合近期记录观察运动连续性。"
            detailReason = "候选来自当前运动记录的类型、时长和日期字段。"
        case "reading":
            emotionLine = "这条阅读记录已保留。"
            utilityLine = "之后可以结合近期记录观察阅读连续性。"
            detailReason = "候选来自当前阅读记录的主题、时长和日期字段。"
        case "wallet":
            emotionLine = "这条钱包快照已保留。"
            utilityLine = "之后可以结合后续快照对照余额变化。"
            detailReason = "候选来自当前钱包快照的余额和日期字段。"
        default:
            emotionLine = "这条记录已保留。"
            utilityLine = "之后可以结合近期记录继续观察。"
            detailReason = "候选来自当前本地事实。"
        }

        let payload: [String: AnyCodable] = [
            "candidate_id": AnyCodable(candidateID),
            "semantic_key": AnyCodable(semanticKey),
            "claim_fingerprint": AnyCodable(fingerprint),
            "exposure_event_id": AnyCodable("local:\(fingerprint)"),
            "presentation_target": AnyCodable("feedback_card"),
            "dimension": AnyCodable("current_fact"),
            "source": AnyCodable("expression_planner"),
            "icon": AnyCodable("sparkles"),
            "badge": AnyCodable("本地 Planner"),
            "band": AnyCodable("neutral"),
            "emotion_line": AnyCodable(emotionLine),
            "utility_line": AnyCodable(utilityLine),
            "detail_reason": AnyCodable(detailReason),
            "timing_signal": AnyCodable(["label": fact.recordDate ?? "本地事实"] as [String: Any]),
            "local_exposure": AnyCodable(true)
        ]
        guard let feedback = NativeAIFeedback(payload: payload) else { return [] }
        var result = [feedback]
        if let memory = firstMemory(from: memoryContextJSON, matching: fact) {
            let memoryKey = memory.key
            let memoryFingerprint = LocalImageStore.sha256(Data("\(fact.id)|\(memoryKey)".utf8))
            let memoryLine = memory.value.map { "结合本地记忆：\(String($0.prefix(44)))" }
                ?? "结合你保存的本地偏好，这条记录可以继续观察。"
            let memoryPayload: [String: AnyCodable] = [
                "candidate_id": AnyCodable("local-planner-\(domain)-memory-\(String(memoryFingerprint.prefix(16)))"),
                "semantic_key": AnyCodable("local_\(domain)_memory_context"),
                "claim_fingerprint": AnyCodable(memoryFingerprint),
                "exposure_event_id": AnyCodable("local:\(memoryFingerprint)"),
                "presentation_target": AnyCodable("feedback_card"),
                "dimension": AnyCodable("memory_context"),
                "source": AnyCodable("expression_planner"),
                "icon": AnyCodable("person.crop.circle.badge.checkmark"),
                "badge": AnyCodable("本地记忆角度"),
                "band": AnyCodable("ritual"),
                "emotion_line": AnyCodable(memoryLine),
                "utility_line": AnyCodable("记忆只用于调整观察角度，不改变这条记录的事实。"),
                "detail_reason": AnyCodable("候选引用本地记忆键 \(memoryKey)，并保留当前记录作为事实依据。"),
                "timing_signal": AnyCodable(["label": "本地记忆"] as [String: Any]),
                "local_exposure": AnyCodable(true)
            ]
            if let memoryFeedback = NativeAIFeedback(payload: memoryPayload) {
                result.append(memoryFeedback)
            }
        }
        return result
    }

    static func selectedCandidate(
        for fact: LocalExpressionFact,
        memoryContextJSON: String? = nil
    ) -> NativeAIFeedback? {
        let candidates = candidates(for: fact, memoryContextJSON: memoryContextJSON)
        guard let current = candidates.first else { return nil }
        guard let memory = candidates.first(where: { $0.dimension == "memory_context" }) else {
            return current
        }
        // The current fact remains the default. A high-confidence memory angle
        // may lead only when it has stronger evidence than that threshold.
        return memoryConfidence(from: memoryContextJSON) >= 0.8 ? memory : current
    }

    private static func firstMemory(
        from json: String?,
        matching fact: LocalExpressionFact
    ) -> (key: String, value: String?)? {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let facts = object["facts"] as? [[String: Any]] else { return nil }
        let currentTitle = canonicalEntity(fact.title)
        let currentCategory = canonicalEntity(fact.category ?? "")
        for memory in facts {
            guard let key = memory["key"] as? String, !key.isEmpty,
                  let entityType = memory["entity_type"] as? String,
                  let entityValue = memory["entity_value"] as? String else { continue }
            let expected = entityType == "category" ? currentCategory : currentTitle
            guard !expected.isEmpty, expected == canonicalEntity(entityValue) else { continue }
            return (key, memory["value"] as? String)
        }
        return nil
    }

    private static func canonicalEntity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func localTimeContext(for date: Date) -> (time: String, weekday: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let time = formatter.string(from: date)
        let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekdayIndex = Calendar.current.component(.weekday, from: date) - 1
        let weekday = weekdays.indices.contains(weekdayIndex) ? weekdays[weekdayIndex] : ""
        return (time, weekday)
    }

    private static func memoryConfidence(from json: String?) -> Double {
        guard let json,
              let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let facts = object["facts"] as? [[String: Any]],
              let confidence = facts.first?["confidence"] as? NSNumber else { return 0 }
        return max(0, min(1, confidence.doubleValue))
    }

    private static func domainLabel(_ domain: String) -> String {
        switch domain {
        case "expense": return "消费"
        case "income": return "收入"
        case "food": return "饮食"
        case "sleep": return "睡眠"
        case "sport": return "运动"
        case "reading": return "阅读"
        case "wallet": return "钱包"
        default: return "记录"
        }
    }
}

extension NativeAIFeedback {
    var localPayload: [String: AnyCodable] {
        var payload: [String: AnyCodable] = [
            "candidate_id": AnyCodable(candidateId ?? ""),
            "semantic_key": AnyCodable(semanticKey),
            "claim_fingerprint": AnyCodable(claimFingerprint),
            "presentation_target": AnyCodable(presentationTarget),
            "dimension": AnyCodable(dimension),
            "source": AnyCodable(source),
            "icon": AnyCodable(icon),
            "badge": AnyCodable(badge),
            "band": AnyCodable(band),
            "emotion_line": AnyCodable(emotionLine),
            "utility_line": AnyCodable(utilityLine),
            "detail_reason": AnyCodable(detailReason),
            "timing_signal": AnyCodable(["label": timingLabel] as [String: Any])
        ]
        if let exposureEventId { payload["exposure_event_id"] = AnyCodable(exposureEventId) }
        return payload
    }
}
