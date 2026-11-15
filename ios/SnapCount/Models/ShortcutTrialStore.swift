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
    private let key = "jiezi.onboarding.shortcut-trial.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func synchronize(scope: OnboardingProgressScope) {
        if let receipt = read(), receipt.scope != scopeKey(scope) { defaults.removeObject(forKey: key) }
    }

    func begin(scope: OnboardingProgressScope, now: Date = Date()) -> UUID {
        let receipt = ShortcutTrialReceipt(id: UUID(), scope: scopeKey(scope), startedAt: now)
        save(receipt)
        return receipt.id
    }

    func claim(now: Date = Date()) -> UUID? {
        guard var receipt = active(now: now), !receipt.processing, receipt.outcome == nil else { return nil }
        receipt.processing = true
        save(receipt)
        return receipt.id
    }

    func complete(id: UUID, outcome: ShortcutTrialOutcome, now: Date = Date()) {
        guard var receipt = active(now: now), receipt.id == id, receipt.processing, receipt.outcome == nil else { return }
        receipt.outcome = outcome
        save(receipt)
    }

    func snapshot(for scope: OnboardingProgressScope, now: Date = Date()) -> ShortcutTrialReceipt? {
        guard let receipt = active(now: now), receipt.scope == scopeKey(scope) else { return nil }
        return receipt
    }

    func cancel(id: UUID) {
        guard read()?.id == id else { return }
        defaults.removeObject(forKey: key)
    }

    private func active(now: Date) -> ShortcutTrialReceipt? {
        guard let receipt = read() else { return nil }
        let age = now.timeIntervalSince(receipt.startedAt)
        guard age >= 0, age <= 30 * 60 else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return receipt
    }

    private func read() -> ShortcutTrialReceipt? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ShortcutTrialReceipt.self, from: data)
    }

    private func save(_ receipt: ShortcutTrialReceipt) {
        // ponytail: 当前 Intent 与 App 同一 target、主执行器串行；若拆成扩展需改 App Group 与跨进程互斥。
        guard let data = try? JSONEncoder().encode(receipt) else { return }
        defaults.set(data, forKey: key)
    }

    private func scopeKey(_ scope: OnboardingProgressScope) -> String {
        switch scope {
        case .device: return "device"
        case .account(let id): return "account:\(id)"
        }
    }
}
