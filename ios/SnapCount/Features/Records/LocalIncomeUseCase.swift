import Foundation

struct LocalIncomeCommand: Equatable {
    let id: UUID
    let accountID: UUID?
    let amountText: String
    let currency: String
    let incomeCategory: String
    let sourceName: String?
    let incomeDate: String
    let incomeTime: String?
    let note: String?
    let createdAt: Date
}

struct LocalIncomeUpdateCommand: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let accountID: UUID?
    let amountText: String
    let currency: String
    let incomeCategory: String
    let sourceName: String?
    let incomeDate: String
    let incomeTime: String?
    let note: String?
    let updatedAt: Date
}

struct LocalIncomeDeleteCommand: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let deletedAt: Date
}

struct LocalIncomeOutcome: Equatable {
    let income: LocalIncome
    let profileID: UUID
}

struct LocalIncomeDeleteOutcome: Equatable {
    let tombstone: LocalIncomeTombstone
    let profileID: UUID
}

protocol LocalIncomeUseCaseProtocol {
    func create(_ command: LocalIncomeCommand) async throws -> LocalIncomeOutcome
    func update(_ command: LocalIncomeUpdateCommand) async throws -> LocalIncomeOutcome
    func delete(_ command: LocalIncomeDeleteCommand) async throws -> LocalIncomeDeleteOutcome
    func income(id: UUID) async throws -> LocalIncome?
    func month(_ monthKey: String) async throws -> [LocalIncome]
}

final class LocalIncomeUseCase: LocalIncomeUseCaseProtocol {
    private let profileStore: LocalProfileStoreProtocol
    private let repository: LocalIncomeRepositoryProtocol

    init(
        profileStore: LocalProfileStoreProtocol,
        repository: LocalIncomeRepositoryProtocol
    ) {
        self.profileStore = profileStore
        self.repository = repository
    }

    func create(_ command: LocalIncomeCommand) async throws -> LocalIncomeOutcome {
        let profile = try profileStore.activeProfile()
        let draft = try Self.draft(command, profileID: profile.id)
        let income = try repository.createIncome(draft)
        return LocalIncomeOutcome(income: income, profileID: profile.id)
    }

    func update(_ command: LocalIncomeUpdateCommand) async throws -> LocalIncomeOutcome {
        let profile = try profileStore.activeProfile()
        let update = try Self.update(command)
        let income = try repository.updateIncome(update, profileID: profile.id)
        return LocalIncomeOutcome(income: income, profileID: profile.id)
    }

    func delete(_ command: LocalIncomeDeleteCommand) async throws -> LocalIncomeDeleteOutcome {
        let profile = try profileStore.activeProfile()
        let tombstone = try repository.deleteIncome(command, profileID: profile.id)
        return LocalIncomeDeleteOutcome(tombstone: tombstone, profileID: profile.id)
    }

    func income(id: UUID) async throws -> LocalIncome? {
        let profile = try profileStore.activeProfile()
        guard let income = try repository.income(id: id) else { return nil }
        guard income.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return income
    }

    func month(_ monthKey: String) async throws -> [LocalIncome] {
        let profile = try profileStore.activeProfile()
        return try repository.incomes(profileID: profile.id, monthKey: monthKey)
    }

    private static func draft(
        _ command: LocalIncomeCommand,
        profileID: UUID
    ) throws -> LocalIncomeDraft {
        LocalIncomeDraft(
            id: command.id,
            profileID: profileID,
            accountID: command.accountID,
            amountMinor: try LocalIncomeMoney.amountMinor(command.amountText, currency: command.currency),
            currency: normalizedCurrency(command.currency),
            incomeCategory: try normalizedCategory(command.incomeCategory),
            sourceName: normalizedOptionalText(command.sourceName),
            incomeDate: command.incomeDate,
            incomeTime: normalizedOptionalText(command.incomeTime),
            note: normalizedOptionalText(command.note),
            createdAt: command.createdAt
        )
    }

    private static func update(_ command: LocalIncomeUpdateCommand) throws -> LocalIncomeUpdate {
        LocalIncomeUpdate(
            id: command.id,
            expectedVersion: command.expectedVersion,
            accountID: command.accountID,
            amountMinor: try LocalIncomeMoney.amountMinor(command.amountText, currency: command.currency),
            currency: normalizedCurrency(command.currency),
            incomeCategory: try normalizedCategory(command.incomeCategory),
            sourceName: normalizedOptionalText(command.sourceName),
            incomeDate: command.incomeDate,
            incomeTime: normalizedOptionalText(command.incomeTime),
            note: normalizedOptionalText(command.note),
            updatedAt: command.updatedAt
        )
    }

    private static func normalizedCategory(_ value: String) throws -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["salary", "bonus", "freelance", "investment", "reimbursement", "other"].contains(normalized) else {
            throw LocalDataError.invalidRecord
        }
        return normalized
    }

    private static func normalizedCurrency(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

enum LocalIncomeMoney {
    static func amountMinor(_ text: String, currency: String) throws -> Int64 {
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalizedCurrency == "CNY" else {
            throw LocalDataError.invalidRecord
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0 else {
            throw LocalDataError.invalidAmount
        }
        // Current input supports CNY's two decimal places. The table stores the
        // smallest unit and keeps currency open for a future scale registry.
        var scaled = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        guard scaled == rounded,
              rounded > 0,
              rounded <= Decimal(Int64.max) else {
            throw LocalDataError.invalidAmount
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
