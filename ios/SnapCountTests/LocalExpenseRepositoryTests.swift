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
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 1)
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
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 1)
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
        XCTAssertEqual(try reopened.pendingOutboxOperations().map(\.operationID), [operationID])
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

    private var fixedDate: Date {
        Date(timeIntervalSince1970: 1_777_000_000)
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
