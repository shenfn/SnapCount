import Foundation

struct LocalExpenseCommand: Equatable {
    let id: UUID
    let accountID: UUID
    let amountText: String
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let createdAt: Date
}

struct LocalExpenseUpdateCommand: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let accountID: UUID
    let amountText: String
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let updatedAt: Date
}

struct LocalExpenseDeleteCommand: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let deletedAt: Date
}

struct LocalExpenseOutcome: Equatable {
    let expense: LocalExpense?
    let tombstone: LocalExpenseTombstone?
    let profileID: UUID
}

struct LocalExpenseMonth: Equatable {
    let profileID: UUID
    let expenses: [LocalExpense]
}

protocol LocalExpenseUseCaseProtocol {
    func prepareProfile() async throws -> LocalProfile
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome
    func month(_ monthKey: String) async throws -> LocalExpenseMonth
}

final class LocalExpenseUseCase: LocalExpenseUseCaseProtocol {
    private let profileStore: LocalProfileStoreProtocol
    private let repository: LocalExpenseRepositoryProtocol
    private let operationIDProvider: () -> UUID

    init(
        profileStore: LocalProfileStoreProtocol,
        repository: LocalExpenseRepositoryProtocol,
        operationIDProvider: @escaping () -> UUID = UUID.init
    ) {
        self.profileStore = profileStore
        self.repository = repository
        self.operationIDProvider = operationIDProvider
    }

    func prepareProfile() async throws -> LocalProfile {
        try profileStore.activeProfile()
    }

    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome {
        let profile = try profileStore.activeProfile()
        let draft = try LocalExpenseMapper.createDraft(command, profileID: profile.id)
        let expense = try repository.createExpense(draft, operationID: operationIDProvider())
        return LocalExpenseOutcome(expense: expense, tombstone: nil, profileID: profile.id)
    }

    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome {
        let profile = try profileStore.activeProfile()
        let update = try LocalExpenseMapper.update(command)
        let expense = try repository.updateExpense(update, operationID: operationIDProvider())
        guard expense.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return LocalExpenseOutcome(expense: expense, tombstone: nil, profileID: profile.id)
    }

    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome {
        let profile = try profileStore.activeProfile()
        let tombstone = try repository.deleteExpense(
            id: command.id,
            expectedVersion: command.expectedVersion,
            deletedAt: command.deletedAt,
            operationID: operationIDProvider()
        )
        guard tombstone.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return LocalExpenseOutcome(expense: nil, tombstone: tombstone, profileID: profile.id)
    }

    func month(_ monthKey: String) async throws -> LocalExpenseMonth {
        let profile = try profileStore.activeProfile()
        return LocalExpenseMonth(
            profileID: profile.id,
            expenses: try repository.expenses(profileID: profile.id, monthKey: monthKey)
        )
    }
}
