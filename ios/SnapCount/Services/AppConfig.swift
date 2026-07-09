import Foundation

enum AppConfig {
    static var supabaseURL: String {
        value(for: "SupabaseURL")
    }

    static var supabaseAnonKey: String {
        value(for: "SupabaseAnonKey")
    }

    private static func value(for key: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }
        return raw.hasPrefix("$(") ? "" : raw
    }
}
