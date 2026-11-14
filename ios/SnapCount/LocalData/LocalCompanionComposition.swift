import Foundation

struct LocalCompanionResult {
    let companionMessage: String?
    let aiFeedback: [String: AnyCodable]?
}

protocol LocalCompanionProvider {
    func compose(context: LocalExpressionContext) async throws -> LocalCompanionResult
}

/// Hosted composition sends the current fact, selected local Planner candidate,
/// and the bounded local-memory context when the user has enabled memory.
final class HostedAICompanionProvider: LocalCompanionProvider {
    private let accessToken: String
    private let service: SnapCountUploadService

    init(accessToken: String, service: SnapCountUploadService = SnapCountUploadService()) {
        self.accessToken = accessToken
        self.service = service
    }

    func compose(context: LocalExpressionContext) async throws -> LocalCompanionResult {
        let selected = LocalPlannerCandidateEngine.selectedCandidate(
            for: context.currentFact,
            recentFacts: context.recentFacts,
            memoryContextJSON: context.memoryContextJSON
        )
        let response = try await service.generateLocalExpression(
            currentFact: Self.factPayload(context.currentFact),
            plannerCandidate: Self.plannerPayload(selected, fact: context.currentFact),
            localMemoryContext: LocalCompanionCompositionSupport.jsonObject(context.memoryContextJSON) as? [String: Any],
            expressionPreferences: Self.preferencesPayload(context.expressionPreferences),
            clientLocalTime: context.clientLocalTime,
            clientCapturedAt: context.clientCapturedAt,
            weekday: context.weekday,
            recentCompanionLines: context.recentCompanionLines,
            accessToken: accessToken
        )
        guard let envelope = try? JSONDecoder().decode(HostedExpressionEnvelope.self, from: response),
              envelope.ok != false else {
            throw QwenBYOKError.invalidResponse
        }
        do {
            return try LocalCompanionResultNormalizer.normalize(
                companionMessage: envelope.data?.companionMessage,
                aiFeedback: envelope.data?.aiFeedback,
                domainKey: context.currentFact.domainKey,
                recentCompanionLines: context.recentCompanionLines
            )
        } catch {
            throw QwenBYOKError.invalidResponse
        }
    }

    static func factPayload(_ fact: LocalExpressionFact) -> [String: Any] {
        let merchant: Any = fact.domainKey == "expense" && !fact.title.isEmpty ? fact.title : NSNull()
        let source: Any = fact.domainKey == "income" ? (fact.sourceName ?? fact.title) : NSNull()
        var payload: [String: Any] = [
            "id": fact.id,
            "domain_key": fact.domainKey,
            "title": fact.title,
            "merchant_name": merchant,
            "source_name": source,
            "platform": fact.platform ?? NSNull(),
            "payment_method": fact.paymentMethod ?? NSNull(),
            "summary": fact.summary,
            "record_date": fact.recordDate ?? NSNull(),
            "record_time": fact.recordTime ?? NSNull(),
            "occurred_at": fact.occurredAt ?? NSNull(),
            "order_finished_at": fact.orderFinishedAt ?? NSNull(),
            "amount": fact.amount ?? NSNull(),
            "category": fact.category ?? NSNull()
        ]
        if var object = LocalCompanionCompositionSupport.jsonObject(fact.payloadJSON) as? [String: Any] {
            // Stored expressions are replay state, not evidence for a new AI
            // request. Keep the structural domain payload only.
            object.removeValue(forKey: "companion_message")
            object.removeValue(forKey: "ai_feedback")
            object.removeValue(forKey: "planner_ai_feedback")
            payload["payload_json"] = object
        }
        return payload
    }

    /// The cloud Planner brief carries its numeric evidence alongside the
    /// candidate. Keep the local candidate on that same contract so the
    /// shared Voice validator can apply the same evidence rules.
    static func plannerPayload(
        _ candidate: NativeAIFeedback?,
        fact: LocalExpressionFact
    ) -> [String: Any]? {
        guard let candidate else { return nil }
        var payload = candidate.localPayload.mapValues(\.value)
        // `canonical_text` is required by the Edge contract and the Swift
        // fingerprint is computed from it. Keep it byte-identical to
        // `emotion_line` so both clients recompute the same claim.
        payload["canonical_text"] = candidate.emotionLine
        if payload["numbers"] == nil {
            payload["numbers"] = []
            payload["count_numbers"] = []
            payload["number_facts"] = []
        }
        return payload
    }

    static func preferencesPayload(_ preferences: LocalCompanionExpressionPreferences) -> [String: Any] {
        var payload: [String: Any] = [
            "persona": preferences.persona,
            "memory_strength": preferences.memoryStrength,
            "expression_style": preferences.expressionStyle,
        ]
        if let customNote = preferences.customNote { payload["custom_note"] = customNote }
        return payload
    }
}

/// BYOK composition uses the same bounded evidence contract as the existing
/// image provider and may include the compact memory JSON when enabled.
final class QwenBYOKCompanionProvider: LocalCompanionProvider {
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func compose(context: LocalExpressionContext) async throws -> LocalCompanionResult {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QwenBYOKError.missingKey
        }
        let selected = LocalPlannerCandidateEngine.selectedCandidate(
            for: context.currentFact,
            recentFacts: context.recentFacts,
            memoryContextJSON: context.memoryContextJSON
        )
        var facts = HostedAICompanionProvider.factPayload(context.currentFact)
        facts["planner_candidate"] = HostedAICompanionProvider.plannerPayload(selected, fact: context.currentFact) ?? NSNull()
        facts["expression_preferences"] = HostedAICompanionProvider.preferencesPayload(context.expressionPreferences)
        facts["client_local_time"] = context.clientLocalTime ?? NSNull()
        facts["client_captured_at"] = context.clientCapturedAt ?? NSNull()
        facts["weekday"] = context.weekday ?? NSNull()
        facts["recent_companion_lines"] = Array(context.recentCompanionLines.prefix(5))
        if let memory = LocalCompanionCompositionSupport.jsonObject(context.memoryContextJSON) {
            facts["memory_context"] = memory
        }
        let factsData = try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
        let factsText = String(decoding: factsData, as: UTF8.self)
        let prompt = """
        你是芥子的本地陪伴文案生成器。下面的 current fact、planner candidate 和（若存在）local memory context 是唯一上下文来源。
        只能引用 current fact 或 planner candidate 中明确存在的数字、日期、商户、类别、频率和趋势；不能自行计算、回忆、补写或改变统计口径。
        local memory context 只用于调整语气和观察角度，不是当前事实来源；不要把其中的金额、次数或统计写成确定事实。
        occurred_at、record_date、record_time 和 client_local_time 只用于把握时间语境；不要把上传时间写成事件发生时间。
        遵循 expression_preferences 中的说话风格；recent_companion_lines 只用于避免重复句式。
        companion_message 是首选主表达，最多 30 个汉字；可返回空串。补充候选可放在 companion_candidates 中。
        ai_feedback 只有能补充不同信息时才输出，不要换句话重复主表达；依据不足时返回 null。
        companion_message、emotion_line 不主动给建议；utility_line 只能在事实支撑时给低风险、可选择的建议，禁止诊断、用药、强制要求以及“加油/注意身体/记得/超标/放纵”。
        不要机械复述“已记录”，不要质问式反问，不要把 food 类别或时间擅自写成早餐、午餐、晚餐。
        band 只能是 positive、neutral、watch、recover、ritual；emotion_line 不超过 28 字，utility_line 不超过 30 字，detail_reason 不超过 60 字；confidence 为 0 到 1 的数字。
        返回纯 JSON（不能返回 Markdown）：{"companion_message":"≤30字","companion_candidates":["≤30字备选一","≤30字备选二"],"ai_feedback":{"badge":"4-8字","icon":"图标","band":"positive|neutral|watch|recover|ritual","emotion_line":"≤28字","utility_line":"≤30字或null","detail_reason":"≤60字或null","confidence":0.0}}

        事实 JSON：
        \(factsText)
        """
        let body: [String: Any] = [
            "model": QwenBYOKImageRecognitionProvider.model,
            "stream": false,
            "response_format": ["type": "json_object"],
            "temperature": 0.8,
            "messages": [["role": "user", "content": prompt]]
        ]
        var request = URLRequest(url: QwenBYOKImageRecognitionProvider.endpoint)
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QwenBYOKError.serviceUnavailable
        }
        guard let http = response as? HTTPURLResponse else { throw QwenBYOKError.invalidResponse }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw QwenBYOKError.keyRejected
        case 429: throw QwenBYOKError.quotaUnavailable
        default: throw QwenBYOKError.serviceUnavailable
        }
        guard data.count <= 2 * 1024 * 1024,
              let envelope = try? JSONDecoder().decode(LocalChatCompletionEnvelope.self, from: data),
              let content = envelope.choices.first?.message.content,
              let object = LocalCompanionCompositionSupport.jsonObject(from: content) else {
            throw QwenBYOKError.invalidResponse
        }
        do {
            return try LocalCompanionResultNormalizer.normalize(
                companionMessage: object["companion_message"],
                aiFeedback: object["ai_feedback"],
                domainKey: context.currentFact.domainKey,
                recentCompanionLines: context.recentCompanionLines
            )
        } catch {
            throw QwenBYOKError.invalidResponse
        }
    }
}

/// Normalizes provider output at the shared boundary so Hosted and BYOK have
/// the same persistence schema and safety behavior.
internal enum LocalCompanionResultNormalizer {
    private static let allowedBands: Set<String> = ["positive", "neutral", "watch", "recover", "ritual"]

    static func normalize(
        companionMessage: Any?,
        aiFeedback: Any?,
        domainKey: String,
        recentCompanionLines: [String]
    ) throws -> LocalCompanionResult {
        let recent = Set(recentCompanionLines.compactMap { try? normalizedText($0, max: nil) })
        let companion = try normalizeCompanion(companionMessage, recent: recent)
        let feedback = try normalizeFeedback(aiFeedback, domainKey: domainKey, recent: recent)
        return LocalCompanionResult(companionMessage: companion, aiFeedback: feedback)
    }

    private static func normalizeCompanion(_ value: Any?, recent: Set<String>) throws -> String? {
        guard let raw = try normalizedText(value, max: nil) else { return nil }
        guard !recent.contains(raw) else { return nil }
        return String(raw.prefix(30))
    }

    private static func normalizeFeedback(_ value: Any?, domainKey: String, recent: Set<String>) throws -> [String: AnyCodable]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let object = dictionary(value) else { throw LocalCompanionResultNormalizerError.malformedFeedback }
        guard let confidenceValue = object["confidence"],
              let confidence = normalizedConfidence(confidenceValue) else {
            throw LocalCompanionResultNormalizerError.malformedFeedback
        }
        guard let emotion = try normalizedText(object["emotion_line"], max: 28) else {
            throw LocalCompanionResultNormalizerError.malformedFeedback
        }
        let badge = try normalizedText(object["badge"], max: 10) ?? "即时反馈"
        let icon = try normalizedText(object["icon"], max: 4) ?? icon(for: domainKey)
        let bandValue = try normalizedBand(object["band"])
        let utility = try normalizedText(object["utility_line"], max: 30)
        let detail = try normalizedText(object["detail_reason"], max: 60)
        guard confidence >= 0.5, !recent.contains(emotion) else { return nil }
        return [
            "version": AnyCodable("feedback-v1"),
            "domain_key": AnyCodable(domainKey),
            "badge": AnyCodable(badge),
            "icon": AnyCodable(icon),
            "band": AnyCodable(bandValue),
            "tone": AnyCodable("ai_generated"),
            "emotion_line": AnyCodable(emotion),
            "utility_line": AnyCodable(utility ?? NSNull()),
            "detail_reason": AnyCodable(detail ?? NSNull()),
            "confidence": AnyCodable(confidence),
            "internal_score": AnyCodable(Int((confidence * 100).rounded())),
            "source": AnyCodable("hybrid")
        ]
    }

    private static func normalizedText(_ value: Any?, max: Int?) throws -> String? {
        let value = unwrapped(value)
        guard let value, !(value is NSNull) else { return nil }
        guard let string = value as? String else { throw LocalCompanionResultNormalizerError.malformedFeedback }
        let normalized = string.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard let max else { return normalized }
        return String(normalized.prefix(max))
    }

    private static func normalizedBand(_ value: Any?) throws -> String {
        let value = unwrapped(value)
        guard let value, !(value is NSNull) else { return "neutral" }
        guard let band = value as? String else { throw LocalCompanionResultNormalizerError.malformedFeedback }
        return allowedBands.contains(band) ? band : "neutral"
    }

    private static func normalizedConfidence(_ value: Any) -> Double? {
        let value = unwrapped(value)
        let number: Double?
        if let value = value as? Double { number = value }
        else if let value = value as? NSNumber { number = value.doubleValue }
        else if let value = value as? String { number = Double(value) }
        else { number = nil }
        guard let number, number.isFinite else { return nil }
        return min(1, max(0, number))
    }

    private static func dictionary(_ value: Any) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        if let object = value as? [String: AnyCodable] { return object.mapValues(\.value) }
        return nil
    }

    private static func unwrapped(_ value: Any?) -> Any? {
        if let value = value as? AnyCodable { return value.value }
        return value
    }

    private static func icon(for domainKey: String) -> String {
        switch domainKey {
        case "sleep": return "🌙"
        case "sport": return "🏃"
        case "food": return "🍱"
        case "reading": return "📚"
        case "wallet": return "💳"
        case "income": return "💰"
        default: return "💸"
        }
    }
}

private enum LocalCompanionResultNormalizerError: Error {
    case malformedFeedback
}

private enum LocalCompanionCompositionSupport {
    static func jsonObject(_ json: String?) -> Any? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func jsonObject(from content: String) -> [String: Any]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix("```")
            ? trimmed.split(separator: "\n").dropFirst().dropLast().joined(separator: "\n")
            : trimmed
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func icon(for domainKey: String) -> String {
        switch domainKey {
        case "sleep": return "🌙"
        case "sport": return "🏃"
        case "food": return "🍱"
        case "reading": return "📚"
        case "wallet": return "💳"
        case "income": return "💰"
        default: return "💸"
        }
    }
}

private struct HostedExpressionEnvelope: Decodable {
    let ok: Bool?
    let data: Payload?

    struct Payload: Decodable {
        let companionMessage: String?
        let aiFeedback: [String: AnyCodable]?

        enum CodingKeys: String, CodingKey {
            case companionMessage = "companion_message"
            case aiFeedback = "ai_feedback"
        }
    }
}

private struct LocalChatCompletionEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}
