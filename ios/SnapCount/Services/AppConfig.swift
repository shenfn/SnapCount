import Foundation

enum AppConfig {
    static var supabaseURL: String {
        if !GeneratedAppConfig.supabaseURL.isEmpty {
            return GeneratedAppConfig.supabaseURL
        }
        value(for: "SupabaseURL")
    }

    static var supabaseAnonKey: String {
        if !GeneratedAppConfig.supabaseAnonKey.isEmpty {
            return GeneratedAppConfig.supabaseAnonKey
        }
        value(for: "SupabaseAnonKey")
    }

    private static func value(for key: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }
        return raw.hasPrefix("$(") ? "" : raw
    }
}
