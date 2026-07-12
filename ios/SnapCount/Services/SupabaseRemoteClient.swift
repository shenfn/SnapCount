import Foundation

enum SupabaseRemoteError: LocalizedError {
    case missingConfig
    case invalidURL
    case missingSession
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "缺少 iOS Supabase 配置。"
        case .invalidURL:
            return "数据接口地址无效。"
        case .missingSession:
            return "登录状态已失效，请重新登录。"
        case .requestFailed(let message):
            return message
        }
    }
}

typealias NativeDataServiceError = SupabaseRemoteError

protocol SupabaseRemoteClientProtocol {
    func get<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws -> T

    func patch(
        path: String,
        queryItems: [URLQueryItem],
        body: [String: AnyCodable],
        accessToken: String
    ) async throws

    func delete(
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws

    func post<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem],
        body: [String: AnyCodable],
        accessToken: String
    ) async throws -> T

    func rpc<T: Decodable>(
        _ type: T.Type,
        name: String,
        body: [String: AnyCodable],
        accessToken: String
    ) async throws -> T

    func postMultipart(
        path: String,
        fields: [String: String],
        accessToken: String
    ) async throws -> Data
}

final class SupabaseRemoteClient: SupabaseRemoteClientProtocol {
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.session = session
        self.decoder = decoder
        self.encoder = encoder
    }

    func get<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws -> T {
        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        authorize(&request, accessToken: accessToken)
        return try decoder.decode(type, from: try await dataResponse(for: request))
    }

    func patch(
        path: String,
        queryItems: [URLQueryItem],
        body: [String: AnyCodable],
        accessToken: String
    ) async throws {
        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = "PATCH"
        authorize(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        _ = try await dataResponse(for: request)
    }

    func delete(
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws {
        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = "DELETE"
        authorize(&request, accessToken: accessToken)
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        _ = try await dataResponse(for: request)
    }

    func post<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: AnyCodable],
        accessToken: String
    ) async throws -> T {
        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = "POST"
        authorize(&request, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try encoder.encode(body)
        return try decoder.decode(type, from: try await dataResponse(for: request))
    }

    func rpc<T: Decodable>(
        _ type: T.Type,
        name: String,
        body: [String: AnyCodable],
        accessToken: String
    ) async throws -> T {
        try await post(
            type,
            path: "rest/v1/rpc/\(name)",
            body: body,
            accessToken: accessToken
        )
    }

    func postMultipart(
        path: String,
        fields: [String: String],
        accessToken: String
    ) async throws -> Data {
        guard let baseURL = URL(
            string: AppConfig.supabaseFunctionsURL.isEmpty
                ? AppConfig.supabaseURL
                : AppConfig.supabaseFunctionsURL
        ) else {
            throw SupabaseRemoteError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        authorize(&request, accessToken: accessToken)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await dataResponse(for: request)
    }

    private func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard !AppConfig.supabaseURL.isEmpty, !AppConfig.supabaseAnonKey.isEmpty else {
            throw SupabaseRemoteError.missingConfig
        }
        guard let baseURL = URL(string: AppConfig.supabaseURL) else {
            throw SupabaseRemoteError.invalidURL
        }
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw SupabaseRemoteError.invalidURL
        }
        return url
    }

    private func authorize(_ request: inout URLRequest, accessToken: String) {
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }

    private func dataResponse(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let payload = try? decoder.decode(SupabaseErrorPayload.self, from: data) {
                throw SupabaseRemoteError.requestFailed(payload.displayMessage)
            }
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw SupabaseRemoteError.requestFailed(text)
        }
        return data
    }
}
