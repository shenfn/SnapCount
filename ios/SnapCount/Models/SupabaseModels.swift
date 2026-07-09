import Foundation

struct SupabaseAuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

struct SupabaseUser: Codable {
    let id: String
    let email: String?
}

struct UserConfigRow: Codable {
    let uploadToken: String?

    enum CodingKeys: String, CodingKey {
        case uploadToken = "upload_token"
    }
}

struct SupabaseErrorPayload: Codable {
    let error: String?
    let errorDescription: String?
    let msg: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case msg
        case message
    }

    var displayMessage: String {
        errorDescription ?? message ?? msg ?? error ?? "请求失败"
    }
}
