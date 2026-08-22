import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class AccountBindingUseCaseTests: XCTestCase {
    func testA4IOS007ARejectsInvalidAndUnauthenticatedCommandsBeforeTransport() async {
        let repository = AccountBindingRepositoryStub()
        let unauthenticated = makeHarness(repository: repository, signedIn: false)
        let invalid = await unauthenticated.useCase.bind(record(), accountId: "   ")

        XCTAssertEqual(invalid.transaction, .rejected(.invalidInput))
        XCTAssertEqual(repository.bindCallCount, 0)
        XCTAssertEqual(unauthenticated.sessionCallCount(), 0)

        let rejected = await unauthenticated.useCase.bind(record(), accountId: "account-1")
        XCTAssertEqual(rejected.transaction, .rejected(.unauthenticated))
        XCTAssertEqual(repository.bindCallCount, 0)
    }

    func testA4IOS007BReusesSameCommandAndConflictsOnDifferentAccount() async {
        let gate = AccountBindingActionGate()
        let repository = AccountBindingRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let source = record(id: "expense-1")

        async let first = harness.useCase.bind(source, accountId: "account-1")
        await gate.waitUntilEntered()
        async let duplicate = harness.useCase.bind(source, accountId: "account-1")
        for _ in 0..<8 { await Task.yield() }
        let conflict = await harness.useCase.bind(source, accountId: "account-2")

        XCTAssertEqual(conflict.transaction, .conflict(.bindingConflict))
        XCTAssertEqual(repository.bindCallCount, 1)
        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction.accepted?.recordId, "expense-1")
        XCTAssertEqual(duplicateResult.transaction.accepted?.accountId, "account-1")
        XCTAssertEqual(repository.bindCallCount, 1)
    }

    func testA4IOS007CAcceptedRemovesOnlyMatchingIdentityAndRefreshFailureStaysAccepted() async {
        let repository = AccountBindingRepositoryStub()
        var removed: [(NativeUnboundRecordKind, String)] = []
        let harness = makeHarness(
            repository: repository,
            applyAccepted: { accepted in removed.append((accepted.kind, accepted.recordId)) },
            refresh: { throw AccountBindingActionTestError.refreshFailed }
        )

        let result = await harness.useCase.bind(record(id: "same-id", kind: .income), accountId: "account-1")

        XCTAssertEqual(result.transaction.accepted?.recordId, "same-id")
        XCTAssertEqual(result.transaction.accepted?.kind, .income)
        XCTAssertEqual(result.refresh, .failed("refresh_failed"))
        XCTAssertEqual(removed.map { "\($0.0.rawValue)/\($0.1)" }, ["income/same-id"])
    }

    func testA4IOS007DBatchPreservesItemFactsAndPartialStatus() async {
        let repository = AccountBindingRepositoryStub(failingIds: ["bad-expense"])
        let harness = makeHarness(repository: repository)
        let candidates = [
            candidate(record(id: "good-expense"), accountId: "account-1"),
            candidate(record(id: "bad-expense"), accountId: "account-1"),
            candidate(record(id: "good-income", kind: .income), accountId: "account-2")
        ]

        let result = await harness.useCase.bindBatch(candidates)

        XCTAssertEqual(result.status, .partial)
        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.failedCount, 1)
        XCTAssertEqual(result.items.map(\.recordId), ["good-expense", "bad-expense", "good-income"])
        XCTAssertEqual(result.items[1].transaction, .failed("service_failed"))
        XCTAssertEqual(harness.refreshCallCount(), 1)
    }

    func testA4IOS007EResetMakesOldResultStaleAndStopsRemainingBatchItems() async {
        let gate = AccountBindingActionGate()
        let repository = AccountBindingRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let candidates = [
            candidate(record(id: "first"), accountId: "account-1"),
            candidate(record(id: "second"), accountId: "account-1")
        ]

        async let request = harness.useCase.bindBatch(candidates)
        await gate.waitUntilEntered()
        harness.useCase.reset()
        await gate.release()

        let result = await request
        XCTAssertEqual(result.status, .stale)
        XCTAssertEqual(repository.bindCallCount, 1)
        XCTAssertEqual(harness.refreshCallCount(), 0)
    }

    func testA4IOS007FRepositoryResultKeepsKindRecordAndAccountIdentity() async {
        let repository = AccountBindingRepositoryStub()
        let harness = makeHarness(repository: repository)
        let result = await harness.useCase.bind(record(id: "income-1", kind: .income), accountId: "account-2")

        guard case .accepted(let accepted) = result.transaction else {
            return XCTFail("expected accepted binding")
        }
        XCTAssertEqual(accepted.kind, .income)
        XCTAssertEqual(accepted.recordId, "income-1")
        XCTAssertEqual(accepted.accountId, "account-2")
    }

    func testA4IOS007GDoesNotMoveRecommendationOrReadIntoBindingAction() {
        XCTAssertTrue(NativeAccountRecommendationEngine.candidates(records: [], accounts: []).isEmpty)
    }

    private func makeHarness(
        repository: AccountBindingRepositoryStub,
        signedIn: Bool = true,
        applyAccepted: @escaping (NativeAccountBindingResult) -> Void = { _ in },
        refresh: @escaping () async throws -> Void = {}
    ) -> AccountBindingActionHarness {
        var sessionCalls = 0
        var refreshCalls = 0
        let context = AccountBindingUserContext(userId: "user-1", generation: 1, isSignedIn: signedIn)
        let useCase = AccountBindingUseCase(
            repository: repository,
            sessionProvider: { _ in
                sessionCalls += 1
                return Self.session
            },
            contextProvider: { context },
            applyAccepted: applyAccepted,
            refresh: {
                refreshCalls += 1
                try await refresh()
            }
        )
        return AccountBindingActionHarness(
            useCase: useCase,
            sessionCallCount: { sessionCalls },
            refreshCallCount: { refreshCalls }
        )
    }

    private func record(
        id: String = "expense-1",
        kind: NativeUnboundRecordKind = .expense
    ) -> NativeUnboundRecord {
        NativeUnboundRecord(
            id: id,
            kind: kind,
            title: "测试记录",
            amount: 12.5,
            date: "2026-08-22",
            time: "12:00:00",
            platform: nil,
            category: "food",
            paymentMethod: "微信支付",
            note: nil,
            source: "manual",
            imagePath: nil,
            imageHash: nil,
            companionMessage: nil
        )
    }

    private func candidate(_ record: NativeUnboundRecord, accountId: String) -> NativeUnboundBindingCandidate {
        NativeUnboundBindingCandidate(
            record: record,
            recommendation: NativeAccountRecommendation(
                account: NativeAccount.fixture(id: accountId),
                reason: "测试",
                confidence: "高"
            )
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

private struct AccountBindingActionHarness {
    let useCase: AccountBindingUseCase
    let sessionCallCount: () -> Int
    let refreshCallCount: () -> Int
}

private final class AccountBindingRepositoryStub: UnboundRecordRepositoryProtocol {
    private let gate: AccountBindingActionGate?
    private let failingIds: Set<String>
    private(set) var bindCallCount = 0

    init(gate: AccountBindingActionGate? = nil, failingIds: Set<String> = []) {
        self.gate = gate
        self.failingIds = failingIds
    }

    func fetch(monthKey: String, accessToken: String) async throws -> [NativeUnboundRecord] { [] }

    func bind(
        _ record: NativeUnboundRecord,
        accountId: String,
        accessToken: String
    ) async throws -> NativeAccountBindingResult {
        bindCallCount += 1
        if let gate { await gate.enterAndWait() }
        if failingIds.contains(record.id) { throw AccountBindingActionTestError.serviceFailed }
        return NativeAccountBindingResult(recordId: record.id, kind: record.kind, accountId: accountId)
    }
}

private actor AccountBindingActionGate {
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

private enum AccountBindingActionTestError: LocalizedError {
    case serviceFailed
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .serviceFailed: return "service_failed"
        case .refreshFailed: return "refresh_failed"
        }
    }
}

private extension NativeAccount {
    static func fixture(id: String) -> NativeAccount {
        NativeAccount(
            id: id,
            name: "测试账户",
            type: .walletBalance,
            institution: "测试机构",
            last4: "",
            currency: "CNY",
            initialBalance: 100,
            currentBalance: 100,
            snapshotBalance: nil,
            snapshotAt: nil,
            sourceRecordTable: "",
            sourceRecordId: "",
            billDay: nil,
            paymentDueDay: nil,
            autoDebitAccountId: nil,
            autoConfirmRepayment: false,
            gracePeriodDays: 0,
            lastReconciledAt: nil,
            isDefaultExpense: false,
            isDefaultIncome: false,
            isArchived: false,
            sortOrder: 0
        )
    }
}
