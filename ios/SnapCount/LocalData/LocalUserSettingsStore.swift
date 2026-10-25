import Foundation

/// Device preferences only. Account entitlement and privacy consent are separate authorities.
final class LocalUserSettingsStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "jiezi.local.user-preferences.v1") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> NativeUserSettings {
        var settings = NativeUserSettings()
        let values = defaults.dictionary(forKey: key) ?? [:]
        settings.screenshotVisionPrimary = values["screenshotVisionPrimary"] as? String ?? settings.screenshotVisionPrimary
        settings.photoVisionPrimary = values["photoVisionPrimary"] as? String ?? settings.photoVisionPrimary
        settings.qwenScreenshotModel = values["qwenScreenshotModel"] as? String ?? settings.qwenScreenshotModel
        settings.qwenPhotoModel = values["qwenPhotoModel"] as? String ?? settings.qwenPhotoModel
        settings.qwenScreenshotThinking = values["qwenScreenshotThinking"] as? Bool ?? settings.qwenScreenshotThinking
        settings.qwenPhotoThinking = values["qwenPhotoThinking"] as? Bool ?? settings.qwenPhotoThinking
        settings.aiInsightProvider = values["aiInsightProvider"] as? String ?? settings.aiInsightProvider
        settings.companionEnabled = values["companionEnabled"] as? Bool ?? settings.companionEnabled
        settings.companionPersona = values["companionPersona"] as? String ?? settings.companionPersona
        settings.companionMemoryStrength = values["companionMemoryStrength"] as? String ?? settings.companionMemoryStrength
        settings.companionExpressionStyle = values["companionExpressionStyle"] as? String ?? settings.companionExpressionStyle
        settings.companionCustomNote = values["companionCustomNote"] as? String ?? settings.companionCustomNote
        if let consent = defaults.dictionary(forKey: key + ".explicit-consent") {
            settings.companionMemoryEnabled = consent["companion_memory_enabled"] as? Bool ?? settings.companionMemoryEnabled
            settings.aiLogsEnabled = consent["ai_logs_enabled"] as? Bool ?? settings.aiLogsEnabled
            settings.promptOptimizationEnabled = consent["prompt_optimization_enabled"] as? Bool ?? settings.promptOptimizationEnabled
            settings.expressionImprovementEnabled = consent["expression_improvement_enabled"] as? Bool ?? settings.expressionImprovementEnabled
            settings.keepSourceImages = consent["keep_source_images"] as? Bool ?? settings.keepSourceImages
            settings.imageRetentionDays = consent["image_retention_days"] as? Int ?? settings.imageRetentionDays
        }
        return settings
    }

    func save(_ settings: NativeUserSettings) {
        defaults.set([
            "screenshotVisionPrimary": settings.screenshotVisionPrimary,
            "photoVisionPrimary": settings.photoVisionPrimary,
            "qwenScreenshotModel": settings.qwenScreenshotModel,
            "qwenPhotoModel": settings.qwenPhotoModel,
            "qwenScreenshotThinking": settings.qwenScreenshotThinking,
            "qwenPhotoThinking": settings.qwenPhotoThinking,
            "aiInsightProvider": settings.aiInsightProvider,
            "companionEnabled": settings.companionEnabled,
            "companionPersona": settings.companionPersona,
            "companionMemoryStrength": settings.companionMemoryStrength,
            "companionExpressionStyle": settings.companionExpressionStyle,
            "companionCustomNote": settings.companionCustomNote
        ] as [String: Any], forKey: key)
    }

    /// Call only for a user's explicit settings action, never while applying cloud settings.
    func saveExplicitConsent(_ settings: NativeUserSettings, keys: Set<String>) {
        let available: [String: Any] = [
            "companion_memory_enabled": settings.companionMemoryEnabled,
            "ai_logs_enabled": settings.aiLogsEnabled,
            "prompt_optimization_enabled": settings.promptOptimizationEnabled,
            "expression_improvement_enabled": settings.expressionImprovementEnabled,
            "keep_source_images": settings.keepSourceImages,
            "image_retention_days": settings.imageRetentionDays
        ]
        var consent = defaults.dictionary(forKey: key + ".explicit-consent") ?? [:]
        for field in keys {
            if let value = available[field] { consent[field] = value }
        }
        defaults.set(consent, forKey: key + ".explicit-consent")
    }
}
