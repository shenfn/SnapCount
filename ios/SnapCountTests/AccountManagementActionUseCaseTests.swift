import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class AccountManagementActionUseCaseTests: XCTestCase {
    func testA4IOS004ARejectsInvalidCommandsBeforeTransport() async {
        let repository = AccountManagementRepositoryStub()
        let harness = makeHarness(repository: repository)

        let invalidSave = await harness.useCase.perform(.save(
            AccountManagementSaveCommand(
                accountId: nil,
                name: "   ",
                type: .walletBalance,
                institution: "",
                last4: "12",
                initialBalance: 0,
                billDay: nil,
                paymentDueDay: nil,
                autoDebitAccountId: nil,
                autoConfirmRepayment: false,
                isDefaultExpense: false,
                isDefaultIncome: false
            )
        ))
        let invalidArchive = await harness.useCase.perform(
            .setArchived(accountId: "   ", archived: true)
        )

        XCTAssertEqual(invalidSave.transaction, .rejected(.invalidInput))
        XCTAssertEqual(invalidArchive.transaction, .rejected(.invalidInput))
        XCTAssertEqual(repository.saveCallCount, 0)
        XCTAssertEqual(repository.archiveCallCount, 0)
        XCTAssertEqual(harness.sessionCallCount(), 0)
    }

    func testA4IOS004BUsesNarrowAccountManagementRepository() async {
        let repository = AccountManagementRepositoryStub()
        let harness = makeHarness(repository: repository)

        let result = await harness.useCase.perform(.setArchived(
            accountId: "account-1",
            archived: true
        ))

        XCTAssertEqual(result.transaction.acceptedAccount?.id, "account-1")
        XCTAssertEqual(repository.archiveCallCount, 1)
        XCTAssertEqual(repository.lastArchived, true)
        XCTAssertEqual(repository.saveCallCount, 0)
    }

    func testA4IOS004CProjectsCanonicalAccountBeforeRefresh() async {
        let repository = AccountManagementRepositoryStub()
        var projected: [NativeAccount] = []
        let harness = makeHarness(
            repository: repository,
            applyAccepted: { projected.append($0) }
        )

        let result = await harness.useCase.perform(.setArchived(
            accountId: "account-1",
            archived: true
        ))

        XCTAssertEqual(result.transaction.acceptedAccount?.isArchived, true)
        XCTAssertEqual(projected.map(\.id), ["account-1"])
        XCTAssertEqual(harness.refreshCallCount(), 1)
    }

    func testA4IOS004DReusesSameCommandAndDoesNotDuplicateTransport() async {
        let gate = AccountManagementActionGate()
        let repository = AccountManagementRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let command = AccountManagementActionCommand.setArchived(
            accountId: "account-1",
            archived: true
        )

        async let first = harness.useCase.perform(command)
        await gate.waitUntilEntered()
        async let duplicate = harness.useCase.perform(command)

        XCTAssertEqual(repository.archiveCallCount, 1)
        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction.acceptedAccount?.id, "account-1")
        XCTAssertEqual(duplicateResult.transaction.acceptedAccount?.id, "account-1")
        XCTAssertEqual(repository.archiveCallCount, 1)
    }

    func testA4IOS004EConflictsWhenSaveAndArchiveOverlap() async {
        let gate = AccountManagementActionGate()
        let repository = AccountManagementRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let save = AccountManagementActionCommand.save(
            AccountManagementSaveCommand(
                accountId: "account-1",
                name: "微信钱包",
                type: .walletBalance,
                institution: "微信",
                last4: "",
                initialBalance: 0,
                billDay: nil,
                paymentDueDay: nil,
                autoDebitAccountId: nil,
                autoConfirmRepayment: false,
                isDefaultExpense: false,
                isDefaultIncome: false
            )
        )

        async let pending = harness.useCase.perform(save)
        await gate.waitUntilEntered()
        let conflict = await harness.useCase.perform(.setArchived(
            accountId: "account-1",
            archived: true
        ))

        XCTAssertEqual(conflict.transaction, .conflict(.accountCommandConflict))
        XCTAssertEqual(repository.saveCallCount, 1)
        XCTAssertEqual(repository.archiveCallCount, 0)
        await gate.release()
        _ = await pending
    }

    func testA4IOS004FRefreshFailureDoesNotRewriteAcceptedTransaction() async {
        let repository = AccountManagementRepositoryStub()
        let harness = makeHarness(
            repository: repository,
            refresh: { throw AccountManagementActionTestError.refreshFailed }
        )

        let result = await harness.useCase.perform(.setArchived(
            accountId: "account-1",
            archived: true
        ))

        XCTAssertEqual(result.transaction.acceptedAccount?.id, "account-1")
        XCTAssertEqual(result.refresh, .failed("refresh_failed"))
        XCTAssertEqual(repository.archiveCallCount, 1)
        XCTAssertEqual(harness.refreshCallCount(), 1)
    }

    func testA4IOS004GResetMakesOldRequestStaleWithoutProjectionOrRefresh() async {
        let gate = AccountManagementActionGate()
        let repository = AccountManagementRepositoryStub(gate: gate)
        var context = AccountManagementUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        var projected = 0
        let harness = makeHarness(
            repository: repository,
            contextProvider: { context },
            applyAccepted: { _ in projected += 1 }
        )

        async let pending = harness.useCase.perform(.setArchived(
            accountId: "account-1",
            archived: true
        ))
        await gate.waitUntilEntered()
        context = AccountManagementUserContext(userId: "user-2", generation: 2, isSignedIn: true)
        harness.useCase.reset()
        await gate.release()

        let result = await pending
        XCTAssertEqual(result.transaction, .stale)
        XCTAssertEqual(projected, 0)
        XCTAssertEqual(harness.refreshCallCount(), 0)
    }

    func testA4IOS004HMapsCanonicalProtocolAndDatabaseFailures() async {
        let repository = AccountManagementRepositoryStub(error: .accountTypeTransitionBlocked)
        let harness = makeHarness(repository: repository)

        let result = await harness.useCase.perform(.setArchived(
            accountId: "account-1",
            archived: true
        ))

        XCTAssertEqual(result.transaction.failureReason, "account_type_transition_blocked")
        XCTAssertEqual(result.refresh, .notStarted)
        XCTAssertEqual(harness.refreshCallCount(), 0)
    }

    private func makeHarness(
        repository: AccountManagementRepositoryStub,
        contextProvider: (() -> AccountManagementUserContext)? = nil,
        applyAccepted: @escaping (NativeAccount) -> Void = { _ in },
        refresh: @escaping () async throws -> Void = {}
    ) -> AccountManagementActionHarness {
        var sessionCalls = 0
        var refreshCalls = 0
        let defaultContext = AccountManagementUserContext(
            userId: "user-1",
            generation: 1,
            isSignedIn: true
        )
        let useCase = AccountManagementActionUseCase(
            repository: repository,
            sessionProvider: { _ in
                sessionCalls += 1
                return Self.session
            },
            contextProvider: { contextProvider?() ?? defaultContext },
            applyAccepted: applyAccepted,
            refresh: { _ in
                refreshCalls += 1
                try await refresh()
            }
        )
        return AccountManagementActionHarness(
            useCase: useCase,
            sessionCallCount: { sessionCalls },
            refreshCallCount: { refreshCalls }
        )
    }

    private static let session = SupabaseAuthSession(
        accessToken: "test-token",
        refreshToken: nil,
        expiresIn: nil,
        expiresAt: nil,
        tokenType: "bearer",
        user: SupabaseUser(id: "user-1", email: "test@example.com")
    )
}

private struct AccountManagementActionHarness {
    let useCase: AccountManagementActionUseCase
    let sessionCallCount: () -> Int
    let refreshCallCount: () -> Int
}

private final class AccountManagementRepositoryStub: AccountManagementRepositoryProtocol {
    private let gate: AccountManagementActionGate?
    private let failure: AccountManagementRepositoryError?
    private(set) var saveCallCount = 0
    private(set) var archiveCallCount = 0
    private(set) var lastArchived: Bool?

    init(
        gate: AccountManagementActionGate? = nil,
        error: AccountManagementRepositoryError? = nil
    ) {
        self.gate = gate
        self.failure = error
    }

    func saveAccount(
        _ command: AccountManagementSaveCommand,
        accessToken: String
    ) async throws -> NativeAccount {
        saveCallCount += 1
        if let failure { throw failure }
        if let gate { await gate.enterAndWait() }
        return account()
    }

    func setAccountArchived(
        accountId: String,
        archived: Bool,
        accessToken: String
    ) async throws -> NativeAccount {
        archiveCallCount += 1
        lastArchived = archived
        if let failure { throw failure }
        if let gate { await gate.enterAndWait() }
        return account(id: accountId, archived: archived)
    }

    private func account(id: String = "account-1", archived: Bool = false) -> NativeAccount {
        NativeAccount(
            id: id,
            name: "微信钱包",
            type: .walletBalance,
            institution: "微信",
            last4: "",
            currency: "CNY",
            initialBalance: 320,
            currentBalance: 320,
            snapshotBalance: 320,
            snapshotAt: "2026-08-19T02:00:00Z",
            sourceRecordTable: "data_records",
            sourceRecordId: "record-1",
            billDay: nil,
            paymentDueDay: nil,
            autoDebitAccountId: nil,
            autoConfirmRepayment: false,
            gracePeriodDays: 0,
            lastReconciledAt: nil,
            isDefaultExpense: false,
            isDefaultIncome: false,
            isArchived: archived,
            sortOrder: 0
        )
    }
}

private actor AccountManagementActionGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private enum AccountManagementRepositoryError: LocalizedError {
    case accountTypeTransitionBlocked

    var errorDescription: String? {
        switch self {
        case .accountTypeTransitionBlocked: return "account_type_transition_blocked"
        }
    }
}

private enum AccountManagementActionTestError: LocalizedError {
    case refreshFailed

    var errorDescription: String? { "refresh_failed" }
}
