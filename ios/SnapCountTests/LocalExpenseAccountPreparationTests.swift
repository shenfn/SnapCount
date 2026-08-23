import XCTest
@testable import SnapCount

final class LocalExpenseAccountPreparationTests: XCTestCase {
    func testWorkspaceReturnsActiveProfileAndLocalAccounts() async throws {
        let fixture = try makeFixture()
        defer { removeDatabase(at: fixture.url) }

        let workspace = try await fixture.useCase.prepareWorkspace()

        XCTAssertEqual(workspace.profile.id, fixture.profile.id)
        XCTAssertEqual(workspace.accounts, [])
    }

    func testCreateAccountAcceptsZeroAndDerivesOpeningBalanceLocally() async throws {
        let fixture = try makeFixture()
        defer { removeDatabase(at: fixture.url) }

        let account = try await fixture.useCase.createAccount(LocalAccountSetupCommand(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            name: "现金",
            kind: "cash",
            openingBalanceText: "0",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        XCTAssertEqual(account.openingBalanceMinor, 0)
        XCTAssertEqual(try fixture.repository.accountBalanceMinor(accountID: account.id), 0)
        let workspace = try await fixture.useCase.prepareWorkspace()
        XCTAssertEqual(workspace.accounts.map(\.id), [account.id])
    }

    func testCreateAccountRejectsInvalidAmountAndUnsupportedKind() async throws {
        let fixture = try makeFixture()
        defer { removeDatabase(at: fixture.url) }

        for value in ["-1", "NaN", "999999999999999999999999999999999999"] {
            await XCTAssertThrowsErrorAsync {
                try await fixture.useCase.createAccount(LocalAccountSetupCommand(
                    id: UUID(),
                    name: "测试账户",
                    kind: "cash",
                    openingBalanceText: value,
                    createdAt: Date()
                ))
            } assert: { XCTAssertEqual($0 as? LocalDataError, .invalidAmount) }
        }

        await XCTAssertThrowsErrorAsync {
            try await fixture.useCase.createAccount(LocalAccountSetupCommand(
                id: UUID(),
                name: "信用卡",
                kind: "credit_card",
                openingBalanceText: "0",
                createdAt: Date()
            ))
        } assert: { XCTAssertEqual($0 as? LocalDataError, .invalidAccountKind) }
    }

    func testLocalExpenseWithoutAccountFailsBeforeWritingExpenseOrEntry() async throws {
        let fixture = try makeFixture()
        defer { removeDatabase(at: fixture.url) }

        await XCTAssertThrowsErrorAsync {
            try await fixture.useCase.create(LocalExpenseCommand(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                accountID: UUID(),
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
        } assert: { XCTAssertEqual($0 as? LocalDataError, .accountRequired) }

        XCTAssertEqual(try fixture.repository.expenseCount(), 0)
        XCTAssertEqual(try fixture.repository.accountEntryCount(), 0)
    }

    func testCreatingAccountDoesNotPersistAUserDefault() async throws {
        let fixture = try makeFixture()
        defer { removeDatabase(at: fixture.url) }

        _ = try await fixture.useCase.createAccount(LocalAccountSetupCommand(
            id: UUID(),
            name: "钱包",
            kind: "wallet_balance",
            openingBalanceText: "12.34",
            createdAt: Date()
        ))

        let workspace = try await fixture.useCase.prepareWorkspace()
        XCTAssertNil(workspace.defaultAccountID)
    }

    private func makeFixture() throws -> Fixture {
        let url = temporaryDatabaseURL()
        let database = try LocalDatabase(databaseURL: url)
        let store = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try store.activeProfile()
        return Fixture(
            url: url,
            profile: profile,
            repository: repository,
            useCase: LocalExpenseUseCase(profileStore: store, repository: repository)
        )
    }
}

private struct Fixture {
    let url: URL
    let profile: LocalProfile
    let repository: LocalExpenseRepository
    let useCase: LocalExpenseUseCase
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @escaping () async throws -> T,
        assert: (Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail("expected error")
        } catch {
            assert(error)
        }
    }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapCountUIBTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("jiezi.sqlite")
}

private func removeDatabase(at url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
