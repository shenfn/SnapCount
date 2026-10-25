import XCTest
import GRDB
@testable import SnapCount

final class LocalPendingFinancialTests: XCTestCase {
    func testLF037PendingExpenseCanRemainUnboundUntilAccountCompletion() throws {
        try withFixture { database, profile, cash, repository in
            let pending = LocalPendingFinancialRepository(database: database)
            let id = UUID()
            try pending.stage(LocalPendingFinancialRecord(id: id, profileID: profile, amountMinor: 2000,
                currency: "CNY", merchantName: "合成未绑消费", transactionDate: "2026-10-24",
                transactionTime: nil, occurredAt: nil, createdAt: Date()))
            var draft = makeDraft(id: id, account: cash, kind: .expense)
            draft.accountId = nil
            _ = try pending.resolve(profileID: profile, pendingID: id, draft: draft)
            _ = try pending.resolve(profileID: profile, pendingID: id, draft: draft)
            XCTAssertNil(try repository.expense(id: id)?.accountID)
            XCTAssertEqual(try repository.expenseCount(), 1)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: cash), 10000)
            XCTAssertEqual(try LocalFinancialBindingRepository(database: database).unboundRecords(profileID: profile).count, 1)
        }
    }

    func testLF03731ExpenseConfirmationRetainsIDAndChargesOnlyOnce() throws {
        try withFixture { database, profile, account, repository in
            let pending = LocalPendingFinancialRepository(database: database)
            let id = UUID()
            try pending.stage(LocalPendingFinancialRecord(id: id, profileID: profile, amountMinor: 2000,
                currency: "CNY", merchantName: "原商户", transactionDate: "2026-10-24",
                transactionTime: "08:30", occurredAt: nil, createdAt: Date(), imagePath: "expense/original.jpg", imageHash: "hash"))
            let draft = makeDraft(id: id, account: account, kind: .expense)
            let first = try pending.resolve(profileID: profile, pendingID: id, draft: draft)
            let retry = try pending.resolve(profileID: profile, pendingID: id, draft: draft)
            XCTAssertEqual(first.recordId, id.uuidString)
            XCTAssertTrue(retry.idempotentRetry)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 8000)
            XCTAssertEqual(try repository.expense(id: id)?.transactionTime, "08:30")
            XCTAssertEqual(try repository.expense(id: id)?.imagePath, "expense/original.jpg")
            XCTAssertTrue(try pending.pending(profileID: profile).isEmpty)
        }
    }

    func testLF03741IncomeRetryAndLF03744ArchiveFailureAreAtomic() throws {
        try withFixture { database, profile, account, repository in
            let pending = LocalPendingFinancialRepository(database: database)
            let id = UUID()
            try pending.stage(LocalPendingFinancialRecord(id: id, profileID: profile, amountMinor: 2000,
                currency: "CNY", merchantName: "原商户", transactionDate: "2026-10-24",
                transactionTime: nil, occurredAt: nil, createdAt: Date()))
            let draft = makeDraft(id: id, account: account, kind: .income)
            try database.writer.write { db in
                try db.execute(sql: "CREATE TRIGGER reject_pending_archive BEFORE UPDATE ON local_pending_transactions BEGIN SELECT RAISE(ABORT, 'injected'); END")
            }
            XCTAssertThrowsError(try pending.resolve(profileID: profile, pendingID: id, draft: draft))
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 10000)
            XCTAssertTrue(try repository.incomes(profileID: profile, monthKey: "2026-10").isEmpty)
            XCTAssertEqual(try pending.pending(profileID: profile).count, 1)
            try database.writer.write { db in try db.execute(sql: "DROP TRIGGER reject_pending_archive") }
            let first = try pending.resolve(profileID: profile, pendingID: id, draft: draft)
            let retry = try pending.resolve(profileID: profile, pendingID: id, draft: draft)
            XCTAssertEqual(first.recordId, retry.recordId)
            XCTAssertTrue(retry.idempotentRetry)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 12000)
            XCTAssertEqual(try repository.incomes(profileID: profile, monthKey: "2026-10").count, 1)
        }
    }

    func testLF03733IncomeBindingRebindingAndClearingPreserveFactAndBalances() throws {
        try withFixture { database, profile, account, repository in
            let id = UUID()
            _ = try repository.createIncome(LocalIncomeDraft(id: id, profileID: profile, accountID: nil,
                amountMinor: 2000, currency: "CNY", sourceName: "测试收入", category: "other",
                incomeDate: "2026-10-24", occurredAt: nil, note: nil, createdAt: Date()))
            let binding = try LocalFinancialBindingRepository(database: database)
            XCTAssertEqual(try binding.unboundIncomes(profileID: profile).count, 1)
            try binding.bindIncome(profileID: profile, id: id, accountID: account)
            try binding.bindIncome(profileID: profile, id: id, accountID: account)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 12000)
            try binding.bindIncome(profileID: profile, id: id, accountID: nil)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 10000)
            XCTAssertEqual(try repository.income(id: id)?.incomeDate, "2026-10-24")
        }
    }

    func testLF03732ExpenseBindingRebindingAndClearingPreserveDirection() throws {
        try withFixture { database, profile, cash, repository in
            let liability = UUID(), id = UUID()
            _ = try repository.createAccount(LocalAccountDraft(id: liability, profileID: profile,
                name: "信用账户", kind: "credit_line", currency: "CNY", openingBalanceMinor: 10000, createdAt: Date()))
            _ = try repository.createExpense(LocalExpenseDraft(id: id, profileID: profile, accountID: nil,
                amountMinor: 2000, currency: "CNY", merchantName: "原商户", platform: "微信",
                category: "food", paymentMethod: "微信支付", transactionDate: "2026-10-24",
                transactionTime: "08:30", note: nil, createdAt: Date()), operationID: UUID())
            let binding = try LocalFinancialBindingRepository(database: database)
            XCTAssertEqual(try binding.unboundRecords(profileID: profile).count, 1)
            try binding.bindExpense(profileID: profile, id: id, accountID: cash)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: cash), 8000)
            try binding.bindExpense(profileID: profile, id: id, accountID: liability)
            try binding.bindExpense(profileID: profile, id: id, accountID: liability)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: cash), 10000)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: liability), 12000)
            try binding.bindExpense(profileID: profile, id: id, accountID: nil)
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: liability), 10000)
            XCTAssertEqual(try repository.expense(id: id)?.transactionTime, "08:30")
        }
    }

    private func withFixture(_ body: (LocalDatabase, UUID, UUID, LocalExpenseRepository) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("facts.sqlite"))
        let repository = try LocalExpenseRepository(database: database)
        let profile = UUID(), account = UUID()
        _ = try repository.createProfile(id: profile, createdAt: Date())
        _ = try repository.createAccount(LocalAccountDraft(id: account, profileID: profile, name: "现金", kind: "cash", currency: "CNY", openingBalanceMinor: 10000, createdAt: Date()))
        try body(database, profile, account, repository)
    }

    private func makeDraft(id: UUID, account: UUID, kind: NativePendingEntryKind) -> NativePendingResolutionDraft {
        let detail = NativeRecordDetail(id: "expense/\(id.uuidString)", rawId: id.uuidString, kind: kind.rawValue,
            title: "待补全", subtitle: "2026-10-24", value: "¥20", detailRows: [], imageURL: nil,
            imageLoadError: false, imagePath: nil, imageHash: nil, amount: 20, merchantName: "测试商户",
            platform: "微信", category: "food", paymentMethod: "微信支付", recordDate: "2026-10-24",
            note: nil, companionMessage: nil, accountId: account.uuidString, systemImage: "creditcard", payload: nil)
        var draft = NativePendingResolutionDraft(detail: detail)
        draft.amountText = "20.00"
        draft.kind = kind
        if kind == .income { draft.incomeCategory = "salary" }
        return draft
    }
    // LF-037.31/41: a pending financial transaction is durable, separate from
    // universal-domain staging, and must retain the source date and image.
    func testLF03731PendingFinancialStorageIsDurable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pending.sqlite")
        let profileID = UUID()
        let pendingID = UUID()
        do {
            let database = try LocalDatabase(databaseURL: url)
            let repository = try LocalExpenseRepository(database: database)
            _ = try repository.createProfile(id: profileID, createdAt: Date())
            let exists = try database.writer.read { db in
                try db.tableExists("local_pending_transactions")
            }
            XCTAssertTrue(exists, "Pending finance needs its own durable state, not an in-memory remote row")
            guard exists else { return }
            try database.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO local_pending_transactions
                    (id, profile_id, amount_minor, currency, merchant_name, transaction_date,
                     transaction_time, occurred_at, created_at, image_path, image_hash, status)
                    VALUES (?, ?, 2000, 'CNY', '测试商户', '2026-10-24', '08:30', ?, ?, 'expense/original.jpg', 'original-hash', 'pending')
                    """, arguments: [pendingID.uuidString, profileID.uuidString, Date(), Date()])
            }
        }
        let reopened = try LocalDatabase(databaseURL: url)
        let row = try reopened.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM local_pending_transactions WHERE id = ?", arguments: [pendingID.uuidString])
        }
        XCTAssertEqual(row?["amount_minor"] as Int64?, 2000)
        XCTAssertEqual(row?["transaction_date"] as String?, "2026-10-24")
        XCTAssertEqual(row?["image_path"] as String?, "expense/original.jpg")
        XCTAssertEqual(row?["status"] as String?, "pending")
    }

    // LF-037.41/44: converted income requires a stable source relationship so
    // a retry cannot create a second income. This checks a real SQLite contract.
    func testLF03741IncomeHasUniquePendingSourceRelationship() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let columns = try database.writer.read { db in try db.columns(in: "local_income_records") }
        XCTAssertTrue(columns.contains { $0.name == "source_pending_transaction_id" },
                      "Income retries must resolve the persisted original pending transaction")
    }
}
