import Foundation

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
    private static let maximumImageBytes = 20 * 1024 * 1024

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
              request.imageData.count <= Self.maximumImageBytes else {
            throw QwenBYOKError.invalidImage
        }

        let prompt = """
        你是芥子的图片识别器。只识别图片中与个人记录有关的可见事实，不推断未显示的信息，不执行记账或外部操作。
        返回一个 JSON 对象，字段为 schema_version、operation、candidate。schema_version 固定为 local-recognition-candidate-v1，operation 固定为 recognize_only。
        candidate 字段为 id、domain_key、title、summary、payload、confidence、record_date、record_time、occurred_at、evidence_fields、missing_fields、image_hash。
        domain_key 只能是 expense、food、sleep、sport、reading。无法可靠识别时给出保守标题、confidence 0、并把缺失字段列入 missing_fields；不得编造金额、时间或日期。日期使用 YYYY-MM-DD。
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
        return LocalRecognitionCandidate(
            id: candidate.id ?? UUID().uuidString,
            domainKey: domainKey,
            title: title,
            summary: summary,
            payload: candidate.payload ?? [:],
            confidence: candidate.confidence,
            recordDate: recordDate,
            recordTime: candidate.recordTime,
            occurredAt: candidate.occurredAt,
            evidenceFields: candidate.evidenceFields ?? [],
            missingFields: candidate.missingFields ?? [],
            imageHash: candidate.imageHash
        )
    }
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

        enum CodingKeys: String, CodingKey {
            case id, title, summary, payload, confidence
            case domainKey = "domain_key"
            case recordDate = "record_date"
            case recordTime = "record_time"
            case occurredAt = "occurred_at"
            case evidenceFields = "evidence_fields"
            case missingFields = "missing_fields"
            case imageHash = "image_hash"
        }
    }
}
