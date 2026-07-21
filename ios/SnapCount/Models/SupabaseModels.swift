import Foundation

struct SupabaseAuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let tokenType: String?
    let user: SupabaseUser

    var expirationEpoch: Int? {
        if let expiresAt { return expiresAt }
        let parts = accessToken.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? NSNumber else { return nil }
        return exp.intValue
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
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
