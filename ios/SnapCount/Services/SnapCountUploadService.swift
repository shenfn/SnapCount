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
        multipart.appendField(name: "response_mode", value: "text")
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
        return text.isEmpty ? "截图已上传，打开芥子查看结果。" : text
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
