import Foundation

enum SupabaseAuthServiceError: LocalizedError {
    case missingConfig
    case invalidURL
    case requestFailed(String)
    case emptyUploadToken

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "缺少 iOS Supabase 配置，请先配置 IOS_SUPABASE_URL 和 IOS_SUPABASE_ANON_KEY。"
        case .invalidURL:
            return "Supabase URL 无效"
        case .requestFailed(let message):
            return message
        case .emptyUploadToken:
            return "登录成功，但没有读取到 upload_token。"
        }
    }
}

final class SupabaseAuthService {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(email: String, password: String) async throws -> SupabaseAuthSession {
        let baseURL = try requireBaseURL()
        let url = baseURL.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        guard let requestURL = components?.url else { throw SupabaseAuthServiceError.invalidURL }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["email": email, "password": password])

        return try await decoded(SupabaseAuthSession.self, from: request)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseAuthSession {
        let baseURL = try requireBaseURL()
        let url = baseURL.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let requestURL = components?.url else { throw SupabaseAuthServiceError.invalidURL }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["refresh_token": refreshToken])

        return try await decoded(SupabaseAuthSession.self, from: request)
    }

    func fetchUploadToken(userId: String, accessToken: String) async throws -> String {
        let baseURL = try requireBaseURL()
        let url = baseURL.appendingPathComponent("rest/v1/user_configs")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "upload_token"),
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let requestURL = components?.url else { throw SupabaseAuthServiceError.invalidURL }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let rows = try await decoded([UserConfigRow].self, from: request)
        guard let token = rows.first?.uploadToken, !token.isEmpty else {
            throw SupabaseAuthServiceError.emptyUploadToken
        }
        return token
    }

    private func requireBaseURL() throws -> URL {
        guard !AppConfig.supabaseURL.isEmpty, !AppConfig.supabaseAnonKey.isEmpty else {
            throw SupabaseAuthServiceError.missingConfig
        }
        guard let url = URL(string: AppConfig.supabaseURL) else {
            throw SupabaseAuthServiceError.invalidURL
        }
        return url
    }

    private func decoded<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let payload = try? decoder.decode(SupabaseErrorPayload.self, from: data) {
                throw SupabaseAuthServiceError.requestFailed(payload.displayMessage)
            }
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw SupabaseAuthServiceError.requestFailed(text)
        }
        return try decoder.decode(T.self, from: data)
    }
}
