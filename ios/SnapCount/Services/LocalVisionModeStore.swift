import Foundation

enum LocalVisionMode: String, CaseIterable, Identifiable {
    case disabled
    case hosted
    case byok

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disabled: "关闭识别"
        case .hosted: "Hosted AI"
        case .byok: "自带 Key · Qwen 3.6 Flash"
        }
    }
}

struct LocalVisionModeStore {
    private let defaults: UserDefaults
    private let key = "local_vision_mode"
    private let hostedConsentKey = "hosted_ai_consent_version"
    private static let hostedConsentVersion = 1

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: LocalVisionMode {
        let persisted = LocalVisionMode(rawValue: defaults.string(forKey: key) ?? "") ?? .disabled
        if persisted == .hosted, defaults.integer(forKey: hostedConsentKey) != Self.hostedConsentVersion {
            return .disabled
        }
        guard persisted != .byok || JieziReleaseCapabilities.byok else {
            defaults.set(LocalVisionMode.disabled.rawValue, forKey: key)
            return .disabled
        }
        return persisted
    }

    func save(_ mode: LocalVisionMode) {
        let safeMode = mode == .byok && !JieziReleaseCapabilities.byok ? .disabled : mode
        if safeMode == .hosted {
            defaults.set(Self.hostedConsentVersion, forKey: hostedConsentKey)
        } else {
            defaults.removeObject(forKey: hostedConsentKey)
        }
        defaults.set(safeMode.rawValue, forKey: key)
    }
}
