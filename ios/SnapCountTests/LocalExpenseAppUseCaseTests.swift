import XCTest
@testable import SnapCount

final class LocalExpenseAppUseCaseTests: XCTestCase {
    func testLocalAppBoundaryTypesExistBeforeImplementation() {
        XCTAssertNotNil(LocalProfileStoreProtocol.self)
        XCTAssertNotNil(LocalExpenseUseCaseProtocol.self)
    }

    func testLocalProfileIsResolvedWithoutCloudSession() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = LocalProfileStore(database: try LocalDatabase(databaseURL: databaseURL))
        let profile = try store.activeProfile()

        XCTAssertNil(profile.cloudUserID)
        XCTAssertFalse(profile.syncEnabled)
    }

    func testLocalProfilePersistsAcrossDatabaseReopen() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let first = try LocalProfileStore(
            database: LocalDatabase(databaseURL: databaseURL)
        ).activeProfile()
        let reopened = try LocalProfileStore(
            database: LocalDatabase(databaseURL: databaseURL)
        ).activeProfile()

        XCTAssertEqual(reopened, first)
    }

    func testAmountMapperUsesDecimalMinorUnits() throws {
        XCTAssertEqual(try LocalExpenseMapper.amountMinor("10.235"), 1_024)
        XCTAssertEqual(try LocalExpenseMapper.amountMinor("0.01"), 1)
        XCTAssertThrowsError(try LocalExpenseMapper.amountMinor("0"))
    }

    func testUseCaseCreatesAndProjectsExpenseWithoutNetworkDependency() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try store.activeProfile()
        let account = try repository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 10_000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let useCase = LocalExpenseUseCase(
            profileStore: store,
            repository: repository,
            operationIDProvider: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )

        let outcome = try await useCase.create(LocalExpenseCommand(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            accountID: account.id,
            amountText: "12.30",
            currency: "CNY",
            merchantName: "全家便利店",
            platform: "线下消费",
            category: "food",
            paymentMethod: "现金",
            transactionDate: "2026-08-23",
            transactionTime: "08:30",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))
        let month = try await useCase.month("2026-08")
        let groups = LocalExpenseReadModel.groups(from: month)

        XCTAssertEqual(outcome.profileID, profile.id)
        XCTAssertEqual(outcome.expense?.amountMinor, 1_230)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 8_770)
        XCTAssertEqual(groups.first?.records.first?.reference, "local-expense/22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(groups.first?.records.first?.value, "¥12.30")
    }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapCountTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("jiezi.sqlite")
}

private func removeDatabase(at url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
