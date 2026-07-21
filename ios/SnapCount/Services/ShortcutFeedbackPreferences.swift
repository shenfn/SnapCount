import Foundation

enum ShortcutFeedbackPreferences {
    private static let notificationKey = "shortcut_feedback_notifications_enabled"
    private static let resultCardKey = "shortcut_feedback_result_card_enabled"
    private static let hasConfiguredKey = "shortcut_feedback_has_configured"

    static var notificationsEnabled: Bool {
        get {
            guard UserDefaults.standard.bool(forKey: hasConfiguredKey) else { return true }
            return UserDefaults.standard.bool(forKey: notificationKey)
        }
        set {
            UserDefaults.standard.set(true, forKey: hasConfiguredKey)
            UserDefaults.standard.set(newValue, forKey: notificationKey)
        }
    }

    static var resultCardEnabled: Bool {
        get {
            guard UserDefaults.standard.bool(forKey: hasConfiguredKey) else { return true }
            return UserDefaults.standard.bool(forKey: resultCardKey)
        }
        set {
            UserDefaults.standard.set(true, forKey: hasConfiguredKey)
            UserDefaults.standard.set(newValue, forKey: resultCardKey)
        }
    }

    static func applyNotificationAuthorization(granted: Bool) {
        notificationsEnabled = granted
        resultCardEnabled = !granted
    }
}
