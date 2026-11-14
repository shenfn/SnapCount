import Foundation

enum SnapCountUploadServiceError: LocalizedError {
    case missingConfig
    case invalidURL
    case invalidResponse
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "缺少 iOS 上传配置，请先配置 IOS_SUPABASE_URL、IOS_SUPABASE_FUNCTIONS_URL 和 IOS_SUPABASE_ANON_KEY。"
        case .invalidURL:
            return "上传地址无效"
        case .invalidResponse:
            return "上传接口返回无效"
        case .requestFailed(let message):
            return message
        }
    }
}

final class SnapCountUploadService {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let functionsURLOverride: String?
    private let anonKeyOverride: String?

    init(
        session: URLSession = .shared,
        functionsURL: String? = nil,
        anonKey: String? = nil
    ) {
        self.session = session
        self.functionsURLOverride = functionsURL
        self.anonKeyOverride = anonKey
    }

    func uploadShortcutImage(
        data: Data,
        uploadToken: String,
        captureKind: String = "screenshot",
        filename: String = "shortcut-screenshot.jpg"
    ) async throws -> String {
        try await uploadImage(
            data: data,
            uploadToken: uploadToken,
            sourceApp: "ios_app_intent",
            captureKind: captureKind,
            filename: filename,
            mimeType: "image/jpeg"
        )
    }

    func uploadShortcutImageResult(
        data: Data,
        uploadToken: String,
        captureKind: String = "screenshot",
        filename: String = "shortcut-screenshot.jpg"
    ) async throws -> ShortcutUploadResult {
        let responseData = try await uploadImageResponse(
            data: data,
            uploadToken: uploadToken,
            sourceApp: "ios_app_intent",
            captureKind: captureKind,
            filename: filename,
            mimeType: "image/jpeg",
            responseMode: "json"
        )

        if let payload = try? decoder.decode(ShortcutUploadPayload.self, from: responseData) {
            return ShortcutUploadResult(payload: payload)
        }

        let text = String(data: responseData, encoding: .utf8) ?? ""
        return ShortcutUploadResult(displayText: text.isEmpty ? "截图已上传，打开芥子查看结果。" : text)
    }

    func uploadNativeImage(
        data: Data,
        uploadToken: String,
        captureKind: String = "photo_library",
        filename: String = "native-upload.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> String {
        let result = try await uploadNativeImageResult(
            data: data,
            uploadToken: uploadToken,
            captureKind: captureKind,
            filename: filename,
            mimeType: mimeType
        )
        return result.notificationText
    }

    func uploadNativeImageResult(
        data: Data,
        uploadToken: String,
        captureKind: String = "photo_library",
        filename: String = "native-upload.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> ShortcutUploadResult {
        let responseData = try await uploadImageResponse(
            data: data,
            uploadToken: uploadToken,
            sourceApp: "ios_native",
            captureKind: captureKind,
            filename: filename,
            mimeType: mimeType,
            responseMode: "json"
        )

        guard let payload = try? decoder.decode(ShortcutUploadPayload.self, from: responseData) else {
            let text = String(data: responseData, encoding: .utf8) ?? ""
            return ShortcutUploadResult(
                displayText: text.isEmpty ? "截图已上传，打开芥子查看结果。" : text
            )
        }
        return ShortcutUploadResult(payload: payload)
    }

    func recognizeNativeImage(
        data: Data,
        uploadToken: String? = nil,
        captureKind: String = "photo_library",
        filename: String = "native-recognition.jpg",
        mimeType: String = "image/jpeg"
    ) async throws -> Data {
        try await uploadImageResponse(
            data: data,
            uploadToken: uploadToken,
            sourceApp: "ios_native_local_first",
            captureKind: captureKind,
            filename: filename,
            mimeType: mimeType,
            responseMode: "json",
            operation: "recognize_only"
        )
    }

    /// Ask the hosted text provider to compose a Companion for one local fact.
    /// The endpoint is read-only and must not be used for business writes.
    func generateLocalExpression(
        currentFact: [String: Any],
        plannerCandidate: [String: Any]?,
        recentFacts: [[String: Any]],
        localMemoryContext: [String: Any]?,
        expressionPreferences: [String: Any],
        clientLocalTime: String?,
        clientCapturedAt: String?,
        weekday: String?,
        recentCompanionLines: [String],
        accessToken: String
    ) async throws -> Data {
        let functionsURL = functionsURLOverride ?? AppConfig.supabaseFunctionsURL
        let anonKey = anonKeyOverride ?? AppConfig.supabaseAnonKey
        guard !functionsURL.isEmpty, !anonKey.isEmpty else {
            throw SnapCountUploadServiceError.missingConfig
        }
        guard let baseURL = URL(string: functionsURL) else {
            throw SnapCountUploadServiceError.invalidURL
        }
        let endpointPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url = endpointPath.hasSuffix("functions/v1")
            ? baseURL.appendingPathComponent("ingest-receipt")
            : baseURL.appendingPathComponent("functions/v1/ingest-receipt")
        var body: [String: Any] = [
            "action": "generate_local_expression",
            "current_fact": currentFact,
            "expression_preferences": expressionPreferences,
            "recent_companion_lines": Array(recentCompanionLines.prefix(5)),
        ]
        if let plannerCandidate { body["planner_candidate"] = plannerCandidate }
        if !recentFacts.isEmpty { body["recent_facts"] = Array(recentFacts.prefix(12)) }
        if let localMemoryContext { body["local_memory_context"] = localMemoryContext }
        if let clientLocalTime { body["client_local_time"] = clientLocalTime }
        if let clientCapturedAt { body["client_captured_at"] = clientCapturedAt }
        if let weekday { body["weekday"] = weekday }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SnapCountUploadServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SnapCountUploadServiceError.requestFailed(
                displayErrorMessage(from: responseData, fallback: String(data: responseData, encoding: .utf8) ?? "", statusCode: http.statusCode)
            )
        }
        return responseData
    }

    private func uploadImage(
        data: Data,
        uploadToken: String,
        sourceApp: String,
        captureKind: String,
        filename: String,
        mimeType: String
    ) async throws -> String {
        let responseData = try await uploadImageResponse(
            data: data,
            uploadToken: uploadToken,
            sourceApp: sourceApp,
            captureKind: captureKind,
            filename: filename,
            mimeType: mimeType,
            responseMode: "text"
        )
        let text = String(data: responseData, encoding: .utf8) ?? ""
        return text.isEmpty ? "截图已上传，打开芥子查看结果。" : text
    }

    private func uploadImageResponse(
        data: Data,
        uploadToken: String?,
        sourceApp: String,
        captureKind: String,
        filename: String,
        mimeType: String,
        responseMode: String,
        operation: String? = nil
    ) async throws -> Data {
        let functionsURL = functionsURLOverride ?? AppConfig.supabaseFunctionsURL
        let anonKey = anonKeyOverride ?? AppConfig.supabaseAnonKey
        guard !functionsURL.isEmpty, !anonKey.isEmpty else {
            throw SnapCountUploadServiceError.missingConfig
        }
        guard let baseURL = URL(string: functionsURL) else {
            throw SnapCountUploadServiceError.invalidURL
        }

        // `SupabaseFunctionsURL` is configured as the functions base URL in the
        // app project (`.../functions/v1`).  CI may instead provide the project
        // root URL, so normalize both forms without ever duplicating the path.
        let endpointPath = baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url: URL
        if endpointPath.hasSuffix("functions/v1") {
            url = baseURL.appendingPathComponent("ingest-receipt")
        } else {
            url = baseURL.appendingPathComponent("functions/v1/ingest-receipt")
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var multipart = MultipartFormData(boundary: boundary)
        if let uploadToken, !uploadToken.isEmpty {
            multipart.appendField(name: "upload_token", value: uploadToken)
        }
        if let operation {
            multipart.appendField(name: "operation", value: operation)
        }
        multipart.appendField(name: "source_app", value: sourceApp)
        multipart.appendField(name: "capture_kind", value: captureKind)
        multipart.appendField(name: "response_mode", value: responseMode)
        multipart.appendField(name: "client_captured_at", value: ISO8601DateFormatter().string(from: Date()))
        multipart.appendFile(
            name: "image",
            filename: filename,
            mimeType: mimeType,
            data: data
        )

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipart.body

        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SnapCountUploadServiceError.invalidResponse
        }

        let text = String(data: responseData, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else {
            throw SnapCountUploadServiceError.requestFailed(
                displayErrorMessage(from: responseData, fallback: text, statusCode: http.statusCode)
            )
        }
        return responseData
    }

    private func displayErrorMessage(from data: Data, fallback: String, statusCode: Int) -> String {
        if statusCode == 401 {
            return "登录凭据未同步或已失效，请打开芥子重新登录后再运行快捷指令。"
        }
        if let payload = try? decoder.decode(UploadErrorPayload.self, from: data) {
            if payload.code == "WORKER_RESOURCE_LIMIT" {
                return "AI 识别资源不足。请重试一次，或换一张更清晰、范围更小的截图。"
            }
            if let message = payload.message, !message.isEmpty {
                return message
            }
            if let error = payload.error, !error.isEmpty {
                return error
            }
        }
        return fallback.isEmpty ? "上传失败：HTTP \(statusCode)" : fallback
    }
}

struct ShortcutUploadResult {
    let displayText: String
    let notificationText: String
    let route: String

    init(displayText: String, notificationText: String? = nil, route: String = "today") {
        self.displayText = displayText
        self.notificationText = notificationText ?? displayText
        self.route = route
    }

    init(payload: ShortcutUploadPayload) {
        let baseText = payload.notificationText
            ?? payload.notification
            ?? payload.message
            ?? payload.error
            ?? "截图已上传，打开芥子查看结果。"
        let mergedText = ShortcutUploadResult.notificationText(
            baseText: baseText,
            payload: payload
        )
        // Compose the block once: the notification body and the in-app result
        // must show the same companion + fixed facts, not a re-merged copy.
        displayText = mergedText
        notificationText = mergedText
        route = payload.routePath
    }

    /// Archived Shortcut outcome. Compose the companion + fixed receipt facts
    /// once and reuse it for both the result card and the system notification.
    static func archived(
        notificationText: String,
        companionMessage: String?,
        feedback: NativeAIFeedback?
    ) -> ShortcutUploadResult {
        let mergedText = expandedDisplayText(
            baseText: notificationText,
            companionMessage: companionMessage,
            feedback: feedback
        )
        return ShortcutUploadResult(
            displayText: mergedText,
            notificationText: mergedText,
            route: "records"
        )
    }

    var notificationTitle: String {
        switch route {
        case "inbox":
            return "芥子需要你确认"
        case "records":
            return "芥子已记录"
        default:
            return "芥子已收到"
        }
    }

    var notificationBody: String {
        LocalIntakeNotificationText.boundedNotificationText(notificationText)
    }

    var compactDisplayText: String {
        "已发送到芥子。推荐点击通知回到 App 查看。"
    }

    static func expandedDisplayText(
        baseText: String,
        companionMessage: String?,
        feedback: NativeAIFeedback?
    ) -> String {
        LocalIntakeNotificationText.merge(
            baseText: baseText,
            companionMessage: companionMessage,
            feedbackParts: feedback.map { LocalIntakeNotificationFeedback($0) }
        )
    }

    static func expandedDisplayText(
        baseText: String,
        companionMessage: String?,
        feedback: ShortcutAIFeedback?
    ) -> String {
        LocalIntakeNotificationText.merge(
            baseText: baseText,
            companionMessage: companionMessage,
            feedbackParts: feedback.map { LocalIntakeNotificationFeedback($0) }
        )
    }

    private static func notificationText(baseText: String, payload: ShortcutUploadPayload) -> String {
        LocalIntakeNotificationText.merge(
            baseText: baseText,
            companionMessage: payload.companionMessage,
            feedbackParts: payload.aiFeedback.map { LocalIntakeNotificationFeedback($0) }
        )
    }
}

struct ShortcutUploadPayload: Decodable {
    let id: String?
    let status: String?
    let recordType: String?
    let notificationText: String?
    let notification: String?
    let message: String?
    let error: String?
    let companionMessage: String?
    let aiFeedback: ShortcutAIFeedback?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case recordType = "record_type"
        case notificationText = "notification_text"
        case notification
        case message
        case error
        case companionMessage = "companion_message"
        case aiFeedback = "ai_feedback"
    }

    var route: String {
        switch status {
        case "staging", "pending", "retry_failed":
            return "inbox"
        default:
            switch recordType {
            case "expense", "income", "sport", "sleep", "reading", "food", "wallet":
                return "records"
            default:
                return "today"
            }
        }
    }

    var routePath: String {
        guard let id, !id.isEmpty else { return route }
        guard route == "records" else { return "\(route)/\(id)" }
        let kind = recordType ?? "data"
        return "\(route)/\(kind)/\(id)"
    }
}

struct ShortcutAIFeedback: Decodable {
    let icon: String?
    let badge: String?
    let confidence: Double?
    let emotionLine: String?
    let utilityLine: String?
    let detailReason: String?

    enum CodingKeys: String, CodingKey {
        case icon
        case badge
        case confidence
        case emotionLine = "emotion_line"
        case utilityLine = "utility_line"
        case detailReason = "detail_reason"
    }
}

private struct UploadErrorPayload: Decodable {
    let code: String?
    let message: String?
    let error: String?
}

private struct MultipartFormData {
    let boundary: String
    private(set) var body = Data()

    mutating func appendField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
        append("--\(boundary)--\r\n")
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}
