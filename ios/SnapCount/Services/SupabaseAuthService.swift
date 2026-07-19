import Foundation
import Supabase

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

enum SupabaseSignUpResult {
    case signedIn(SupabaseAuthSession)
    case confirmationRequired(email: String)
}

final class SupabaseAuthService {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func signIn(email: String, password: String) async throws -> SupabaseAuthSession {
        let session = try await requireClient().auth.signIn(email: email, password: password)
        return mapped(session)
    }

    func signUp(
        email: String,
        password: String,
        consent: NativeRegistrationConsent
    ) async throws -> SupabaseSignUpResult {
        let response = try await requireClient().auth.signUp(
            email: email,
            password: password,
            data: [
                "legal_consent_at": .string(consent.legalAcceptedAt),
                "sensitive_data_consent_at": .string(consent.sensitiveDataAcceptedAt),
                "terms_version": .string(consent.termsVersion),
                "privacy_version": .string(consent.privacyVersion)
            ]
        )
        if let session = response.session {
            return .signedIn(mapped(session))
        }
        return .confirmationRequired(email: response.user.email ?? email)
    }

    func restoreSession(accessToken: String, refreshToken: String) async throws -> SupabaseAuthSession {
        let session = try await requireClient().auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
        return mapped(session)
    }

    func currentSession() async throws -> SupabaseAuthSession {
        mapped(try await requireClient().auth.session)
    }

    func refreshSession(refreshToken: String? = nil) async throws -> SupabaseAuthSession {
        let session = try await requireClient().auth.refreshSession(refreshToken: refreshToken)
        return mapped(session)
    }

    func signOut() async throws {
        try await requireClient().auth.signOut(scope: .local)
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

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            if let payload = try? decoder.decode(SupabaseErrorPayload.self, from: data) {
                throw SupabaseAuthServiceError.requestFailed(payload.displayMessage)
            }
            throw SupabaseAuthServiceError.requestFailed(String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)")
        }
        let rows = try decoder.decode([UserConfigRow].self, from: data)
        guard let token = rows.first?.uploadToken, !token.isEmpty else {
            throw SupabaseAuthServiceError.emptyUploadToken
        }
        return token
    }

    private func requireClient() throws -> SupabaseClient {
        guard let client = SupabaseClientProvider.client else {
            throw SupabaseAuthServiceError.missingConfig
        }
        return client
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

    private func mapped(_ session: Session) -> SupabaseAuthSession {
        SupabaseAuthSession(
            accessToken: session.accessToken,
            refreshToken: session.refreshToken,
            expiresIn: Int(session.expiresIn),
            expiresAt: Int(session.expiresAt),
            tokenType: session.tokenType,
            user: SupabaseUser(id: session.user.id.uuidString.lowercased(), email: session.user.email)
        )
    }
}
