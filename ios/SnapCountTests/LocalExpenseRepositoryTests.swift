import Foundation
import XCTest
@testable import SnapCount

final class LocalExpenseRepositoryTests: XCTestCase {
    func testLOCAL002A1CreatesProfileAccountAndExpenseWithoutCloudSession() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)

        let expense = try repository.createExpense(
            expenseDraft(
                id: UUID(),
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        XCTAssertEqual(expense.amountMinor, 2_680)
        XCTAssertEqual(expense.accountID, fixture.account.id)
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.aggregateKind), ["account", "expense"])
    }

    func testLOCALDATA004AOutboxConflictRollsBackExpenseAndEntry() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let operationID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: UUID(),
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 1_280
            ),
            operationID: operationID
        )
        let rejectedExpenseID = UUID()

        XCTAssertThrowsError(
            try repository.createExpense(
                expenseDraft(
                    id: rejectedExpenseID,
                    profileID: fixture.profile.id,
                    accountID: fixture.account.id,
                    amountMinor: 2_680
                ),
                operationID: operationID
            )
        )
        XCTAssertNil(try repository.expense(id: rejectedExpenseID))
        XCTAssertEqual(try repository.expenseCount(), 1)
        XCTAssertEqual(try repository.accountEntryCount(), 1)
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.aggregateKind), ["account", "expense"])
    }

    func testLOCAL002B1ReopensExpenseAndPendingOutboxFromFile() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let expenseID = UUID()
        let operationID = UUID()
        let accountID: UUID

        do {
            let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
            let fixture = try makeFixture(repository: repository)
            accountID = fixture.account.id
            _ = try repository.createExpense(
                expenseDraft(
                    id: expenseID,
                    profileID: fixture.profile.id,
                    accountID: fixture.account.id,
                    amountMinor: 2_680
                ),
                operationID: operationID
            )
        }

        let reopened = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        XCTAssertEqual(try reopened.expense(id: expenseID)?.accountID, accountID)
        let reopenedOutbox = try reopened.pendingOutboxOperations()
        XCTAssertEqual(reopenedOutbox.count, 2)
        XCTAssertEqual(reopenedOutbox.last?.operationID, operationID)
        XCTAssertEqual(reopenedOutbox.map(\.aggregateKind), ["account", "expense"])
    }

    func testLOCAL002J1DerivesBalanceFromOpeningBalanceAndLedger() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository, openingBalanceMinor: 10_000)

        _ = try repository.createExpense(
            expenseDraft(
                id: UUID(),
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.account.id), 7_320)
    }

    func testLOCALSPIKE001CRejectsDuplicateExpenseStableIDWithoutOverwrite() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let expenseID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: expenseID,
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        XCTAssertThrowsError(
            try repository.createExpense(
                expenseDraft(
                    id: expenseID,
                    profileID: fixture.profile.id,
                    accountID: fixture.account.id,
                    amountMinor: 3_180
                ),
                operationID: UUID()
            )
        )
        XCTAssertEqual(try repository.expense(id: expenseID)?.amountMinor, 2_680)
        XCTAssertEqual(try repository.expenseCount(), 1)
    }

    func testLOCAL002C1EditsMetadataAndIncrementsVersionWithoutReplacingLedger() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let expenseID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: expenseID,
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        let updated = try repository.updateExpense(
            expenseUpdate(
                id: expenseID,
                expectedVersion: 1,
                accountID: fixture.account.id,
                amountMinor: 2_680,
                merchantName: "盒马鲜生"
            ),
            operationID: UUID()
        )

        XCTAssertEqual(updated.merchantName, "盒马鲜生")
        XCTAssertEqual(updated.localVersion, 2)
        XCTAssertEqual(try repository.accountEntries(sourceID: expenseID).count, 1)
        XCTAssertNil(try repository.accountEntries(sourceID: expenseID).first?.voidedAt)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.account.id), 7_320)
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.aggregateVersion), [1, 1, 2])
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.aggregateKind), ["account", "expense", "expense"])
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.operationKind), ["upsert", "upsert", "upsert"])
    }

    func testLOCAL002C2AmountEditVoidsOldEntryAndCreatesReplacement() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let expenseID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: expenseID,
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        _ = try repository.updateExpense(
            expenseUpdate(
                id: expenseID,
                expectedVersion: 1,
                accountID: fixture.account.id,
                amountMinor: 3_180
            ),
            operationID: UUID()
        )

        let entries = try repository.accountEntries(sourceID: expenseID)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.filter { $0.voidedAt != nil }.map(\.amountMinor), [2_680])
        XCTAssertEqual(entries.filter { $0.voidedAt == nil }.map(\.amountMinor), [3_180])
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.account.id), 6_820)
    }

    func testLOCAL002C3AccountMoveRestoresOldBalanceAndChargesNewAccount() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let targetAccount = try repository.createAccount(
            LocalAccountDraft(
                id: UUID(),
                profileID: fixture.profile.id,
                name: "本地储蓄卡",
                kind: "debit_card",
                currency: "CNY",
                openingBalanceMinor: 5_000,
                createdAt: fixedDate
            )
        )
        let expenseID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: expenseID,
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        _ = try repository.updateExpense(
            expenseUpdate(
                id: expenseID,
                expectedVersion: 1,
                accountID: targetAccount.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.account.id), 10_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: targetAccount.id), 2_320)
        let entries = try repository.accountEntries(sourceID: expenseID)
        XCTAssertEqual(entries.filter { $0.voidedAt != nil }.map(\.accountID), [fixture.account.id])
        XCTAssertEqual(entries.filter { $0.voidedAt == nil }.map(\.accountID), [targetAccount.id])
    }

    func testLOCAL002C4RejectsStaleExpectedVersionWithoutSideEffects() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let expenseID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: expenseID,
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )
        _ = try repository.updateExpense(
            expenseUpdate(
                id: expenseID,
                expectedVersion: 1,
                accountID: fixture.account.id,
                amountMinor: 2_680,
                merchantName: "盒马鲜生"
            ),
            operationID: UUID()
        )

        XCTAssertThrowsError(
            try repository.updateExpense(
                expenseUpdate(
                    id: expenseID,
                    expectedVersion: 1,
                    accountID: fixture.account.id,
                    amountMinor: 3_180
                ),
                operationID: UUID()
            )
        ) { error in
            XCTAssertEqual(error as? LocalDataError, .versionConflict(expected: 1, actual: 2))
        }
        XCTAssertEqual(try repository.expense(id: expenseID)?.merchantName, "盒马鲜生")
        XCTAssertEqual(try repository.expense(id: expenseID)?.amountMinor, 2_680)
        XCTAssertEqual(try repository.accountEntries(sourceID: expenseID).count, 1)
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 3)
    }

    func testLOCAL002D1DeleteCreatesTombstoneVoidsLedgerAndRestoresBalance() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let expenseID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: expenseID,
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: UUID()
        )

        let tombstone = try repository.deleteExpense(
            id: expenseID,
            expectedVersion: 1,
            deletedAt: editedDate,
            operationID: UUID()
        )

        XCTAssertEqual(tombstone.id, expenseID)
        XCTAssertEqual(tombstone.localVersion, 2)
        XCTAssertEqual(tombstone.deletedAt, editedDate)
        XCTAssertNil(try repository.expense(id: expenseID))
        XCTAssertEqual(try repository.expenseCount(), 0)
        XCTAssertEqual(try repository.expenseTombstone(id: expenseID), tombstone)
        XCTAssertEqual(try repository.accountEntryCount(), 0)
        XCTAssertNotNil(try repository.accountEntries(sourceID: expenseID).first?.voidedAt)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.account.id), 10_000)
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.aggregateKind), ["account", "expense", "expense"])
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.operationKind), ["upsert", "upsert", "delete"])
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.aggregateVersion), [1, 1, 2])
    }

    func testLOCAL002D2OutboxConflictRollsBackEditAndDelete() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let fixture = try makeFixture(repository: repository)
        let expenseID = UUID()
        let createOperationID = UUID()

        _ = try repository.createExpense(
            expenseDraft(
                id: expenseID,
                profileID: fixture.profile.id,
                accountID: fixture.account.id,
                amountMinor: 2_680
            ),
            operationID: createOperationID
        )

        XCTAssertThrowsError(
            try repository.updateExpense(
                expenseUpdate(
                    id: expenseID,
                    expectedVersion: 1,
                    accountID: fixture.account.id,
                    amountMinor: 3_180
                ),
                operationID: createOperationID
            )
        )
        XCTAssertEqual(try repository.expense(id: expenseID)?.amountMinor, 2_680)
        XCTAssertEqual(try repository.expense(id: expenseID)?.localVersion, 1)
        XCTAssertEqual(try repository.accountEntries(sourceID: expenseID).count, 1)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.account.id), 7_320)

        XCTAssertThrowsError(
            try repository.deleteExpense(
                id: expenseID,
                expectedVersion: 1,
                deletedAt: editedDate,
                operationID: createOperationID
            )
        )
        XCTAssertNotNil(try repository.expense(id: expenseID))
        XCTAssertNil(try repository.expenseTombstone(id: expenseID))
        XCTAssertNil(try repository.accountEntries(sourceID: expenseID).first?.voidedAt)
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 2)
    }

    func testLOCAL002B2ReopensEditedExpenseAndDeletedTombstone() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let editedExpenseID = UUID()
        let deletedExpenseID = UUID()
        let accountID: UUID

        do {
            let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
            let fixture = try makeFixture(repository: repository)
            accountID = fixture.account.id
            _ = try repository.createExpense(
                expenseDraft(
                    id: editedExpenseID,
                    profileID: fixture.profile.id,
                    accountID: fixture.account.id,
                    amountMinor: 2_680
                ),
                operationID: UUID()
            )
            _ = try repository.updateExpense(
                expenseUpdate(
                    id: editedExpenseID,
                    expectedVersion: 1,
                    accountID: fixture.account.id,
                    amountMinor: 3_180
                ),
                operationID: UUID()
            )
            _ = try repository.createExpense(
                expenseDraft(
                    id: deletedExpenseID,
                    profileID: fixture.profile.id,
                    accountID: fixture.account.id,
                    amountMinor: 1_280
                ),
                operationID: UUID()
            )
            _ = try repository.deleteExpense(
                id: deletedExpenseID,
                expectedVersion: 1,
                deletedAt: editedDate,
                operationID: UUID()
            )
        }

        let reopened = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        XCTAssertEqual(try reopened.expense(id: editedExpenseID)?.amountMinor, 3_180)
        XCTAssertEqual(try reopened.expense(id: editedExpenseID)?.localVersion, 2)
        XCTAssertNil(try reopened.expense(id: deletedExpenseID))
        XCTAssertEqual(try reopened.expenseTombstone(id: deletedExpenseID)?.localVersion, 2)
        XCTAssertEqual(try reopened.expenseTombstone(id: deletedExpenseID)?.deletedAt, editedDate)
        XCTAssertEqual(try reopened.accountEntries(sourceID: editedExpenseID).count, 2)
        XCTAssertEqual(try reopened.accountEntries(sourceID: deletedExpenseID).count, 1)
        XCTAssertEqual(try reopened.accountBalanceMinor(accountID: accountID), 6_820)
    }

    private func makeFixture(
        repository: LocalExpenseRepository,
        openingBalanceMinor: Int64 = 10_000
    ) throws -> (profile: LocalProfile, account: LocalAccount) {
        let profile = try repository.createProfile(id: UUID(), createdAt: fixedDate)
        let account = try repository.createAccount(
            LocalAccountDraft(
                id: UUID(),
                profileID: profile.id,
                name: "本地钱包",
                kind: "wallet_balance",
                currency: "CNY",
                openingBalanceMinor: openingBalanceMinor,
                createdAt: fixedDate
            )
        )
        return (profile, account)
    }

    private func expenseDraft(
        id: UUID,
        profileID: UUID,
        accountID: UUID,
        amountMinor: Int64
    ) -> LocalExpenseDraft {
        LocalExpenseDraft(
            id: id,
            profileID: profileID,
            accountID: accountID,
            amountMinor: amountMinor,
            currency: "CNY",
            merchantName: "全家便利店",
            platform: "线下消费",
            category: "food",
            paymentMethod: "微信支付",
            transactionDate: "2026-08-23",
            transactionTime: "12:30:00",
            note: "午餐",
            createdAt: fixedDate
        )
    }

    private func expenseUpdate(
        id: UUID,
        expectedVersion: Int64,
        accountID: UUID,
        amountMinor: Int64,
        merchantName: String = "全家便利店"
    ) -> LocalExpenseUpdate {
        LocalExpenseUpdate(
            id: id,
            expectedVersion: expectedVersion,
            accountID: accountID,
            amountMinor: amountMinor,
            currency: "CNY",
            merchantName: merchantName,
            platform: "线下消费",
            category: "food",
            paymentMethod: "微信支付",
            transactionDate: "2026-08-23",
            transactionTime: "12:30:00",
            note: "午餐",
            updatedAt: editedDate
        )
    }

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_777_000_000)
    }

    private var editedDate: Date {
        fixedDate.addingTimeInterval(3_600)
    }
}

private func temporaryLocalDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("snapcount-local-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}

private func removeLocalDatabase(at databaseURL: URL) {
    for url in [
        databaseURL,
        URL(fileURLWithPath: databaseURL.path + "-shm"),
        URL(fileURLWithPath: databaseURL.path + "-wal")
    ] {
        try? FileManager.default.removeItem(at: url)
    }
}
