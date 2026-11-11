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
            plannerCandidate: selected?.localPayload.mapValues(\.value),
            localMemoryContext: LocalCompanionCompositionSupport.jsonObject(context.memoryContextJSON) as? [String: Any],
            expressionPreferences: Self.preferencesPayload(context.expressionPreferences),
            clientLocalTime: context.clientLocalTime,
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
        var payload: [String: Any] = [
            "id": fact.id,
            "domain_key": fact.domainKey,
            "title": fact.title,
            "merchant_name": fact.domainKey == "expense" ? fact.title : NSNull(),
            "source_name": fact.domainKey == "income" ? fact.title : NSNull(),
            "summary": fact.summary,
            "record_date": fact.recordDate ?? NSNull(),
            "record_time": fact.recordTime ?? NSNull(),
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
        facts["planner_candidate"] = selected?.localPayload.mapValues(\.value) ?? NSNull()
        facts["expression_preferences"] = HostedAICompanionProvider.preferencesPayload(context.expressionPreferences)
        facts["client_local_time"] = context.clientLocalTime ?? NSNull()
        facts["weekday"] = context.weekday ?? NSNull()
        facts["recent_companion_lines"] = Array(context.recentCompanionLines.prefix(5))
        if let memory = LocalCompanionCompositionSupport.jsonObject(context.memoryContextJSON) {
            facts["memory_context"] = memory
        }
        let factsData = try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
        let factsText = String(decoding: factsData, as: UTF8.self)
        let prompt = """
        你是芥子的本地陪伴文案生成器。下面是已保存的当前事实、Planner 候选和（若存在）紧凑记忆 JSON。
        只能根据这些证据表达，不要补写 JSON 没有的金额、日期、商户、频率或健康结论；记忆只能改变观察角度，不能修改当前事实。
        遵循 expression_preferences 中的说话风格；client_local_time 和 weekday 只用于自然把握此刻语境，不推断用户作息；recent_companion_lines 只用于避免重复句式。
        返回一个 JSON 对象，不能返回 Markdown。字段为 companion_message 和 ai_feedback。
        companion_message 是一句 8 到 30 字的陪伴语；ai_feedback 包含 badge、icon、band、emotion_line、utility_line、detail_reason、confidence。
        band 只能是 positive、neutral、watch、recover、ritual；emotion_line 不超过 30 字，utility_line 不超过 32 字，detail_reason 不超过 64 字；confidence 为 0 到 1 的数字且至少 0.5。
        不要机械复述“已记录”，也不要把建议写成诊断或命令。依据不足时 utility_line 或 detail_reason 可为 null。

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
              let object = LocalCompanionCompositionSupport.jsonObject(from: content),
              let companion = LocalCompanionCompositionSupport.clipped(object["companion_message"] as? String, max: 30),
              let feedbackObject = object["ai_feedback"] as? [String: Any] else {
            throw QwenBYOKError.invalidResponse
        }
        guard let emotion = LocalCompanionCompositionSupport.clipped(feedbackObject["emotion_line"] as? String, max: 30),
              !emotion.isEmpty else {
            throw QwenBYOKError.invalidResponse
        }
        let confidence = LocalCompanionCompositionSupport.normalizedConfidence(feedbackObject["confidence"]) ?? 0.7
        guard confidence >= 0.5 else { throw QwenBYOKError.invalidResponse }
        let domain = context.currentFact.domainKey
        let band = LocalCompanionCompositionSupport.allowedBands.contains(feedbackObject["band"] as? String ?? "")
            ? (feedbackObject["band"] as? String ?? "neutral")
            : "neutral"
        let feedback: [String: AnyCodable] = [
            "version": AnyCodable("feedback-v1"),
            "domain_key": AnyCodable(domain),
            "badge": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["badge"] as? String, max: 10) ?? "即时反馈"),
            "icon": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["icon"] as? String, max: 4) ?? LocalCompanionCompositionSupport.icon(for: domain)),
            "band": AnyCodable(band),
            "tone": AnyCodable("ai_generated"),
            "emotion_line": AnyCodable(emotion),
            "utility_line": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["utility_line"] as? String, max: 32) ?? NSNull()),
            "detail_reason": AnyCodable(LocalCompanionCompositionSupport.clipped(feedbackObject["detail_reason"] as? String, max: 64) ?? NSNull()),
            "confidence": AnyCodable(confidence),
            "internal_score": AnyCodable(Int((confidence * 100).rounded())),
            "source": AnyCodable("hybrid")
        ]
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
