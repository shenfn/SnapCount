import Foundation
import XCTest
@testable import SnapCount

final class LocalExpensePortabilityTests: XCTestCase {
    func testLOCAL002E1ExportsVersionedFactsRelationshipsAndLedgerHistory() throws {
        let fixture = try makeArchiveFixture()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LocalExpenseArchive.self, from: fixture.data)

        XCTAssertEqual(archive.format, "jiezi-local-expense-archive")
        XCTAssertEqual(archive.schemaVersion, 1)
        XCTAssertEqual(archive.profile.id, fixture.profileID)
        XCTAssertEqual(archive.accounts.map(\.id), [fixture.accountID])
        XCTAssertEqual(Set(archive.expenses.map(\.id)), [fixture.activeExpenseID, fixture.deletedExpenseID])
        XCTAssertEqual(archive.accountEntries.count, 3)
        XCTAssertEqual(archive.expenses.first { $0.id == fixture.activeExpenseID }?.localVersion, 2)
        XCTAssertNil(archive.expenses.first { $0.id == fixture.activeExpenseID }?.deletedAt)
        XCTAssertEqual(archive.expenses.first { $0.id == fixture.deletedExpenseID }?.localVersion, 2)
        XCTAssertNotNil(archive.expenses.first { $0.id == fixture.deletedExpenseID }?.deletedAt)
    }

    func testLOCAL002E2ExportExcludesCloudBindingCredentialsCachesAndSourceOutbox() throws {
        let fixture = try makeArchiveFixture()
        let json = String(decoding: fixture.data, as: UTF8.self)

        XCTAssertFalse(json.contains("cloudUserID"))
        XCTAssertFalse(json.contains("syncEnabled"))
        XCTAssertFalse(json.contains("accessToken"))
        XCTAssertFalse(json.contains("apiKey"))
        XCTAssertFalse(json.contains("signedURL"))
        XCTAssertFalse(json.contains("outbox"))
        for operationID in fixture.sourceOperationIDs {
            XCTAssertFalse(json.contains(operationID.uuidString))
        }
    }

    func testLOCAL002F1ImportsArchiveIntoEmptyDatabaseAndRestoresBalance() throws {
        let fixture = try makeArchiveFixture()
        let targetURL = temporaryPortabilityDatabaseURL()
        defer { removePortabilityDatabase(at: targetURL) }
        let database = try LocalDatabase(databaseURL: targetURL)
        let repository = try LocalExpenseRepository(database: database)
        let portability = LocalExpensePortability(database: database)

        let result = try portability.importArchive(fixture.data, importedAt: importedDate)

        XCTAssertEqual(
            result,
            LocalExpenseImportResult(
                insertedProfiles: 1,
                insertedAccounts: 1,
                insertedExpenses: 2,
                insertedAccountEntries: 3,
                insertedOutboxOperations: 3,
                skippedProfiles: 0,
                skippedAccounts: 0,
                skippedExpenses: 0,
                skippedAccountEntries: 0
            )
        )
        XCTAssertEqual(try repository.expense(id: fixture.activeExpenseID)?.amountMinor, 3_180)
        XCTAssertEqual(try repository.expense(id: fixture.activeExpenseID)?.localVersion, 2)
        XCTAssertNil(try repository.expense(id: fixture.deletedExpenseID))
        XCTAssertEqual(try repository.expenseTombstone(id: fixture.deletedExpenseID)?.localVersion, 2)
        XCTAssertEqual(try repository.accountEntries(sourceID: fixture.activeExpenseID).count, 2)
        XCTAssertEqual(try repository.accountEntries(sourceID: fixture.deletedExpenseID).count, 1)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.accountID), 6_820)
        XCTAssertEqual(try repository.pendingOutboxOperations().map(\.aggregateKind), ["account", "expense", "expense"])
        XCTAssertEqual(Set(try repository.pendingOutboxOperations().map(\.operationKind)), ["upsert", "delete"])
        let activeUpload = try XCTUnwrap(
            repository.pendingOutboxUploads(profileID: fixture.profileID)
                .first(where: { $0.aggregateID == fixture.activeExpenseID })
        )
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(activeUpload.payloadJSON.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(payload["type"] as? String, "expense")
        XCTAssertEqual(payload["source"] as? String, "manual")
    }

    func testLOCAL002F2RepeatedImportIsIdempotentAndDoesNotAppendOutbox() throws {
        let fixture = try makeArchiveFixture()
        let targetURL = temporaryPortabilityDatabaseURL()
        defer { removePortabilityDatabase(at: targetURL) }
        let database = try LocalDatabase(databaseURL: targetURL)
        let repository = try LocalExpenseRepository(database: database)
        let portability = LocalExpensePortability(database: database)

        _ = try portability.importArchive(fixture.data, importedAt: importedDate)
        let repeated = try portability.importArchive(
            fixture.data,
            importedAt: importedDate.addingTimeInterval(60)
        )

        XCTAssertEqual(repeated.insertedProfiles, 0)
        XCTAssertEqual(repeated.insertedAccounts, 0)
        XCTAssertEqual(repeated.insertedExpenses, 0)
        XCTAssertEqual(repeated.insertedAccountEntries, 0)
        XCTAssertEqual(repeated.insertedOutboxOperations, 0)
        XCTAssertEqual(repeated.skippedProfiles, 1)
        XCTAssertEqual(repeated.skippedAccounts, 1)
        XCTAssertEqual(repeated.skippedExpenses, 2)
        XCTAssertEqual(repeated.skippedAccountEntries, 3)
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 3)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: fixture.accountID), 6_820)
    }

    func testLOCAL002F3ConflictingStableIDRejectsWholeArchiveWithoutPartialWrites() throws {
        let fixture = try makeArchiveFixture()
        let targetURL = temporaryPortabilityDatabaseURL()
        defer { removePortabilityDatabase(at: targetURL) }
        let database = try LocalDatabase(databaseURL: targetURL)
        let repository = try LocalExpenseRepository(database: database)
        _ = try repository.createProfile(id: fixture.profileID, createdAt: fixedDate)
        _ = try repository.createAccount(
            LocalAccountDraft(
                id: fixture.accountID,
                profileID: fixture.profileID,
                name: "本地钱包",
                kind: "wallet_balance",
                currency: "CNY",
                openingBalanceMinor: 10_000,
                createdAt: fixedDate
            )
        )
        _ = try repository.createExpense(
            expenseDraft(
                id: fixture.activeExpenseID,
                profileID: fixture.profileID,
                accountID: fixture.accountID,
                amountMinor: 999
            ),
            operationID: UUID()
        )
        let portability = LocalExpensePortability(database: database)

        XCTAssertThrowsError(
            try portability.importArchive(fixture.data, importedAt: importedDate)
        ) { error in
            XCTAssertEqual(
                error as? LocalExpenseArchiveError,
                .conflictingStableID(entity: "expense", id: fixture.activeExpenseID)
            )
        }
        XCTAssertEqual(try repository.expense(id: fixture.activeExpenseID)?.amountMinor, 999)
        XCTAssertNil(try repository.expenseTombstone(id: fixture.deletedExpenseID))
        XCTAssertEqual(try repository.expenseCount(), 1)
        XCTAssertEqual(try repository.accountEntryCount(), 1)
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 2)
    }

    func testLOCAL002F4RejectsUnknownVersionAndInvalidRelationshipsBeforeWriting() throws {
        let fixture = try makeArchiveFixture()
        let targetURL = temporaryPortabilityDatabaseURL()
        defer { removePortabilityDatabase(at: targetURL) }
        let database = try LocalDatabase(databaseURL: targetURL)
        let repository = try LocalExpenseRepository(database: database)
        let portability = LocalExpensePortability(database: database)

        XCTAssertThrowsError(
            try portability.importArchive(
                replacingJSONValue(in: fixture.data, key: "schemaVersion", value: 999),
                importedAt: importedDate
            )
        ) { error in
            XCTAssertEqual(error as? LocalExpenseArchiveError, .unsupportedSchemaVersion(999))
        }
        XCTAssertEqual(try repository.expenseCount(), 0)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture.data) as? [String: Any]
        )
        var expenses = try XCTUnwrap(object["expenses"] as? [[String: Any]])
        expenses[0]["accountID"] = UUID().uuidString
        object["expenses"] = expenses
        let invalidRelationships = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )

        XCTAssertThrowsError(
            try portability.importArchive(invalidRelationships, importedAt: importedDate)
        ) { error in
            XCTAssertEqual(error as? LocalExpenseArchiveError, .invalidRelationship)
        }
        XCTAssertEqual(try repository.expenseCount(), 0)
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 0)
    }

    func testLOCALDATA004COutboxConflictRollsBackEntireImport() throws {
        let fixture = try makeArchiveFixture()
        let targetURL = temporaryPortabilityDatabaseURL()
        defer { removePortabilityDatabase(at: targetURL) }
        let database = try LocalDatabase(databaseURL: targetURL)
        let repository = try LocalExpenseRepository(database: database)
        let duplicateOperationID = UUID()
        let portability = LocalExpensePortability(
            database: database,
            operationID: { duplicateOperationID }
        )

        XCTAssertThrowsError(
            try portability.importArchive(fixture.data, importedAt: importedDate)
        )
        XCTAssertEqual(try repository.expenseCount(), 0)
        XCTAssertNil(try repository.expenseTombstone(id: fixture.deletedExpenseID))
        XCTAssertEqual(try repository.accountEntryCount(), 0)
        XCTAssertEqual(try repository.pendingOutboxOperations().count, 0)
        XCTAssertThrowsError(try repository.accountBalanceMinor(accountID: fixture.accountID))
    }

    private func makeArchiveFixture() throws -> ArchiveFixture {
        let sourceURL = temporaryPortabilityDatabaseURL()
        defer { removePortabilityDatabase(at: sourceURL) }
        let database = try LocalDatabase(databaseURL: sourceURL)
        let repository = try LocalExpenseRepository(database: database)
        let portability = LocalExpensePortability(database: database)
        let profileID = UUID()
        let accountID = UUID()
        let activeExpenseID = UUID()
        let deletedExpenseID = UUID()
        let operationIDs = [UUID(), UUID(), UUID(), UUID()]

        _ = try repository.createProfile(id: profileID, createdAt: fixedDate)
        _ = try repository.createAccount(
            LocalAccountDraft(
                id: accountID,
                profileID: profileID,
                name: "本地钱包",
                kind: "wallet_balance",
                currency: "CNY",
                openingBalanceMinor: 10_000,
                createdAt: fixedDate
            )
        )
        _ = try repository.createExpense(
            expenseDraft(
                id: activeExpenseID,
                profileID: profileID,
                accountID: accountID,
                amountMinor: 2_680
            ),
            operationID: operationIDs[0]
        )
        _ = try repository.updateExpense(
            expenseUpdate(
                id: activeExpenseID,
                accountID: accountID,
                amountMinor: 3_180
            ),
            operationID: operationIDs[1]
        )
        _ = try repository.createExpense(
            expenseDraft(
                id: deletedExpenseID,
                profileID: profileID,
                accountID: accountID,
                amountMinor: 1_280
            ),
            operationID: operationIDs[2]
        )
        _ = try repository.deleteExpense(
            id: deletedExpenseID,
            expectedVersion: 1,
            deletedAt: editedDate,
            operationID: operationIDs[3]
        )

        return ArchiveFixture(
            data: try portability.exportArchive(profileID: profileID, exportedAt: exportedDate),
            profileID: profileID,
            accountID: accountID,
            activeExpenseID: activeExpenseID,
            deletedExpenseID: deletedExpenseID,
            sourceOperationIDs: operationIDs
        )
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
        accountID: UUID,
        amountMinor: Int64
    ) -> LocalExpenseUpdate {
        LocalExpenseUpdate(
            id: id,
            expectedVersion: 1,
            accountID: accountID,
            amountMinor: amountMinor,
            currency: "CNY",
            merchantName: "盒马鲜生",
            platform: "线下消费",
            category: "food",
            paymentMethod: "微信支付",
            transactionDate: "2026-08-23",
            transactionTime: "18:30:00",
            note: "晚餐",
            updatedAt: editedDate
        )
    }

    private func replacingJSONValue(in data: Data, key: String, value: Any) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private var fixedDate: Date { Date(timeIntervalSince1970: 1_777_000_000) }
    private var editedDate: Date { fixedDate.addingTimeInterval(3_600) }
    private var exportedDate: Date { fixedDate.addingTimeInterval(7_200) }
    private var importedDate: Date { fixedDate.addingTimeInterval(10_800) }
}

private struct ArchiveFixture {
    let data: Data
    let profileID: UUID
    let accountID: UUID
    let activeExpenseID: UUID
    let deletedExpenseID: UUID
    let sourceOperationIDs: [UUID]
}

private func temporaryPortabilityDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("snapcount-portability-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
}

private func removePortabilityDatabase(at databaseURL: URL) {
    for url in [
        databaseURL,
        URL(fileURLWithPath: databaseURL.path + "-shm"),
        URL(fileURLWithPath: databaseURL.path + "-wal")
    ] {
        try? FileManager.default.removeItem(at: url)
    }
}
