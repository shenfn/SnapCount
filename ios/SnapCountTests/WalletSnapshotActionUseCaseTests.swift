import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class WalletSnapshotActionUseCaseTests: XCTestCase {
    func testA4IOS002ARejectsInvalidInputBeforeTransport() async {
        let repository = WalletSnapshotActionRepositoryStub()
        let harness = makeHarness(repository: repository, isSignedIn: false)

        let unauthenticated = await harness.useCase.perform(
            .create(recordId: "record-1"),
            snapshot: walletSnapshot()
        )
        let emptyRecord = await harness.useCase.perform(
            .create(recordId: "   "),
            snapshot: walletSnapshot(id: "   ")
        )
        let createWithAccount = await harness.useCase.perform(
            .init(operation: .create, recordId: "record-1", accountId: "account-1"),
            snapshot: walletSnapshot()
        )
        let linkWithoutAccount = await harness.useCase.perform(
            .init(operation: .link, recordId: "record-1", accountId: nil),
            snapshot: walletSnapshot()
        )

        XCTAssertEqual(unauthenticated.transaction, .rejected(.unauthenticated))
        XCTAssertEqual(emptyRecord.transaction, .rejected(.invalidInput))
        XCTAssertEqual(createWithAccount.transaction, .rejected(.invalidInput))
        XCTAssertEqual(linkWithoutAccount.transaction, .rejected(.invalidInput))
        XCTAssertEqual(repository.callCount, 0)
        XCTAssertEqual(harness.sessionCallCount(), 0)
    }

    func testA4IOS002BReusesSameTaskAndRejectsDifferentSignature() async {
        let gate = WalletSnapshotActionGate()
        let repository = WalletSnapshotActionRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let snapshot = walletSnapshot()

        async let first = harness.useCase.perform(.create(recordId: snapshot.id), snapshot: snapshot)
        await gate.waitUntilEntered()
        async let duplicate = harness.useCase.perform(.create(recordId: snapshot.id), snapshot: snapshot)
        let conflict = await harness.useCase.perform(
            .link(recordId: snapshot.id, accountId: "account-2"),
            snapshot: snapshot,
            account: account(id: "account-2")
        )

        XCTAssertEqual(conflict.transaction, .conflict(.walletSnapshotConflict))
        XCTAssertEqual(repository.callCount, 1)

        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction, .accepted(.created))
        XCTAssertEqual(duplicateResult.transaction, .accepted(.created))
        XCTAssertEqual(repository.callCount, 1)
    }

    func testA4IOS002CPreservesCanonicalAcceptedOutcomes() async {
        for outcome in NativeWalletSnapshotOutcome.allCasesForTests {
            let repository = WalletSnapshotActionRepositoryStub(outcome: outcome)
            let harness = makeHarness(repository: repository)
            let result = await harness.useCase.perform(
                .create(recordId: "record-1"),
                snapshot: walletSnapshot()
            )

            XCTAssertEqual(result.transaction, .accepted(outcome))
            XCTAssertEqual(result.refresh, .succeeded)
        }
    }

    func testA4IOS002DRefreshFailureDoesNotRewriteAcceptedTransaction() async {
        let repository = WalletSnapshotActionRepositoryStub(outcome: .linked)
        let harness = makeHarness(
            repository: repository,
            refresh: { throw WalletSnapshotActionTestError.refreshFailed }
        )

        let result = await harness.useCase.perform(
            .link(recordId: "record-1", accountId: "account-1"),
            snapshot: walletSnapshot(),
            account: account()
        )

        XCTAssertEqual(result.transaction, .accepted(.linked))
        XCTAssertEqual(result.refresh, .failed("refresh_failed"))
        XCTAssertEqual(repository.callCount, 1)
        XCTAssertEqual(harness.refreshCallCount(), 1)
    }

    func testA4IOS002EResetMakesOldTaskStaleWithoutRefresh() async {
        let gate = WalletSnapshotActionGate()
        let repository = WalletSnapshotActionRepositoryStub(gate: gate)
        var context = WalletSnapshotActionUserContext(
            userId: "user-1",
            generation: 4,
            isSignedIn: true
        )
        let harness = makeHarness(repository: repository, context: { context })

        async let pending = harness.useCase.perform(
            .create(recordId: "record-1"),
            snapshot: walletSnapshot()
        )
        await gate.waitUntilEntered()
        context = WalletSnapshotActionUserContext(
            userId: "user-2",
            generation: 5,
            isSignedIn: true
        )
        harness.useCase.reset()
        await gate.release()

        let result = await pending
        XCTAssertEqual(result.transaction, .stale(.sessionChanged))
        XCTAssertEqual(result.refresh, .notStarted)
        XCTAssertEqual(harness.refreshCallCount(), 0)
    }

    func testA4IOS002FAppStateKeepsPublicEntryAndProjectsResult() async {
        let repository = WalletSnapshotActionRepositoryStub(outcome: .needsConfirmation)
        let harness = makeHarness(repository: repository)
        let state = AppState(walletSnapshotActionUseCase: harness.useCase)

        let accepted = await state.createAccountFromWalletSnapshot(walletSnapshot())

        XCTAssertTrue(accepted)
        XCTAssertNil(state.walletSnapshotActionId)
        XCTAssertEqual(state.walletSnapshotMessage, "账户已关联，账期/还款需要确认")
        XCTAssertEqual(repository.callCount, 1)
        XCTAssertEqual(harness.refreshCallCount(), 1)
    }

    private func makeHarness(
        repository: WalletSnapshotActionRepositoryStub,
        isSignedIn: Bool = true,
        context: (() -> WalletSnapshotActionUserContext)? = nil,
        refresh: @escaping () async throws -> Void = {}
    ) -> WalletSnapshotActionHarness {
        var sessionCalls = 0
        var refreshCalls = 0
        let defaultContext = WalletSnapshotActionUserContext(
            userId: "user-1",
            generation: 1,
            isSignedIn: isSignedIn
        )
        let useCase = WalletSnapshotActionUseCase(
            repository: repository,
            sessionProvider: { _ in
                sessionCalls += 1
                return Self.session
            },
            contextProvider: { context?() ?? defaultContext },
            refresh: {
                refreshCalls += 1
                try await refresh()
            }
        )
        return WalletSnapshotActionHarness(
            useCase: useCase,
            sessionCallCount: { sessionCalls },
            refreshCallCount: { refreshCalls }
        )
    }

    private func walletSnapshot(id: String = "record-1") -> NativeWalletSnapshot {
        NativeWalletSnapshot(
            id: id,
            title: "微信钱包",
            summary: "余额快照",
            occurredAt: "2026-08-17T02:00:00Z",
            createdAt: "2026-08-17T02:00:00Z",
            payload: ["snapshot_balance": AnyCodable(320.0)],
            imagePath: nil,
            imageHash: nil,
            linkedAccountId: nil,
            kind: .asset,
            balance: 320,
            snapshotAt: "2026-08-17T02:00:00Z"
        )
    }

    private func account(id: String = "account-1") -> NativeAccount {
        NativeAccount(
            id: id, name: "微信钱包", type: .walletBalance, institution: "微信", last4: "",
            currency: "CNY", initialBalance: 320, currentBalance: 320, snapshotBalance: 320,
            snapshotAt: "2026-08-17T02:00:00Z", sourceRecordTable: "data_records", sourceRecordId: "record-1",
            billDay: nil, paymentDueDay: nil, autoDebitAccountId: nil, autoConfirmRepayment: false,
            gracePeriodDays: 0, lastReconciledAt: nil, isDefaultExpense: false, isDefaultIncome: false,
            isArchived: false, sortOrder: 0
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

private struct WalletSnapshotActionHarness {
    let useCase: WalletSnapshotActionUseCase
    let sessionCallCount: () -> Int
    let refreshCallCount: () -> Int
}

private final class WalletSnapshotActionRepositoryStub: WalletSnapshotRepositoryProtocol {
    private let outcome: NativeWalletSnapshotOutcome
    private let gate: WalletSnapshotActionGate?
    private(set) var callCount = 0

    init(
        outcome: NativeWalletSnapshotOutcome = .created,
        gate: WalletSnapshotActionGate? = nil
    ) {
        self.outcome = outcome
        self.gate = gate
    }

    func fetchUnlinked(accessToken: String) async throws -> [NativeWalletSnapshot] { [] }
    func fetch(id: String, accessToken: String) async throws -> NativeWalletSnapshot? { nil }

    func createAccount(
        from snapshot: NativeWalletSnapshot,
        userId: String,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult {
        try await result(recordId: snapshot.id, accountId: "account-1")
    }

    func link(
        _ snapshot: NativeWalletSnapshot,
        to account: NativeAccount,
        userId: String,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult {
        try await result(recordId: snapshot.id, accountId: account.id)
    }

    private func result(recordId: String, accountId: String) async throws -> NativeWalletSnapshotLinkResult {
        callCount += 1
        if let gate { await gate.enterAndWait() }
        return NativeWalletSnapshotLinkResult(
            accountId: accountId,
            outcome: outcome,
            recordId: recordId,
            reviewRequired: outcome == .needsConfirmation
        )
    }
}

private actor WalletSnapshotActionGate {
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

private enum WalletSnapshotActionTestError: LocalizedError {
    case refreshFailed

    var errorDescription: String? { "refresh_failed" }
}

private extension NativeWalletSnapshotOutcome {
    static var allCasesForTests: [Self] {
        [.created, .linked, .replayed, .needsConfirmation]
    }
}
