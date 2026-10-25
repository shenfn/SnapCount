import Foundation

/// Each item commits independently. The caller reports partial batch success and
/// stops starting items when its workspace generation changes (LF-037.35/36).
final class LocalFinancialBindingRepository {
    private let repository: LocalExpenseRepository
    init(database: LocalDatabase) throws { repository = try LocalExpenseRepository(database: database) }

    func unboundRecords(profileID: UUID) throws -> [NativeUnboundRecord] {
        let expenses = try repository.expenses(profileID: profileID, monthKey: "").filter { $0.accountID == nil }.map { expense in
            NativeUnboundRecord(id: expense.id.uuidString, kind: .expense, title: expense.merchantName,
                amount: Double(expense.amountMinor) / 100, date: expense.transactionDate,
                time: expense.transactionTime, platform: expense.platform, category: expense.category,
                paymentMethod: expense.paymentMethod, note: expense.note, source: "local",
                imagePath: expense.imagePath, imageHash: expense.imageHash, companionMessage: nil)
        }
        return expenses + (try unboundIncomes(profileID: profileID))
    }

    func unboundIncomes(profileID: UUID) throws -> [NativeUnboundRecord] {
        // The unbounded local read is deliberate: unbound facts can predate the
        // currently visible month and must remain reachable for completion.
        try repository.incomes(profileID: profileID, monthKey: "").filter { $0.accountID == nil }.map { income in
            NativeUnboundRecord(id: income.id.uuidString, kind: .income, title: income.sourceName,
                amount: Double(income.amountMinor) / 100, date: income.incomeDate, time: nil,
                occurredAt: income.occurredAt.map { ISO8601DateFormatter().string(from: $0) },
                platform: nil, category: income.category, paymentMethod: nil, note: income.note,
                source: "local", imagePath: income.imagePath, imageHash: income.imageHash,
                companionMessage: nil)
        }
    }

    func bindIncome(profileID: UUID, id: UUID, accountID: UUID?, at now: Date = Date()) throws {
        guard let income = try repository.income(id: id), income.profileID == profileID else { throw LocalDataError.invalidRecord }
        guard income.accountID != accountID else { return }
        _ = try repository.updateIncome(LocalIncomeUpdate(id: id, profileID: profileID,
            expectedVersion: income.localVersion, accountID: accountID,
            amountMinor: income.amountMinor, currency: income.currency, sourceName: income.sourceName,
            category: income.category, incomeDate: income.incomeDate, occurredAt: income.occurredAt,
            note: income.note, updatedAt: now))
    }

    func bindExpense(profileID: UUID, id: UUID, accountID: UUID?, at now: Date = Date()) throws {
        guard let expense = try repository.expense(id: id), expense.profileID == profileID else { throw LocalDataError.invalidRecord }
        guard expense.accountID != accountID else { return }
        _ = try repository.updateExpense(LocalExpenseUpdate(id: id, expectedVersion: expense.localVersion,
            accountID: accountID, amountMinor: expense.amountMinor, currency: expense.currency,
            merchantName: expense.merchantName, platform: expense.platform, category: expense.category,
            paymentMethod: expense.paymentMethod, transactionDate: expense.transactionDate,
            transactionTime: expense.transactionTime, note: expense.note, updatedAt: now), operationID: UUID())
    }
}
