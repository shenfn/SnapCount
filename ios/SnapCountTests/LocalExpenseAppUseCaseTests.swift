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

        XCTAssertEqual(reopened.id, first.id)
        XCTAssertEqual(reopened.cloudUserID, first.cloudUserID)
        XCTAssertEqual(reopened.syncEnabled, first.syncEnabled)
        XCTAssertEqual(
            reopened.createdAt.timeIntervalSince1970,
            first.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
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

    @MainActor
    func testAppStateLoadsSignedOutMonthFromLocalUseCaseWithoutSessionLookup() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let expense = localExpense(profileID: profileID)
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(
                id: profileID,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                cloudUserID: nil,
                syncEnabled: false
            ),
            month: LocalExpenseMonth(profileID: profileID, expenses: [expense])
        )
        var sessionLookupCount = 0
        let state = AppState(
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in
                sessionLookupCount += 1
                throw SupabaseRemoteError.missingSession
            }
        )

        await state.loadRecordMonth("2026-07", force: true)

        XCTAssertEqual(localUseCase.monthKeys, ["2026-07"])
        XCTAssertEqual(sessionLookupCount, 0)
        XCTAssertEqual(state.recordGroups(monthKey: "2026-07").first?.records.first?.title, "全家便利店")
        XCTAssertNil(state.recordMonthMessages["2026-07"])
    }

    @MainActor
    func testAppStateKeepsSignedInMonthOnRemoteRepository() async throws {
        let localUseCase = LocalShellExpenseUseCaseStub.empty
        let remoteGroup = NativeDayRecordGroup(
            dateKey: "2026-07-20",
            records: [NativeDayRecord(
                id: "remote-1",
                reference: "expense/remote-1",
                dateKey: "2026-07-20",
                kind: .expense,
                domainKey: nil,
                title: "云端记录",
                subtitle: "food",
                value: "¥8.00",
                timeLabel: "08:00",
                systemImage: "creditcard"
            )]
        )
        let repository = LocalShellRecordRepositorySpy(
            monthSnapshot: NativeRecordMonthSnapshot(groups: [remoteGroup], details: [:])
        )
        let state = AppState(
            recordRepository: repository,
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in LocalShellRecordRepositorySpy.session }
        )
        state.isSignedIn = true
        state.currentUserId = LocalShellRecordRepositorySpy.session.user.id

        await state.loadRecordMonth("2026-07", force: true)

        XCTAssertEqual(repository.fetchMonthKeys, ["2026-07"])
        XCTAssertTrue(localUseCase.monthKeys.isEmpty)
        XCTAssertEqual(state.recordGroups(monthKey: "2026-07").first?.records.first?.title, "云端记录")
    }

    private func localExpense(profileID: UUID) -> LocalExpense {
        LocalExpense(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            profileID: profileID,
            accountID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            amountMinor: 1_230,
            currency: "CNY",
            merchantName: "全家便利店",
            platform: "线下消费",
            category: "food",
            paymentMethod: "现金",
            transactionDate: "2026-07-20",
            transactionTime: "08:30",
            note: nil,
            localVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }
}

private final class LocalShellExpenseUseCaseStub: LocalExpenseUseCaseProtocol {
    static var empty: LocalShellExpenseUseCaseStub {
        let profile = LocalProfile(id: UUID(), createdAt: Date(), cloudUserID: nil, syncEnabled: false)
        return LocalShellExpenseUseCaseStub(
            profile: profile,
            month: LocalExpenseMonth(profileID: profile.id, expenses: [])
        )
    }

    let profile: LocalProfile
    let monthResult: LocalExpenseMonth
    private(set) var monthKeys: [String] = []

    init(profile: LocalProfile, month: LocalExpenseMonth) {
        self.profile = profile
        self.monthResult = month
    }

    func prepareProfile() async throws -> LocalProfile { profile }
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }

    func month(_ monthKey: String) async throws -> LocalExpenseMonth {
        monthKeys.append(monthKey)
        return monthResult
    }
}

private final class LocalShellRecordRepositorySpy: RecordRepositoryProtocol {
    static let session = SupabaseAuthSession(
        accessToken: "test-token",
        refreshToken: nil,
        expiresIn: nil,
        expiresAt: nil,
        tokenType: "bearer",
        user: SupabaseUser(id: "user-1", email: "test@example.com")
    )

    let monthSnapshot: NativeRecordMonthSnapshot
    private(set) var fetchMonthKeys: [String] = []

    init(monthSnapshot: NativeRecordMonthSnapshot) {
        self.monthSnapshot = monthSnapshot
    }

    func fetchMonth(monthKey: String, accessToken: String) async throws -> NativeRecordMonthSnapshot {
        fetchMonthKeys.append(monthKey)
        return monthSnapshot
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail { detail }
    func getRecordExpressionPlan(reference: String, accessToken: String) async throws -> NativeRecordExpressionPlanLookup {
        .unavailable(reason: "unused")
    }

    func acknowledgeRecordExpressionPlan(
        recordId: String,
        planToken: String,
        candidateId: String,
        accessToken: String
    ) async throws -> NativeAIFeedback {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func create(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?,
        userId: String,
        accessToken: String
    ) async throws -> String {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func delete(reference: String, accessToken: String) async throws {}

    func submitFeedback(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?,
        accessToken: String
    ) async throws {}
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapCountTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("jiezi.sqlite")
}

private func removeDatabase(at url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
