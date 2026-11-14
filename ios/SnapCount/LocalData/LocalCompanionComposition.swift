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
        return LocalCompanionResult(
            companionMessage: envelope.data?.companionMessage,
            aiFeedback: envelope.data?.aiFeedback
        )
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
        if candidate.dimension == "current_fact", let amount = fact.amount, amount.isFinite {
            payload["numbers"] = [amount]
            payload["count_numbers"] = []
            payload["number_facts"] = [[
                "value": amount,
                "meaning": "amount",
                "role": "measure",
                "evidence": [[
                    "kind": "current_fact",
                    "source": "local_record",
                    "reference": fact.id,
                    "field": "amount"
                ]]
            ]]
        } else {
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
        let companion = LocalCompanionCompositionSupport.clipped(object["companion_message"] as? String, max: 30)
        let feedback: [String: AnyCodable]?
        if let feedbackObject = object["ai_feedback"] as? [String: Any],
           let emotion = LocalCompanionCompositionSupport.clipped(feedbackObject["emotion_line"] as? String, max: 28),
           !emotion.isEmpty {
            let confidence = LocalCompanionCompositionSupport.normalizedConfidence(feedbackObject["confidence"]) ?? 0.7
            if confidence >= 0.5 {
                let domain = context.currentFact.domainKey
                let band = LocalCompanionCompositionSupport.allowedBands.contains(feedbackObject["band"] as? String ?? "")
                    ? (feedbackObject["band"] as? String ?? "neutral")
                    : "neutral"
                feedback = [
                    "version": AnyCodable("feedback-v1"),
                    "domain_key": AnyCodable(domain),
                    "badge": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["badge"] as? String, max: 10) ?? "即时反馈"),
                    "icon": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["icon"] as? String, max: 4) ?? LocalCompanionCompositionSupport.icon(for: domain)),
                    "band": AnyCodable(band),
                    "tone": AnyCodable("ai_generated"),
                    "emotion_line": AnyCodable(emotion),
                    "utility_line": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["utility_line"] as? String, max: 30) ?? NSNull()),
                    "detail_reason": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["detail_reason"] as? String, max: 60) ?? NSNull()),
                    "confidence": AnyCodable(confidence),
                    "internal_score": AnyCodable(Int((confidence * 100).rounded())),
                    "source": AnyCodable("hybrid")
                ]
            } else {
                feedback = nil
            }
        } else {
            feedback = nil
        }
        guard companion != nil || feedback != nil else { throw QwenBYOKError.invalidResponse }
        return LocalCompanionResult(companionMessage: companion, aiFeedback: feedback)
    }
}

private enum LocalCompanionCompositionSupport {
    static let allowedBands: Set<String> = ["positive", "neutral", "watch", "recover", "ritual"]

    static func clipped(_ value: String?, max: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized.count <= max ? normalized : String(normalized.prefix(max))
    }

    static func normalizedConfidence(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? Double { number = value }
        else if let value = value as? NSNumber { number = value.doubleValue }
        else if let value = value as? String { number = Double(value) }
        else { number = nil }
        guard let number, number.isFinite else { return nil }
        return min(1, max(0, number))
    }

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
