import Foundation
import XCTest
@testable import SnapCount

final class LocalExpenseRepositoryTests: XCTestCase {
    func testLF04004EqualVersionLiveSnapshotCannotChargeDeletedExpenseAgain() throws {
        let url = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: url) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: url))
        let fixture = try makeFixture(repository: repository)
        let id = UUID()
        let draft = expenseDraft(id: id, profileID: fixture.profile.id,
                                 accountID: fixture.account.id, amountMinor: 2_680)
        _ = try repository.createExpense(draft, operationID: UUID())
        let deleted = try repository.deleteExpense(id: id, expectedVersion: 1,
                                                   deletedAt: editedDate, operationID: UUID())
        let snapshot = LocalRemoteSnapshot(accounts: [], expenses: [LocalRemoteExpense(
            id: id, accountID: fixture.account.id, amountMinor: draft.amountMinor,
            currency: draft.currency, merchantName: draft.merchantName, platform: draft.platform,
            category: draft.category, paymentMethod: draft.paymentMethod,
            transactionDate: draft.transactionDate, transactionTime: draft.transactionTime,
            note: draft.note, version: deleted.localVersion, deletedAt: nil
        )], accountEntries: [])
        for _ in 0..<2 {
            _ = try repository.applyRemoteSnapshot(snapshot, profileID: fixture.profile.id)
            XCTAssertNil(try repository.expense(id: id))
            XCTAssertEqual(try repository.expenseTombstone(id: id), deleted)
            XCTAssertTrue(try repository.accountEntries(sourceID: id).allSatisfy { $0.voidedAt != nil })
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.account.id), 10_000)
        }
    }

    func testLOCAL003ProjectionImportsCloudFactsWithoutCreatingOutbox() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let profile = try repository.createProfile(id: UUID(), createdAt: fixedDate)
        let accountID = UUID()
        try repository.importRemoteAccounts([
            LocalAccountDraft(
                id: accountID,
                profileID: profile.id,
                name: "云端银行卡",
                kind: "debit_card",
                currency: "CNY",
                openingBalanceMinor: 20_000,
                createdAt: fixedDate
            )
        ])
        let expenseID = UUID()
        try repository.importRemoteExpenses([
            expenseDraft(
                id: expenseID,
                profileID: profile.id,
                accountID: accountID,
                amountMinor: 1_280
            )
        ])
        try repository.importRemoteExpenses([
            expenseDraft(
                id: expenseID,
                profileID: profile.id,
                accountID: accountID,
                amountMinor: 9_999
            )
        ])

        XCTAssertEqual(try repository.accounts(profileID: profile.id).map(\.id), [accountID])
        XCTAssertEqual(try repository.accounts(profileID: profile.id).first?.origin, "remote")
        XCTAssertEqual(try repository.expense(id: expenseID)?.amountMinor, 1_280)
        XCTAssertEqual(try repository.accountEntries(accountID: accountID).count, 1)
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 0)
    }

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
        let expenseUpload = try XCTUnwrap(
            repository.pendingOutboxUploads(profileID: fixture.profile.id)
                .first(where: { $0.aggregateKind == "expense" })
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(expenseUpload.payloadJSON.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(payload["type"] as? String, "expense")
        XCTAssertEqual(payload["source"] as? String, "manual")
        XCTAssertNotNil(payload["platform"])
        XCTAssertNotNil(payload["note"])
    }

    func testLF03709ArchivedLocalAccountKeepsBalanceAndHistoryAcrossReopenAndRestore() throws {
        let databaseURL = temporaryLocalDatabaseURL()
        defer { removeLocalDatabase(at: databaseURL) }
        let repository = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let profile = try repository.createProfile(id: UUID(), createdAt: fixedDate)
        let accountID = UUID()
        _ = try repository.createAccount(LocalAccountDraft(
            id: accountID, profileID: profile.id, name: "本地现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: fixedDate, isDefaultExpense: true
        ))
        let expenseID = UUID()
        _ = try repository.createExpense(
            expenseDraft(id: expenseID, profileID: profile.id, accountID: accountID, amountMinor: 1_280),
            operationID: UUID()
        )
        let beforeArchive = try XCTUnwrap(repository.accounts(profileID: profile.id).first { $0.id == accountID })
        _ = try repository.updateAccount(LocalAccountUpdate(
            id: accountID, profileID: profile.id, expectedVersion: beforeArchive.localVersion,
            name: beforeArchive.name, kind: beforeArchive.kind, institution: beforeArchive.institution,
            last4: beforeArchive.last4, billDay: nil, paymentDueDay: nil, autoDebitAccountID: nil,
            autoConfirmRepayment: false, gracePeriodDays: 0, isDefaultExpense: false,
            isDefaultIncome: false, isArchived: true, sortOrder: beforeArchive.sortOrder, updatedAt: editedDate
        ))

        let reopened = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let archived = try XCTUnwrap(reopened.accounts(profileID: profile.id).first { $0.id == accountID })
        XCTAssertTrue(archived.isArchived)
        XCTAssertFalse(archived.isDefaultExpense)
        XCTAssertEqual(try reopened.accountBalanceMinor(accountID: accountID), 8_720)
        XCTAssertEqual(try reopened.expense(id: expenseID)?.amountMinor, 1_280)
        let archivedEntrySourceIDs = try reopened.accountEntries(accountID: accountID).map(\.sourceID)
        XCTAssertEqual(archivedEntrySourceIDs, [expenseID])
        XCTAssertThrowsError(try reopened.createExpense(
            expenseDraft(id: UUID(), profileID: profile.id, accountID: accountID, amountMinor: 100),
            operationID: UUID()
        ))

        _ = try reopened.updateAccount(LocalAccountUpdate(
            id: accountID, profileID: profile.id, expectedVersion: archived.localVersion,
            name: archived.name, kind: archived.kind, institution: archived.institution,
            last4: archived.last4, billDay: nil, paymentDueDay: nil, autoDebitAccountID: nil,
            autoConfirmRepayment: false, gracePeriodDays: 0, isDefaultExpense: false,
            isDefaultIncome: false, isArchived: false, sortOrder: archived.sortOrder, updatedAt: editedDate
        ))
        let restored = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let active = try XCTUnwrap(restored.accounts(profileID: profile.id).first { $0.id == accountID })
        XCTAssertFalse(active.isArchived)
        XCTAssertFalse(active.isDefaultExpense, "恢复不自动重建归档前默认项")
        XCTAssertEqual(try restored.accountBalanceMinor(accountID: accountID), 8_720)
        XCTAssertEqual(try restored.accountEntries(accountID: accountID).count, 1)
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
