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

struct LocalIncomeCommand: Equatable {
    let id: UUID
    let accountID: UUID?
    let amountText: String
    let currency: String
    let sourceName: String
    let category: String
    let incomeDate: String
    let occurredAt: Date?
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

struct LocalIncomeMonth: Equatable {
    let profileID: UUID
    let incomes: [LocalIncome]
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
    func importRemoteAccounts(_ accounts: [LocalAccount]) async throws
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome
    func createIncome(_ command: LocalIncomeCommand) async throws -> LocalIncome
    func income(id: UUID) async throws -> LocalIncome?
    func incomes(_ monthKey: String) async throws -> LocalIncomeMonth
    func updateIncome(_ update: LocalIncomeUpdate) async throws -> LocalIncome
    func deleteIncome(id: UUID, expectedVersion: Int64, deletedAt: Date) async throws -> LocalIncomeTombstone
    func importRemoteExpenses(_ expenses: [LocalExpenseDraft]) async throws
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome
    func accountEntries(accountID: UUID) async throws -> [LocalAccountEntry]
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

    func importRemoteAccounts(_ accounts: [LocalAccount]) async throws {}
    func importRemoteExpenses(_ expenses: [LocalExpenseDraft]) async throws {}
    func createIncome(_ command: LocalIncomeCommand) async throws -> LocalIncome { throw LocalDataError.invalidRecord }
    func income(id: UUID) async throws -> LocalIncome? { nil }
    func incomes(_ monthKey: String) async throws -> LocalIncomeMonth {
        LocalIncomeMonth(profileID: try await prepareProfile().id, incomes: [])
    }
    func updateIncome(_ update: LocalIncomeUpdate) async throws -> LocalIncome { throw LocalDataError.invalidRecord }
    func deleteIncome(id: UUID, expectedVersion: Int64, deletedAt: Date) async throws -> LocalIncomeTombstone { throw LocalDataError.invalidRecord }
    func accountEntries(accountID: UUID) async throws -> [LocalAccountEntry] { [] }
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

    func importRemoteAccounts(_ accounts: [LocalAccount]) async throws {
        let profile = try profileStore.activeProfile()
        let drafts = accounts.map { account in
            LocalAccountDraft(
                id: account.id,
                profileID: profile.id,
                name: account.name,
                kind: account.kind,
                currency: account.currency,
                openingBalanceMinor: account.openingBalanceMinor,
                createdAt: account.createdAt
            )
        }
        try repository.importRemoteAccounts(drafts)
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

    func createIncome(_ command: LocalIncomeCommand) async throws -> LocalIncome {
        let profile = try profileStore.activeProfile()
        let name = command.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = command.category.trimmingCharacters(in: .whitespacesAndNewlines)
        let amountMinor = try LocalExpenseMapper.amountMinor(command.amountText)
        guard !category.isEmpty,
              command.currency == "CNY",
              NativeLocalDate.monthKey(from: command.incomeDate) != nil,
              command.occurredAt.map({ NativeLocalDate.dateKey($0) == command.incomeDate }) ?? true else {
            throw LocalDataError.invalidRecord
        }
        guard amountMinor <= 99_999_999 else { throw LocalDataError.invalidAmount }
        let draft = LocalIncomeDraft(
            id: command.id, profileID: profile.id, accountID: command.accountID,
            amountMinor: amountMinor,
            currency: command.currency, sourceName: name, category: category,
            incomeDate: command.incomeDate, occurredAt: command.occurredAt,
            note: command.note, createdAt: command.createdAt
        )
        return try repository.createIncome(draft)
    }

    func income(id: UUID) async throws -> LocalIncome? {
        let profile = try profileStore.activeProfile()
        guard let value = try repository.income(id: id) else { return nil }
        guard value.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return value
    }

    func incomes(_ monthKey: String) async throws -> LocalIncomeMonth {
        let profile = try profileStore.activeProfile()
        return LocalIncomeMonth(profileID: profile.id, incomes: try repository.incomes(profileID: profile.id, monthKey: monthKey))
    }

    func updateIncome(_ update: LocalIncomeUpdate) async throws -> LocalIncome {
        let profile = try profileStore.activeProfile()
        guard update.amountMinor > 0, update.amountMinor <= 99_999_999 else {
            throw LocalDataError.invalidAmount
        }
        guard !update.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              update.currency == "CNY",
              NativeLocalDate.monthKey(from: update.incomeDate) != nil,
              update.occurredAt.map({ NativeLocalDate.dateKey($0) == update.incomeDate }) ?? true else {
            throw LocalDataError.invalidRecord
        }
        let scopedUpdate = LocalIncomeUpdate(
            id: update.id, profileID: profile.id, expectedVersion: update.expectedVersion,
            accountID: update.accountID, amountMinor: update.amountMinor, currency: update.currency,
            sourceName: update.sourceName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: update.category.trimmingCharacters(in: .whitespacesAndNewlines),
            incomeDate: update.incomeDate, occurredAt: update.occurredAt, note: update.note,
            updatedAt: update.updatedAt
        )
        let value = try repository.updateIncome(scopedUpdate)
        guard value.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return value
    }

    func deleteIncome(id: UUID, expectedVersion: Int64, deletedAt: Date) async throws -> LocalIncomeTombstone {
        let profile = try profileStore.activeProfile()
        let tombstone = try repository.deleteIncome(id: id, profileID: profile.id, expectedVersion: expectedVersion, deletedAt: deletedAt)
        guard tombstone.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return tombstone
    }

    func importRemoteExpenses(_ expenses: [LocalExpenseDraft]) async throws {
        let profile = try profileStore.activeProfile()
        let scoped = expenses.map { expense in
            LocalExpenseDraft(
                id: expense.id,
                profileID: profile.id,
                accountID: expense.accountID,
                amountMinor: expense.amountMinor,
                currency: expense.currency,
                merchantName: expense.merchantName,
                platform: expense.platform,
                category: expense.category,
                paymentMethod: expense.paymentMethod,
                transactionDate: expense.transactionDate,
                transactionTime: expense.transactionTime,
                note: expense.note,
                createdAt: expense.createdAt
            )
        }
        try repository.importRemoteExpenses(scoped)
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

    func accountEntries(accountID: UUID) async throws -> [LocalAccountEntry] {
        let profile = try profileStore.activeProfile()
        return try repository.accountEntries(accountID: accountID).filter { $0.profileID == profile.id }
    }
}
