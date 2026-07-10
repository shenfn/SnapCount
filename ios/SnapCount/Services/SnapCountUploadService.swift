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

    init(session: URLSession = .shared) {
        self.session = session
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
        try await uploadImage(
            data: data,
            uploadToken: uploadToken,
            sourceApp: "ios_native",
            captureKind: captureKind,
            filename: filename,
            mimeType: mimeType
        )
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
        uploadToken: String,
        sourceApp: String,
        captureKind: String,
        filename: String,
        mimeType: String,
        responseMode: String
    ) async throws -> Data {
        guard !AppConfig.supabaseFunctionsURL.isEmpty, !AppConfig.supabaseAnonKey.isEmpty else {
            throw SnapCountUploadServiceError.missingConfig
        }
        guard let baseURL = URL(string: AppConfig.supabaseFunctionsURL) else {
            throw SnapCountUploadServiceError.invalidURL
        }

        let url = baseURL.appendingPathComponent("functions/v1/ingest-receipt")
        let boundary = "Boundary-\(UUID().uuidString)"
        var multipart = MultipartFormData(boundary: boundary)
        multipart.appendField(name: "upload_token", value: uploadToken)
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
        request.httpMethod = "POST"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
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
        let text = payload.notificationText
            ?? payload.notification
            ?? payload.message
            ?? payload.error
            ?? "截图已上传，打开芥子查看结果。"
        notificationText = text
        displayText = ShortcutUploadResult.shortcutDisplayText(
            notificationText: text,
            payload: payload
        )
        route = payload.routePath
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
        let compact = notificationText
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
        return compact.count > 160 ? "\(compact.prefix(157))..." : compact
    }

    var compactDisplayText: String {
        "已发送到芥子。推荐点击通知回到 App 查看。"
    }

    private static func shortcutDisplayText(notificationText: String, payload: ShortcutUploadPayload) -> String {
        var lines: [String] = [notificationText]

        if let companion = payload.companionMessage,
           !companion.isEmpty,
           !notificationText.contains(companion) {
            lines.append(companion)
        }

        if let utility = payload.aiFeedback?.utilityLine,
           !utility.isEmpty,
           !lines.contains(where: { $0.contains(utility) }) {
            lines.append("观察：\(utility)")
        }

        if let reason = payload.aiFeedback?.detailReason,
           !reason.isEmpty,
           !lines.contains(where: { $0.contains(reason) }) {
            lines.append("依据：\(reason)")
        }

        switch payload.route {
        case "inbox":
            lines.append("状态：需要打开芥子收件箱确认")
        case "records":
            lines.append("状态：已归档到芥子记录")
        default:
            lines.append("状态：已发送到芥子")
        }

        lines.append("提示：点通知可回到芥子；这张卡片只负责确认。")
        return lines.joined(separator: "\n")
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
    let badge: String?
    let emotionLine: String?
    let utilityLine: String?
    let detailReason: String?

    enum CodingKeys: String, CodingKey {
        case badge
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
