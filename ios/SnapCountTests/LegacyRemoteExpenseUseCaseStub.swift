import Foundation
@testable import SnapCount

/// Explicit repository-only fixture for legacy remote contract tests.
/// Production AppState uses the local fact reader and never takes this route.
final class LegacyRemoteExpenseUseCaseStub: LocalExpenseUseCaseProtocol {
    private let profile = LocalProfile(id: UUID(), createdAt: Date(), cloudUserID: nil, syncEnabled: false)
    func prepareProfile() async throws -> LocalProfile { profile }
    func month(_ monthKey: String) async throws -> LocalExpenseMonth { LocalExpenseMonth(profileID: profile.id, expenses: []) }
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
}
