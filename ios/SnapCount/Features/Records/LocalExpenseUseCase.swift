import Foundation

struct LocalExpenseCommand: Equatable {
    let id: UUID
    let accountID: UUID?
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
    var imageData: Data? = nil
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
    var imageData: Data? = nil
}

struct LocalExpenseUpdateCommand: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let accountID: UUID?
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
    var imageData: Data? = nil
    var removeImage: Bool = false
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
    var institution: String = ""
    var last4: String = ""
    var billDay: Int? = nil
    var paymentDueDay: Int? = nil
    var autoDebitAccountID: UUID? = nil
    var autoConfirmRepayment: Bool = false
    var gracePeriodDays: Int = 0
    var isDefaultExpense: Bool = false
    var isDefaultIncome: Bool = false
    var sortOrder: Int = 0
}

struct LocalAccountEditCommand: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let name: String
    let kind: String
    let institution: String
    let last4: String
    let billDay: Int?
    let paymentDueDay: Int?
    let autoDebitAccountID: UUID?
    let autoConfirmRepayment: Bool
    let gracePeriodDays: Int
    let isDefaultExpense: Bool
    let isDefaultIncome: Bool
    let isArchived: Bool
    let sortOrder: Int
}

protocol LocalExpenseUseCaseProtocol {
    func prepareProfile() async throws -> LocalProfile
    func prepareWorkspace() async throws -> LocalExpenseWorkspace
    func accounts() async throws -> [LocalAccount]
    func accountBalanceMinor(_ accountID: UUID) async throws -> Int64
    func expense(id: UUID) async throws -> LocalExpense?
    func createAccount(_ command: LocalAccountSetupCommand) async throws -> LocalAccount
    func updateAccount(_ command: LocalAccountEditCommand) async throws -> LocalAccount
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
    func ensureRepaymentCycles(_ monthKey: String, now: Date) async throws -> [LocalRepaymentCycle]
    func repaymentCycles(accountID: UUID) async throws -> [LocalRepaymentCycle]
    func liabilityPayments(accountID: UUID) async throws -> [LocalLiabilityPayment]
    func confirmRepayment(cycleID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, status: String?, note: String, paidAt: Date) async throws -> LocalRepaymentCycle
    func confirmScreenshotRepayment(stagingID: String, cycleID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, note: String, paidAt: Date) async throws -> LocalRepaymentCycle
    func revokeLiabilityPayment(id: UUID, reason: String, now: Date) async throws -> LocalRepaymentCycle?
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

    func updateAccount(_ command: LocalAccountEditCommand) async throws -> LocalAccount {
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
    func ensureRepaymentCycles(_ monthKey: String, now: Date) async throws -> [LocalRepaymentCycle] { throw LocalDataError.invalidRecord }
    func repaymentCycles(accountID: UUID) async throws -> [LocalRepaymentCycle] { [] }
    func liabilityPayments(accountID: UUID) async throws -> [LocalLiabilityPayment] { [] }
    func confirmRepayment(cycleID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, status: String?, note: String, paidAt: Date) async throws -> LocalRepaymentCycle { throw LocalDataError.invalidRecord }
    func confirmScreenshotRepayment(stagingID: String, cycleID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, note: String, paidAt: Date) async throws -> LocalRepaymentCycle { throw LocalDataError.invalidRecord }
    func revokeLiabilityPayment(id: UUID, reason: String, now: Date) async throws -> LocalRepaymentCycle? { throw LocalDataError.invalidRecord }
}

final class LocalExpenseUseCase: LocalExpenseUseCaseProtocol {
    private let profileStore: LocalProfileStoreProtocol
    private let repository: LocalExpenseRepositoryProtocol
    private let operationIDProvider: () -> UUID
    private let imageStore: LocalImageStore?

    init(
        profileStore: LocalProfileStoreProtocol,
        repository: LocalExpenseRepositoryProtocol,
        operationIDProvider: @escaping () -> UUID = UUID.init,
        imageStore: LocalImageStore? = nil
    ) {
        self.profileStore = profileStore
        self.repository = repository
        self.operationIDProvider = operationIDProvider
        self.imageStore = imageStore
    }

    private func saveImage(_ data: Data?) throws -> LocalImageReference? {
        guard let data else { return nil }
        guard let imageStore else { throw LocalDataError.invalidRecord }
        return try imageStore.save(data: data, owner: UUID().uuidString)
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
            createdAt: command.createdAt,
            institution: command.institution,
            last4: command.last4,
            billDay: command.billDay,
            paymentDueDay: command.paymentDueDay,
            autoDebitAccountID: command.autoDebitAccountID,
            autoConfirmRepayment: command.autoConfirmRepayment,
            gracePeriodDays: command.gracePeriodDays,
            isDefaultExpense: command.isDefaultExpense,
            isDefaultIncome: command.isDefaultIncome,
            sortOrder: command.sortOrder
        )
        guard !draft.name.isEmpty else { throw LocalDataError.invalidRecord }
        guard draft.openingBalanceMinor >= 0 else { throw LocalDataError.invalidAmount }
        guard LocalExpenseMapper.allowedAccountKinds.contains(draft.kind) else {
            throw LocalDataError.invalidAccountKind
        }
        return try repository.createAccount(draft)
    }

    func updateAccount(_ command: LocalAccountEditCommand) async throws -> LocalAccount {
        let profile = try profileStore.activeProfile()
        guard !command.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              LocalExpenseMapper.allowedAccountKinds.contains(command.kind) else {
            throw LocalDataError.invalidRecord
        }
        return try repository.updateAccount(LocalAccountUpdate(
            id: command.id, profileID: profile.id, expectedVersion: command.expectedVersion,
            name: command.name.trimmingCharacters(in: .whitespacesAndNewlines), kind: command.kind,
            institution: command.institution, last4: command.last4, billDay: command.billDay,
            paymentDueDay: command.paymentDueDay, autoDebitAccountID: command.autoDebitAccountID,
            autoConfirmRepayment: command.autoConfirmRepayment, gracePeriodDays: command.gracePeriodDays,
            isDefaultExpense: command.isDefaultExpense, isDefaultIncome: command.isDefaultIncome,
            isArchived: command.isArchived, sortOrder: command.sortOrder, updatedAt: Date()
        ))
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
                createdAt: account.createdAt,
                institution: account.institution,
                last4: account.last4,
                billDay: account.billDay,
                paymentDueDay: account.paymentDueDay,
                autoDebitAccountID: account.autoDebitAccountID,
                autoConfirmRepayment: account.autoConfirmRepayment,
                gracePeriodDays: account.gracePeriodDays,
                lastReconciledAt: account.lastReconciledAt,
                isDefaultExpense: account.isDefaultExpense,
                isDefaultIncome: account.isDefaultIncome,
                isArchived: account.isArchived,
                sortOrder: account.sortOrder
            )
        }
        try repository.importRemoteAccounts(drafts)
    }

    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome {
        let profile = try profileStore.activeProfile()
        if let accountID = command.accountID {
            guard try repository.accounts(profileID: profile.id).contains(where: { $0.id == accountID }) else {
                throw LocalDataError.accountRequired
            }
        }
        var draft = try LocalExpenseMapper.createDraft(command, profileID: profile.id)
        let image = try saveImage(command.imageData)
        draft.imagePath = image?.path; draft.imageHash = image?.hash
        let expense: LocalExpense
        do { expense = try repository.createExpense(draft, operationID: operationIDProvider()) }
        catch { try? imageStore?.remove(path: image?.path); throw error }
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
        var draft = LocalIncomeDraft(
            id: command.id, profileID: profile.id, accountID: command.accountID,
            amountMinor: amountMinor,
            currency: command.currency, sourceName: name, category: category,
            incomeDate: command.incomeDate, occurredAt: command.occurredAt,
            note: command.note, createdAt: command.createdAt
        )
        let image = try saveImage(command.imageData)
        draft.imagePath = image?.path; draft.imageHash = image?.hash
        do { return try repository.createIncome(draft) }
        catch { try? imageStore?.remove(path: image?.path); throw error }
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
        var scopedUpdate = LocalIncomeUpdate(
            id: update.id, profileID: profile.id, expectedVersion: update.expectedVersion,
            accountID: update.accountID, amountMinor: update.amountMinor, currency: update.currency,
            sourceName: update.sourceName.trimmingCharacters(in: .whitespacesAndNewlines),
            category: update.category.trimmingCharacters(in: .whitespacesAndNewlines),
            incomeDate: update.incomeDate, occurredAt: update.occurredAt, note: update.note,
            updatedAt: update.updatedAt
        )
        let image = try saveImage(update.imageData)
        scopedUpdate.imagePath = image?.path; scopedUpdate.imageHash = image?.hash
        scopedUpdate.removeImage = update.removeImage
        let value: LocalIncome
        do { value = try repository.updateIncome(scopedUpdate) }
        catch { try? imageStore?.remove(path: image?.path); throw error }
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
        guard try repository.expense(id: command.id)?.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        var update = try LocalExpenseMapper.update(command)
        let image = try saveImage(command.imageData)
        update.imagePath = image?.path; update.imageHash = image?.hash
        update.removeImage = command.removeImage
        let expense: LocalExpense
        do { expense = try repository.updateExpense(update, operationID: operationIDProvider()) }
        catch { try? imageStore?.remove(path: image?.path); throw error }
        guard expense.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return LocalExpenseOutcome(expense: expense, tombstone: nil, profileID: profile.id)
    }

    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome {
        let profile = try profileStore.activeProfile()
        guard try repository.expense(id: command.id)?.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
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

    func ensureRepaymentCycles(_ monthKey: String, now: Date = Date()) async throws -> [LocalRepaymentCycle] {
        let profile = try profileStore.activeProfile()
        return try repository.ensureRepaymentCycles(profileID: profile.id, monthKey: monthKey, now: now)
    }

    func repaymentCycles(accountID: UUID) async throws -> [LocalRepaymentCycle] {
        let profile = try profileStore.activeProfile()
        return try repository.repaymentCycles(accountID: accountID).filter { $0.profileID == profile.id }
    }

    func liabilityPayments(accountID: UUID) async throws -> [LocalLiabilityPayment] {
        let profile = try profileStore.activeProfile()
        return try repository.liabilityPayments(accountID: accountID).filter { $0.profileID == profile.id }
    }

    func confirmRepayment(
        cycleID: UUID,
        paidAmountMinor: Int64,
        debitAccountID: UUID?,
        status: String?,
        note: String,
        paidAt: Date
    ) async throws -> LocalRepaymentCycle {
        guard paidAmountMinor >= 0 else { throw LocalDataError.invalidAmount }
        let profile = try profileStore.activeProfile()
        return try repository.confirmRepayment(
            cycleID: cycleID, profileID: profile.id, paidAmountMinor: paidAmountMinor,
            debitAccountID: debitAccountID, status: status, note: note, paidAt: paidAt
        )
    }

    func confirmScreenshotRepayment(
        stagingID: String,
        cycleID: UUID,
        paidAmountMinor: Int64,
        debitAccountID: UUID?,
        note: String,
        paidAt: Date
    ) async throws -> LocalRepaymentCycle {
        guard paidAmountMinor > 0 else { throw LocalDataError.invalidAmount }
        let profile = try profileStore.activeProfile()
        return try repository.confirmScreenshotRepayment(
            stagingID: stagingID, cycleID: cycleID, profileID: profile.id,
            paidAmountMinor: paidAmountMinor, debitAccountID: debitAccountID,
            note: note, paidAt: paidAt
        )
    }

    func revokeLiabilityPayment(id: UUID, reason: String, now: Date = Date()) async throws -> LocalRepaymentCycle? {
        let profile = try profileStore.activeProfile()
        return try repository.revokeLiabilityPayment(id: id, profileID: profile.id, reason: reason, now: now)
    }
}
