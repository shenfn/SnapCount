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

struct LocalExpenseWorkspace: Equatable {
    let profile: LocalProfile
    let accounts: [LocalAccount]
    let defaultAccountID: UUID?
}

struct LocalAccountSetupCommand: Equatable {
    let id: UUID
    let name: String
    let kind: String
    let openingBalanceText: String
    let createdAt: Date
}

protocol LocalExpenseUseCaseProtocol {
    func prepareProfile() async throws -> LocalProfile
    func prepareWorkspace() async throws -> LocalExpenseWorkspace
    func accounts() async throws -> [LocalAccount]
    func accountBalanceMinor(_ accountID: UUID) async throws -> Int64
    func expense(id: UUID) async throws -> LocalExpense?
    func createAccount(_ command: LocalAccountSetupCommand) async throws -> LocalAccount
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome
    func month(_ monthKey: String) async throws -> LocalExpenseMonth
}

extension LocalExpenseUseCaseProtocol {
    func prepareWorkspace() async throws -> LocalExpenseWorkspace {
        LocalExpenseWorkspace(profile: try await prepareProfile(), accounts: [], defaultAccountID: nil)
    }

    func accounts() async throws -> [LocalAccount] { try await prepareWorkspace().accounts }

    func accountBalanceMinor(_ accountID: UUID) async throws -> Int64 {
        throw LocalDataError.invalidRecord
    }

    func expense(id: UUID) async throws -> LocalExpense? { nil }

    func createAccount(_ command: LocalAccountSetupCommand) async throws -> LocalAccount {
        throw LocalDataError.invalidRecord
    }
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

    func prepareWorkspace() async throws -> LocalExpenseWorkspace {
        let profile = try profileStore.activeProfile()
        return LocalExpenseWorkspace(
            profile: profile,
            accounts: try repository.accounts(profileID: profile.id),
            defaultAccountID: nil
        )
    }

    func accounts() async throws -> [LocalAccount] {
        try await prepareWorkspace().accounts
    }

    func accountBalanceMinor(_ accountID: UUID) async throws -> Int64 {
        let profile = try profileStore.activeProfile()
        guard try repository.accounts(profileID: profile.id).contains(where: { $0.id == accountID }) else {
            throw LocalDataError.invalidIdentifier
        }
        return try repository.accountBalanceMinor(accountID: accountID)
    }

    func expense(id: UUID) async throws -> LocalExpense? {
        let profile = try profileStore.activeProfile()
        guard let expense = try repository.expense(id: id) else { return nil }
        guard expense.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return expense
    }

    func createAccount(_ command: LocalAccountSetupCommand) async throws -> LocalAccount {
        let profile = try profileStore.activeProfile()
        let draft = LocalAccountDraft(
            id: command.id,
            profileID: profile.id,
            name: command.name.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: command.kind,
            currency: "CNY",
            openingBalanceMinor: try LocalExpenseMapper.openingBalanceMinor(command.openingBalanceText),
            createdAt: command.createdAt
        )
        guard !draft.name.isEmpty else { throw LocalDataError.invalidRecord }
        guard LocalExpenseMapper.allowedAccountKinds.contains(draft.kind) else {
            throw LocalDataError.invalidAccountKind
        }
        return try repository.createAccount(draft)
    }

    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome {
        let profile = try profileStore.activeProfile()
        guard try repository.accounts(profileID: profile.id).contains(where: { $0.id == command.accountID }) else {
            throw LocalDataError.accountRequired
        }
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
