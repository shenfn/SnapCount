import XCTest
@testable import SnapCount

final class LocalSyncAppStateTests: XCTestCase {
    @MainActor
    func testDREMOTE010ConfirmBindingStartsInitialSync() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let session = Self.session
        let binding = LocalSyncBindingRepositorySpy(
            profileID: profileID,
            state: Self.syncState(profileID: profileID, status: .ready)
        )
        let runner = LocalSyncRunnerSpy(result: Self.syncResult(profileID: profileID))
        let state = AppState(
            localExpenseUseCase: LocalSyncExpenseUseCaseStub(profileID: profileID),
            localBindingRepository: binding,
            localSyncRunner: runner,
            sessionProvider: { _ in session }
        )
        state.isSignedIn = true
        state.currentUserId = session.user.id
        state.localBindingPreview = LocalBindingPreview(
            workspaceID: profileID,
            candidateCloudUserID: session.user.id,
            cloudEmail: session.user.email,
            currentBinding: .unbound,
            localExpenseCount: 0,
            localAccountCount: 0,
            pendingOutboxCount: 0,
            remoteScope: ["expense", "accounts"],
            options: [.mergeAndEnable]
        )

        state.confirmLocalBinding()

        for _ in 0..<20 where runner.callCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(binding.confirmedCloudUserID, session.user.id)
        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(runner.lastProfileID, profileID)
    }

    @MainActor
    func testDREMOTE011SuccessfulSyncPublishesStateAndRefreshesLocalReadModel() async {
        let profileID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let useCase = LocalSyncExpenseUseCaseStub(profileID: profileID)
        let binding = LocalSyncBindingRepositorySpy(
            profileID: profileID,
            state: Self.syncState(profileID: profileID, status: .ready)
        )
        let runner = LocalSyncRunnerSpy(result: Self.syncResult(profileID: profileID, importedRecordCount: 2))
        let state = AppState(
            localExpenseUseCase: useCase,
            localBindingRepository: binding,
            localSyncRunner: runner,
            sessionProvider: { _ in Self.session }
        )
        state.isSignedIn = true
        state.currentUserId = Self.session.user.id

        await state.synchronizeLocalData()

        XCTAssertEqual(state.localSyncState?.status, .synced)
        XCTAssertEqual(state.localSyncState?.pullCursor, "cursor-1")
        XCTAssertTrue(state.localSyncMessage?.contains("2") == true)
        XCTAssertEqual(state.localSyncDiagnostic?.phase, .completed)
        XCTAssertEqual(state.localSyncDiagnostic?.uploadedOperationCount, 0)
        XCTAssertEqual(state.localSyncDiagnostic?.importedRecordCount, 2)
        XCTAssertFalse(state.isSynchronizingLocalData)
        XCTAssertTrue(useCase.workspaceCallCount > 0)
        XCTAssertTrue(useCase.monthKeys.contains(Self.currentMonthKey))
    }

    @MainActor
    func testDREMOTE012FailedSyncKeepsLocalReadModelAndShowsRetryableError() async {
        let profileID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let useCase = LocalSyncExpenseUseCaseStub(profileID: profileID)
        let binding = LocalSyncBindingRepositorySpy(
            profileID: profileID,
            state: Self.syncState(profileID: profileID, status: .failed)
        )
        let runner = LocalSyncRunnerSpy(error: TestLocalSyncError.offline)
        let state = AppState(
            localExpenseUseCase: useCase,
            localBindingRepository: binding,
            localSyncRunner: runner,
            sessionProvider: { _ in Self.session }
        )
        state.isSignedIn = true
        state.currentUserId = Self.session.user.id

        await state.synchronizeLocalData()

        XCTAssertEqual(runner.callCount, 1)
        XCTAssertEqual(state.localSyncState?.status, .failed)
        XCTAssertTrue(state.localSyncMessage?.contains("同步失败") == true)
        XCTAssertEqual(state.localSyncDiagnostic?.phase, .failed)
        XCTAssertEqual(state.localSyncDiagnostic?.failure, .transport)
        XCTAssertFalse(state.isSynchronizingLocalData)
        XCTAssertEqual(useCase.monthKeys.count, 0)
    }

    @MainActor
    func testDREMOTE013ManualSyncIsIdempotentlyGuardedWhileRunning() async {
        let profileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let binding = LocalSyncBindingRepositorySpy(
            profileID: profileID,
            state: Self.syncState(profileID: profileID, status: .ready)
        )
        let runner = LocalSyncRunnerSpy(result: Self.syncResult(profileID: profileID))
        let state = AppState(
            localExpenseUseCase: LocalSyncExpenseUseCaseStub(profileID: profileID),
            localBindingRepository: binding,
            localSyncRunner: runner,
            sessionProvider: { _ in Self.session }
        )
        state.isSignedIn = true
        state.currentUserId = Self.session.user.id
        state.isSynchronizingLocalData = true

        await state.synchronizeLocalData()

        XCTAssertEqual(runner.callCount, 0)
    }

    private static let session = SupabaseAuthSession(
        accessToken: "test-token",
        refreshToken: nil,
        expiresIn: nil,
        expiresAt: nil,
        tokenType: "bearer",
        user: SupabaseUser(id: "sync-user", email: "sync@example.com")
    )

    private static let currentMonthKey = localSyncCurrentMonthKey()

    private static func syncState(profileID: UUID, status: LocalSyncStatus, pullCursor: String? = nil) -> LocalSyncState {
        LocalSyncState(
            workspaceID: profileID,
            binding: .bound(Self.session.user.id),
            status: status,
            conflictState: .none,
            syncGeneration: 1,
            pullCursor: pullCursor,
            lastSuccessfulSyncAt: nil,
            activeAttemptID: nil,
            pendingMutationCount: 0
        )
    }

    private static func syncResult(profileID: UUID, importedRecordCount: Int = 0) -> LocalSyncRunResult {
        LocalSyncRunResult(
            state: syncState(profileID: profileID, status: .synced, pullCursor: "cursor-1"),
            uploadedOperationCount: 0,
            importedRecordCount: importedRecordCount
        )
    }
}

private enum TestLocalSyncError: Error { case offline }

private final class LocalSyncRunnerSpy: LocalSyncRunner {
    let result: LocalSyncRunResult?
    let error: Error?
    private(set) var callCount = 0
    private(set) var lastProfileID: UUID?

    init(result: LocalSyncRunResult) { self.result = result; error = nil }
    init(error: Error) { result = nil; self.error = error }

    func synchronize(profileID: UUID, cloudUserID: String) async throws -> LocalSyncRunResult {
        callCount += 1
        lastProfileID = profileID
        if let error { throw error }
        return result!
    }
}

private final class LocalSyncBindingRepositorySpy: LocalBindingRepository {
    let profile: LocalProfile
    var state: LocalSyncState
    private(set) var confirmedCloudUserID: String?

    init(profileID: UUID, state: LocalSyncState) {
        profile = LocalProfile(id: profileID, createdAt: Date(), cloudUserID: state.binding.cloudUserID, syncEnabled: true)
        self.state = state
    }

    func activeProfile() throws -> LocalProfile { profile }
    func workspaceSummary(profileID: UUID) throws -> LocalWorkspaceSummary {
        LocalWorkspaceSummary(workspaceID: profileID, expenseCount: 0, accountCount: 0, pendingOutboxCount: 0)
    }
    func syncState(profileID: UUID) throws -> LocalSyncState { state }
    func confirmBinding(profileID: UUID, cloudUserID: String) throws -> LocalSyncState {
        confirmedCloudUserID = cloudUserID
        state = LocalSyncState(
            workspaceID: state.workspaceID,
            binding: .bound(cloudUserID),
            status: .ready,
            conflictState: .none,
            syncGeneration: state.syncGeneration + 1,
            pullCursor: state.pullCursor,
            lastSuccessfulSyncAt: state.lastSuccessfulSyncAt,
            activeAttemptID: nil,
            pendingMutationCount: state.pendingMutationCount
        )
        return state
    }
    func disableSync(profileID: UUID) throws -> LocalSyncState { state }
}

private final class LocalSyncExpenseUseCaseStub: LocalExpenseUseCaseProtocol {
    let profile: LocalProfile
    let monthResult: LocalExpenseMonth
    private(set) var workspaceCallCount = 0
    private(set) var monthKeys: [String] = []

    init(profileID: UUID) {
        profile = LocalProfile(id: profileID, createdAt: Date(), cloudUserID: nil, syncEnabled: false)
        monthResult = LocalExpenseMonth(
            profileID: profileID,
            expenses: [LocalExpense(
                id: UUID(),
                profileID: profileID,
                accountID: UUID(),
                amountMinor: 100,
                currency: "CNY",
                merchantName: "测试记录",
                platform: "manual",
                category: "food",
                paymentMethod: "现金",
                transactionDate: localSyncCurrentMonthKey() + "-01",
                transactionTime: nil,
                note: nil,
                localVersion: 1,
                createdAt: Date(),
                updatedAt: Date()
            )]
        )
    }

    func prepareProfile() async throws -> LocalProfile { profile }
    func prepareWorkspace() async throws -> LocalExpenseWorkspace {
        workspaceCallCount += 1
        return LocalExpenseWorkspace(profile: profile, accounts: [], defaultAccountID: nil)
    }
    func month(_ monthKey: String) async throws -> LocalExpenseMonth {
        monthKeys.append(monthKey)
        return monthResult
    }
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome { throw LocalDataError.invalidRecord }
}

private extension LocalWorkspaceBinding {
    var cloudUserID: String? {
        if case .bound(let userID) = self { return userID }
        return nil
    }
}

private func localSyncCurrentMonthKey() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM"
    return formatter.string(from: Date())
}
