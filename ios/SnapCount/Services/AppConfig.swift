import Foundation

enum AppConfig {
    static var supabaseURL: String {
        if !GeneratedAppConfig.supabaseURL.isEmpty {
            return GeneratedAppConfig.supabaseURL
        }
        return value(for: "SupabaseURL")
    }

    static var supabaseFunctionsURL: String {
        if !GeneratedAppConfig.supabaseFunctionsURL.isEmpty {
            return GeneratedAppConfig.supabaseFunctionsURL
        }
        let configured = value(for: "SupabaseFunctionsURL")
        return configured.isEmpty ? supabaseURL : configured
    }

    static var supabaseAnonKey: String {
        if !GeneratedAppConfig.supabaseAnonKey.isEmpty {
            return GeneratedAppConfig.supabaseAnonKey
        }
        return value(for: "SupabaseAnonKey")
    }

    static var shortcutTemplateURL: String {
        screenshotShortcutTemplateURL
    }

    static var photoShortcutTemplateURL: String {
        configuredURL(
            generated: GeneratedAppConfig.photoShortcutTemplateURL,
            infoKey: "PhotoShortcutTemplateURL"
        )
    }

    static var screenshotShortcutTemplateURL: String {
        configuredURL(
            generated: GeneratedAppConfig.screenshotShortcutTemplateURL,
            infoKey: "ScreenshotShortcutTemplateURL"
        )
    }

    private static func configuredURL(generated: String, infoKey: String) -> String {
        if !generated.isEmpty {
            return generated
        }
        let configured = value(for: infoKey)
        if !configured.isEmpty {
            return configured
        }
        if !GeneratedAppConfig.shortcutTemplateURL.isEmpty {
            return GeneratedAppConfig.shortcutTemplateURL
        }
        return value(for: "ShortcutTemplateURL")
    }

    private static func value(for key: String) -> String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }
        return raw.hasPrefix("$(") ? "" : raw
    }
}
