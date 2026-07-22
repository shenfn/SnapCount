import Foundation

enum NativeOnboardingCompletion: String {
    case completed
    case skipped

    var statusText: String {
        switch self {
        case .completed: return "已完成，可重新查看"
        case .skipped: return "已跳过，可随时继续"
        }
    }
}

struct OnboardingProgressStore {
    static let currentVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func completion(
        for userId: String,
        version: Int = OnboardingProgressStore.currentVersion
    ) -> NativeOnboardingCompletion? {
        guard !userId.isEmpty,
              let rawValue = defaults.string(forKey: key(userId: userId, version: version)) else {
            return nil
        }
        return NativeOnboardingCompletion(rawValue: rawValue)
    }

    func shouldPresent(
        for userId: String,
        version: Int = OnboardingProgressStore.currentVersion
    ) -> Bool {
        completion(for: userId, version: version) == nil
    }

    func mark(
        _ completion: NativeOnboardingCompletion,
        for userId: String,
        version: Int = OnboardingProgressStore.currentVersion
    ) {
        guard !userId.isEmpty else { return }
        defaults.set(completion.rawValue, forKey: key(userId: userId, version: version))
    }

    private func key(userId: String, version: Int) -> String {
        "jiezi.onboarding.v\(version).\(userId).completion"
    }
}
