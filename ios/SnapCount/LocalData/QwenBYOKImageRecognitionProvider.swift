import Foundation
import ImageIO
import UniformTypeIdentifiers

enum QwenBYOKError: Error, Equatable, LocalizedError {
    case missingKey
    case invalidImage
    case invalidResponse
    case keyRejected
    case quotaUnavailable
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .missingKey: "未找到 BYOK API Key；图片仍保存在本机，可手动处理。"
        case .invalidImage: "图片数据无法安全发送给所选识别服务；原图仍保存在本机。"
        case .invalidResponse: "识别服务返回的数据无法安全解析；原图仍保存在本机。"
        case .keyRejected: "Qwen API Key 无效或未获此服务地域授权；原图仍保存在本机。"
        case .quotaUnavailable: "Qwen 当前额度或频率限制不可用；原图仍保存在本机。"
        case .serviceUnavailable: "Qwen 识别暂不可用；原图仍保存在本机，可稍后重试或手动处理。"
        }
    }
}

final class QwenBYOKImageRecognitionProvider: LocalImageRecognitionProvider {
    static let model = "qwen3.6-flash"
    static let endpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
    static let maximumImageBytes = 20 * 1024 * 1024

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func recognize(_ request: LocalImageRecognitionRequest) async throws -> LocalRecognitionCandidate {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QwenBYOKError.missingKey
        }
        guard !request.imageData.isEmpty,
              request.imageData.count <= Self.maximumImageBytes,
              Self.isValidJPEG(request.imageData) else {
            throw QwenBYOKError.invalidImage
        }

        let prompt = """
        你是芥子的图片识别器。只识别图片中与个人记录有关的可见事实，不推断未显示的信息，不执行记账或外部操作。
        返回一个 JSON 对象，字段为 schema_version、operation、candidate。schema_version 固定为 local-recognition-candidate-v1，operation 固定为 recognize_only。
        candidate 字段为 id、domain_key、title、summary、payload、confidence、record_date、record_time、occurred_at、evidence_fields、missing_fields、image_hash。
        domain_key 只能是 expense、income、food、sleep、sport、reading、wallet。expense 和 income 的 payload.amount 为截图显示的人民币元金额，收入仅在截图明确显示入账时输出 income；两类候选一律等待用户确认，不得自动记账。wallet 仅用于识别信用卡或信用额度的已还款截图，payload 必须明确包含 account_snapshot_kind=liability 或 record_kind=liability_snapshot，且 status=paid；未能从截图确认已付款时不得输出 wallet。wallet 候选只能交由用户复核，不得当作普通记录自动归档。无法可靠识别时给出保守标题、confidence 0、并把缺失字段列入 missing_fields；不得编造金额、时间或日期。日期使用 YYYY-MM-DD。
        """
        let body: [String: Any] = [
            "model": Self.model,
            "stream": false,
            "response_format": ["type": "json_object"],
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": [
                        "url": "data:image/jpeg;base64,\(request.imageData.base64EncodedString())"
                    ]]
                ]
            ]]
        ]
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
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
              let envelope = try? JSONDecoder().decode(ChatCompletionEnvelope.self, from: data),
              let content = envelope.choices.first?.message.content,
              let candidateData = content.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(QwenRecognitionEnvelope.self, from: candidateData),
              decoded.schemaVersion == "local-recognition-candidate-v1",
              decoded.operation == "recognize_only",
              let candidate = decoded.candidate,
              let domainKey = candidate.domainKey,
              let title = candidate.title,
              let summary = candidate.summary,
              let recordDate = candidate.recordDate else {
            throw QwenBYOKError.invalidResponse
        }
        let payload = candidate.payload ?? [:]
        let recognized = LocalRecognitionCandidate(
            id: candidate.id ?? UUID().uuidString,
            domainKey: domainKey,
            title: title,
            summary: summary,
            payload: payload,
            confidence: candidate.confidence,
            recordDate: recordDate,
            recordTime: candidate.recordTime,
            occurredAt: candidate.occurredAt,
            evidenceFields: candidate.evidenceFields ?? [],
            missingFields: candidate.missingFields ?? [],
            imageHash: candidate.imageHash,
            companionMessage: candidate.companionMessage ?? payload.string("companion_message"),
            aiFeedback: candidate.aiFeedback ?? payload.dictionary("ai_feedback")
        )
        return await addingVoiceFeedback(to: recognized)
    }

    private func addingVoiceFeedback(to candidate: LocalRecognitionCandidate) async -> LocalRecognitionCandidate {
        guard Self.shouldGenerateVoice(for: candidate),
              let voice = try? await generateVoiceFeedback(for: candidate) else {
            return candidate
        }
        return LocalRecognitionCandidate(
            id: candidate.id,
            domainKey: candidate.domainKey,
            title: candidate.title,
            summary: candidate.summary,
            payload: candidate.payload,
            confidence: candidate.confidence,
            recordDate: candidate.recordDate,
            recordTime: candidate.recordTime,
            occurredAt: candidate.occurredAt,
            evidenceFields: candidate.evidenceFields,
            missingFields: candidate.missingFields,
            imageHash: candidate.imageHash,
            companionMessage: voice.companionMessage,
            aiFeedback: voice.aiFeedback
        )
    }

    private static func shouldGenerateVoice(for candidate: LocalRecognitionCandidate) -> Bool {
        guard candidate.missingFields.isEmpty,
              let confidence = candidate.confidence else { return false }
        if ["expense", "income"].contains(candidate.domainKey) {
            return confidence >= 0.7
        }
        return ["food", "sleep", "sport", "reading", "wallet"].contains(candidate.domainKey)
            && confidence >= 0.75
    }

    private func generateVoiceFeedback(for candidate: LocalRecognitionCandidate) async throws -> QwenVoiceResult {
        let facts: [String: Any] = [
            "domain_key": candidate.domainKey,
            "title": candidate.title,
            "summary": candidate.summary,
            "payload": candidate.payload.mapValues(\.value),
            "record_date": candidate.recordDate,
            "record_time": candidate.recordTime ?? NSNull(),
            "occurred_at": candidate.occurredAt ?? NSNull(),
            "confidence": candidate.confidence ?? NSNull()
        ]
        let factsData = try JSONSerialization.data(withJSONObject: facts, options: [.sortedKeys])
        let factsText = String(decoding: factsData, as: UTF8.self)
        let prompt = """
        你是芥子的陪伴文案生成器。下面是已经由图片识别确认的事实 JSON。
        只根据这些事实生成自然、具体、克制的中文表达，不要添加 JSON 中没有的金额、时间、商家、频率、历史比较或健康结论。
        返回一个 JSON 对象，不能返回 Markdown。字段为 companion_message 和 ai_feedback。
        companion_message 是一句 8 到 30 字的陪伴语；ai_feedback 包含 badge、icon、band、emotion_line、utility_line、detail_reason、confidence。
        band 只能是 positive、neutral、watch、recover、ritual；emotion_line 不超过 30 字，utility_line 不超过 32 字，detail_reason 不超过 64 字；confidence 为 0 到 1 的数字。
        不要机械复述“已记录”“已落账”，也不要把建议写成诊断或命令。没有足够依据时，把 utility_line 或 detail_reason 设为 null。

        事实 JSON：
        \(factsText)
        """
        let body: [String: Any] = [
            "model": Self.model,
            "stream": false,
            "response_format": ["type": "json_object"],
            "temperature": 0.8,
            "messages": [["role": "user", "content": prompt]]
        ]
        let data = try await request(body: body)
        guard let envelope = try? JSONDecoder().decode(ChatCompletionEnvelope.self, from: data),
              let content = envelope.choices.first?.message.content,
              let object = Self.jsonObject(from: content),
              let companionMessage = Self.clipped(object["companion_message"] as? String, max: 30),
              let feedbackObject = object["ai_feedback"] as? [String: Any] else {
            throw QwenBYOKError.invalidResponse
        }
        guard let emotion = Self.clipped(feedbackObject["emotion_line"] as? String, max: 30),
              !emotion.isEmpty else {
            throw QwenBYOKError.invalidResponse
        }
        let confidence = Self.normalizedConfidence(feedbackObject["confidence"]) ?? 0.7
        guard confidence >= 0.5 else { throw QwenBYOKError.invalidResponse }
        let band = Self.allowedBands.contains(feedbackObject["band"] as? String ?? "")
            ? (feedbackObject["band"] as? String ?? "neutral")
            : "neutral"
        let feedback: [String: AnyCodable] = [
            "version": AnyCodable("feedback-v1"),
            "domain_key": AnyCodable(candidate.domainKey),
            "badge": AnyCodable(Self.clipped(feedbackObject["badge"] as? String, max: 10) ?? "即时反馈"),
            "icon": AnyCodable(Self.clipped(feedbackObject["icon"] as? String, max: 4) ?? Self.icon(for: candidate.domainKey)),
            "band": AnyCodable(band),
            "tone": AnyCodable("ai_generated"),
            "emotion_line": AnyCodable(emotion),
            "utility_line": AnyCodable(Self.clipped(feedbackObject["utility_line"] as? String, max: 32) ?? NSNull()),
            "detail_reason": AnyCodable(Self.clipped(feedbackObject["detail_reason"] as? String, max: 64) ?? NSNull()),
            "confidence": AnyCodable(confidence),
            "internal_score": AnyCodable(Int((confidence * 100).rounded())),
            "source": AnyCodable("hybrid")
        ]
        return QwenVoiceResult(companionMessage: companionMessage, aiFeedback: feedback)
    }

    private func request(body: [String: Any]) async throws -> Data {
        var urlRequest = URLRequest(url: Self.endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 60
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
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
        guard data.count <= 2 * 1024 * 1024 else { throw QwenBYOKError.invalidResponse }
        return data
    }

    private static let allowedBands: Set<String> = ["positive", "neutral", "watch", "recover", "ritual"]

    private static func clipped(_ value: String?, max: Int) -> String? {
        guard let value else { return nil }
        let normalized = value.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return normalized.count <= max ? normalized : String(normalized.prefix(max))
    }

    private static func normalizedConfidence(_ value: Any?) -> Double? {
        let number: Double?
        if let value = value as? Double { number = value }
        else if let value = value as? NSNumber { number = value.doubleValue }
        else if let value = value as? String { number = Double(value) }
        else { number = nil }
        guard let number, number.isFinite else { return nil }
        return min(1, max(0, number))
    }

    private static func jsonObject(from content: String) -> [String: Any]? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.hasPrefix("```")
            ? trimmed.split(separator: "\n").dropFirst().dropLast().joined(separator: "\n")
            : trimmed
        guard let data = candidate.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
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

    private static func isValidJPEG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let sourceType = CGImageSourceGetType(source),
              UTType(sourceType as String)?.conforms(to: .jpeg) == true else {
            return false
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1,
            kCGImageSourceShouldCacheImmediately: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) != nil
    }
}

private struct QwenVoiceResult {
    let companionMessage: String
    let aiFeedback: [String: AnyCodable]
}

private struct ChatCompletionEnvelope: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
    }
    let choices: [Choice]
}

private struct QwenRecognitionEnvelope: Decodable {
    let schemaVersion: String?
    let operation: String?
    let candidate: Candidate?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case operation, candidate
    }

    struct Candidate: Decodable {
        let id: String?
        let domainKey: String?
        let title: String?
        let summary: String?
        let payload: [String: AnyCodable]?
        let confidence: Double?
        let recordDate: String?
        let recordTime: String?
        let occurredAt: String?
        let evidenceFields: [String]?
        let missingFields: [String]?
        let imageHash: String?
        let companionMessage: String?
        let aiFeedback: [String: AnyCodable]?

        enum CodingKeys: String, CodingKey {
            case id, title, summary, payload, confidence
            case domainKey = "domain_key"
            case recordDate = "record_date"
            case recordTime = "record_time"
            case occurredAt = "occurred_at"
            case evidenceFields = "evidence_fields"
            case missingFields = "missing_fields"
            case imageHash = "image_hash"
            case companionMessage = "companion_message"
            case aiFeedback = "ai_feedback"
        }
    }
}
