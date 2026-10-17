import Foundation

enum ShortcutTrialOutcome: String, Codable, Sendable {
    case archived, staged, remoteReturned, failed
}

struct ShortcutTrialReceipt: Codable, Equatable, Sendable {
    let id: UUID
    let scope: String
    let startedAt: Date
    var processing = false
    var outcome: ShortcutTrialOutcome?
}

@MainActor
struct ShortcutTrialStore {
    static let shared = ShortcutTrialStore()
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func synchronize(scope: OnboardingProgressScope) {}
    func begin(scope: OnboardingProgressScope, now: Date = Date()) -> UUID { UUID() }
    func claim(now: Date = Date()) -> UUID? { nil }
    func complete(id: UUID, outcome: ShortcutTrialOutcome, now: Date = Date()) {}
    func snapshot(for scope: OnboardingProgressScope, now: Date = Date()) -> ShortcutTrialReceipt? { nil }
    func cancel(id: UUID) {}
}
