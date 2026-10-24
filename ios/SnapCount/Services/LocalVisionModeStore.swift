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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var mode: LocalVisionMode {
        LocalVisionMode(rawValue: defaults.string(forKey: key) ?? "") ?? .disabled
    }

    func save(_ mode: LocalVisionMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}
