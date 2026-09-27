import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class LocalWalletSnapshotTests: XCTestCase {
    func testLOCALP1LF033CreatesAssetSnapshotWithoutLedgerOrOutboxAndExposesFact() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let expenseRepository = try LocalExpenseRepository(database: database)
        let profile = try expenseRepository.createProfile(id: UUID(), createdAt: fixedDate)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: fixedDate
        ))
        let outboxBefore = try expenseRepository.pendingOutboxOperations().count
        let walletUseCase = LocalWalletSnapshotUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalWalletSnapshotRepository(database: database)
        )

        let created = try await walletUseCase.create(LocalWalletSnapshotCommand(
            id: UUID(),
            accountID: account.id,
            snapshotKind: "asset",
            amountText: "123.45",
            minimumPaymentText: nil,
            currency: "CNY",
            accountName: "现金",
            accountType: "cash",
            snapshotDate: "2026-09-27",
            snapshotTime: "09:30",
            dueDate: nil,
            billDay: nil,
            note: "钱包余额",
            payload: [:],
            createdAt: fixedDate
        ))

        XCTAssertEqual(created.snapshot.amountMinor, 12_345)
        XCTAssertEqual(created.snapshot.accountID, account.id)
        XCTAssertEqual(try expenseRepository.accountEntries(accountID: account.id), [])
        XCTAssertEqual(try expenseRepository.pendingOutboxOperations().count, outboxBefore)

        let month = try LocalFactReader(database: database).month(
            profileID: profile.id,
            monthKey: "2026-09"
        )
        let fact = try XCTUnwrap(month.facts.first { $0.domainKey == "wallet" })
        XCTAssertEqual(fact.reference, "wallet/\(created.snapshot.id.uuidString)")
        XCTAssertTrue(fact.payloadJSON.contains("snapshot_kind"))

        let row = try XCTUnwrap(
            LocalFactReadModel.groups(from: month, including: [.record])
                .flatMap(\.records)
                .first { $0.reference == fact.reference }
        )
        XCTAssertEqual(row.kind, .wallet)
        XCTAssertEqual(row.value, "¥123.45")
        let detail = try XCTUnwrap(LocalFactReadModel.details(from: month)[fact.reference])
        XCTAssertEqual(detail.domainKey, "wallet")
        XCTAssertEqual(detail.amount ?? 0, 123.45, accuracy: 0.001)

        let state = AppState(
            localWalletSnapshotUseCase: walletUseCase,
            localFactReader: try LocalFactReader(database: database),
            localFactPortability: LocalFactPortability(database: database)
        )
        state.isSignedIn = false
        await state.loadRecordMonth("2026-09", force: true)
        XCTAssertEqual(state.dashboard.monthExpense, 0, accuracy: 0.001)
        XCTAssertEqual(state.dashboard.monthIncome, 0, accuracy: 0.001)
        XCTAssertEqual(
            state.recordGroups(monthKey: "2026-09").flatMap(\.records).filter { $0.kind == .wallet }.count,
            1
        )

        var request = NativeDataExportRequest()
        request.range = .all
        request.format = .json
        request.includeFullPayload = true
        let archiveData = try LocalFactPortability(database: database).exportArchive(
            request: request,
            exportedAt: fixedDate
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LocalFactArchive.self, from: archiveData)
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(archive.facts.map(\.reference), [fact.reference])
        XCTAssertEqual(archive.facts[0].domainKey, "wallet")
    }

    func testLOCALP1LF033RejectsSubMinorPrecisionAndMismatchedAccountKind() async throws {
        XCTAssertThrowsError(try LocalWalletSnapshotMoney.amountMinor("1.005", currency: "CNY"))
        XCTAssertEqual(try LocalWalletSnapshotMoney.amountMinor("0.00", currency: "CNY", allowZero: true), 0)

        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let expenseRepository = try LocalExpenseRepository(database: database)
        let profile = try expenseRepository.createProfile(id: UUID(), createdAt: fixedDate)
        let cashAccount = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: fixedDate
        ))
        let walletUseCase = LocalWalletSnapshotUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalWalletSnapshotRepository(database: database)
        )

        do {
            _ = try await walletUseCase.create(LocalWalletSnapshotCommand(
                id: UUID(),
                accountID: cashAccount.id,
                snapshotKind: "liability",
                amountText: "10.00",
                minimumPaymentText: "1.00",
                currency: "CNY",
                accountName: "花呗",
                accountType: "credit_line",
                snapshotDate: "2026-09-27",
                snapshotTime: nil,
                dueDate: "2026-10-01",
                billDay: 1,
                note: nil,
                payload: [:],
                createdAt: fixedDate
            ))
            XCTFail("负债快照不应绑定资产账户")
        } catch let error as LocalDataError {
            XCTAssertEqual(error, .invalidAccountKind)
        }
    }

    func testLOCALP1LF033UpdateAndDeleteUseVersionAndHideTombstoneFromFacts() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let walletUseCase = LocalWalletSnapshotUseCase(
            profileStore: profileStore,
            repository: try LocalWalletSnapshotRepository(database: database)
        )
        let created = try await walletUseCase.create(LocalWalletSnapshotCommand(
            id: UUID(),
            accountID: nil,
            snapshotKind: "liability",
            amountText: "20.00",
            minimumPaymentText: "2.00",
            currency: "CNY",
            accountName: "花呗",
            accountType: "credit_line",
            snapshotDate: "2026-09-27",
            snapshotTime: nil,
            dueDate: "2026-10-01",
            billDay: 1,
            note: nil,
            payload: [:],
            createdAt: fixedDate
        ))

        let updated = try await walletUseCase.update(LocalWalletSnapshotUpdateCommand(
            id: created.snapshot.id,
            expectedVersion: created.snapshot.localVersion,
            accountID: nil,
            snapshotKind: "liability",
            amountText: "21.01",
            minimumPaymentText: "2.10",
            currency: "CNY",
            accountName: "花呗",
            accountType: "credit_line",
            snapshotDate: "2026-09-28",
            snapshotTime: "10:00",
            dueDate: "2026-10-01",
            billDay: 1,
            note: "更新",
            payload: [:],
            updatedAt: fixedDate.addingTimeInterval(60)
        ))
        XCTAssertEqual(updated.snapshot.amountMinor, 2_101)
        XCTAssertEqual(updated.snapshot.localVersion, 2)
        do {
            _ = try await walletUseCase.update(LocalWalletSnapshotUpdateCommand(
                id: updated.snapshot.id,
                expectedVersion: 1,
                accountID: nil,
                snapshotKind: "liability",
                amountText: "22.00",
                minimumPaymentText: "2.20",
                currency: "CNY",
                accountName: "花呗",
                accountType: "credit_line",
                snapshotDate: "2026-09-28",
                snapshotTime: nil,
                dueDate: "2026-10-01",
                billDay: 1,
                note: nil,
                payload: [:],
                updatedAt: fixedDate.addingTimeInterval(90)
            ))
            XCTFail("过期版本不应覆盖 Wallet 快照")
        } catch let error as LocalDataError {
            XCTAssertEqual(error, .versionConflict(expected: 1, actual: 2))
        }

        let deleted = try await walletUseCase.delete(LocalWalletSnapshotDeleteCommand(
            id: updated.snapshot.id,
            expectedVersion: updated.snapshot.localVersion,
            deletedAt: fixedDate.addingTimeInterval(120)
        ))
        XCTAssertNotNil(deleted.tombstone.deletedAt)
        XCTAssertNil(try await walletUseCase.snapshot(id: updated.snapshot.id))

        let profile = try profileStore.activeProfile()
        let month = try LocalFactReader(database: database).month(
            profileID: profile.id,
            monthKey: "2026-09"
        )
        XCTAssertTrue(month.facts.filter { $0.domainKey == "wallet" }.isEmpty)
    }

    private var fixedDate: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-wallet-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jiezi.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: url)
    }
}
