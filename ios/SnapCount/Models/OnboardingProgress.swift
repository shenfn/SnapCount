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

enum OnboardingProgressScope: Hashable {
    case device
    case account(String)
}

struct OnboardingProgressStore {
    static let currentVersion = 1

    private let defaults: UserDefaults

    func completion(
        for scope: OnboardingProgressScope,
        version: Int = OnboardingProgressStore.currentVersion
    ) -> NativeOnboardingCompletion? {
        switch scope {
        case .device:
            guard let rawValue = defaults.string(forKey: deviceKey(version: version)) else { return nil }
            return NativeOnboardingCompletion(rawValue: rawValue)
        case .account(let userId):
            return completion(for: userId, version: version)
        }
    }

    func shouldPresent(
        for scope: OnboardingProgressScope,
        version: Int = OnboardingProgressStore.currentVersion
    ) -> Bool {
        completion(for: scope, version: version) == nil
    }

    func mark(
        _ completion: NativeOnboardingCompletion,
        for scope: OnboardingProgressScope,
        version: Int = OnboardingProgressStore.currentVersion
    ) {
        switch scope {
        case .device:
            defaults.set(completion.rawValue, forKey: deviceKey(version: version))
        case .account(let userId):
            mark(completion, for: userId, version: version)
        }
    }

    func linkedAccountIDForDeviceProgress() -> String? {
        defaults.string(forKey: deviceAccountLinkKey)
    }

    func linkDeviceProgress(toAccount userId: String) {
        guard !userId.isEmpty, linkedAccountIDForDeviceProgress() == nil else { return }
        defaults.set(userId, forKey: deviceAccountLinkKey)
    }

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

    private func deviceKey(version: Int) -> String {
        "jiezi.onboarding.v\(version).device.completion"
    }

    private var deviceAccountLinkKey: String {
        "jiezi.onboarding.v\(Self.currentVersion).device.account"
    }
}
