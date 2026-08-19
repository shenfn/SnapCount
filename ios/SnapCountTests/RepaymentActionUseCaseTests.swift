import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class RepaymentActionUseCaseTests: XCTestCase {
    func testA4IOS003ARejectsInvalidInputAndUnauthenticatedBeforeTransport() async {
        let repository = RepaymentActionRepositoryStub()
        let signedOut = makeHarness(repository: repository, context: .init(userId: "", generation: 1, isSignedIn: false))
        let invalid = await signedOut.useCase.perform(.confirm(
            cycleId: "cycle-1", accountId: "account-1", paidAmount: 0,
            debitAccountId: nil, status: .partialPaid, note: ""
        ))

        XCTAssertEqual(invalid.rejection, .invalidInput)
        XCTAssertEqual(repository.confirmCallCount, 0)
        XCTAssertEqual(signedOut.sessionCallCount(), 0)

        let unauthenticated = makeHarness(
            repository: repository,
            context: .init(userId: "user-1", generation: 1, isSignedIn: false)
        )
        let result = await unauthenticated.useCase.perform(.confirm(
            cycleId: "cycle-1", accountId: "account-1", paidAmount: 120,
            debitAccountId: nil, status: .partialPaid, note: "手动还款"
        ))

        XCTAssertEqual(result.rejection, .unauthenticated)
        XCTAssertEqual(repository.confirmCallCount, 0)
        XCTAssertEqual(unauthenticated.sessionCallCount(), 0)
    }

    func testA4IOS003BReusesSameCommandAndRejectsDifferentCommandForSameCycle() async {
        let gate = RepaymentActionGate()
        let repository = RepaymentActionRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let confirm = RepaymentActionCommand.confirm(
            cycleId: "cycle-1", accountId: "account-1", paidAmount: 120,
            debitAccountId: "cash-1", status: .partialPaid, note: "手动还款"
        )

        async let first = harness.useCase.perform(confirm)
        await gate.waitUntilEntered()
        async let duplicate = harness.useCase.perform(confirm)
        let conflict = await harness.useCase.perform(.revoke(
            paymentId: "payment-1", cycleId: "cycle-1", accountId: "account-1"
        ))

        XCTAssertEqual(conflict.conflict, .repaymentConflict)
        XCTAssertEqual(repository.confirmCallCount, 1)

        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.accepted?.cycle.id, "cycle-1")
        XCTAssertEqual(duplicateResult.accepted?.cycle.id, "cycle-1")
        XCTAssertEqual(repository.confirmCallCount, 1)
    }

    func testA4IOS003CAcceptedTransactionRemainsAcceptedWhenRefreshFails() async {
        let repository = RepaymentActionRepositoryStub()
        let harness = makeHarness(
            repository: repository,
            refresh: { throw RepaymentActionTestError.refreshFailed }
        )

        let result = await harness.useCase.perform(.confirm(
            cycleId: "cycle-1", accountId: "account-1", paidAmount: 120,
            debitAccountId: nil, status: .partialPaid, note: "手动还款"
        ))

        XCTAssertEqual(result.accepted?.cycle.id, "cycle-1")
        XCTAssertEqual(result.refresh, .failed("refresh_failed"))
        XCTAssertEqual(repository.confirmCallCount, 1)
        XCTAssertEqual(harness.refreshCallCount(), 1)
    }

    func testA4IOS003DResetMakesPendingConfirmationStaleWithoutRefresh() async {
        let gate = RepaymentActionGate()
        let repository = RepaymentActionRepositoryStub(gate: gate)
        var context = RepaymentActionUserContext(userId: "user-1", generation: 4, isSignedIn: true)
        let harness = makeHarness(repository: repository, contextProvider: { context })

        async let pending = harness.useCase.perform(.confirm(
            cycleId: "cycle-1", accountId: "account-1", paidAmount: 120,
            debitAccountId: nil, status: .partialPaid, note: "手动还款"
        ))
        await gate.waitUntilEntered()
        context = RepaymentActionUserContext(userId: "user-2", generation: 5, isSignedIn: true)
        harness.useCase.reset()
        await gate.release()

        let result = await pending
        XCTAssertTrue(result.isStale)
        XCTAssertNil(result.accepted)
        XCTAssertEqual(result.refresh, .notStarted)
        XCTAssertEqual(harness.refreshCallCount(), 0)
    }

    func testA4IOS003ERevokeUsesPaymentCommandAndReturnsCanonicalCycle() async {
        let repository = RepaymentActionRepositoryStub()
        let harness = makeHarness(repository: repository)

        let result = await harness.useCase.perform(.revoke(
            paymentId: "payment-1", cycleId: "cycle-1", accountId: "account-1"
        ))

        XCTAssertEqual(result.accepted?.cycle.id, "cycle-1")
        XCTAssertEqual(repository.revokeCallCount, 1)
        XCTAssertEqual(repository.lastPaymentId, "payment-1")
        XCTAssertEqual(result.refresh, .succeeded)
    }

    func testA4IOS003FAppStateKeepsPublicEntryAndProjectsAcceptedResult() async {
        let repository = RepaymentActionRepositoryStub()
        let harness = makeHarness(repository: repository)
        let state = AppState(repaymentActionUseCase: harness.useCase)

        let accepted = await state.confirmRepayment(
            cycle: repaymentCycle(),
            paidAmount: 120,
            debitAccountId: "cash-1",
            status: .partialPaid,
            note: "手动还款"
        )

        XCTAssertTrue(accepted)
        XCTAssertFalse(state.isSubmittingRepayment)
        XCTAssertEqual(state.repaymentMessage, "已确认还款并记录扣款")
        XCTAssertEqual(repository.confirmCallCount, 1)
        XCTAssertEqual(harness.refreshCallCount(), 1)
    }

    private func makeHarness(
        repository: RepaymentActionRepositoryStub,
        context: RepaymentActionUserContext = .init(userId: "user-1", generation: 1, isSignedIn: true),
        contextProvider: (() -> RepaymentActionUserContext)? = nil,
        refresh: @escaping () async throws -> Void = {}
    ) -> RepaymentActionHarness {
        var sessionCalls = 0
        var refreshCalls = 0
        let useCase = RepaymentActionUseCase(
            repository: repository,
            sessionProvider: { _ in
                sessionCalls += 1
                return Self.session
            },
            contextProvider: { contextProvider?() ?? context },
            refresh: { _ in
                refreshCalls += 1
                try await refresh()
            }
        )
        return RepaymentActionHarness(
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

    private func repaymentCycle() -> NativeRepaymentCycle {
        NativeRepaymentCycle(
            id: "cycle-1",
            accountId: "account-1",
            cycleMonth: "2026-08",
            statementStartDate: "2026-08-01",
            statementEndDate: "2026-08-31",
            dueDate: "2026-08-20",
            statementAmount: 500,
            paidAmount: 0,
            remainingAmount: 500,
            carriedOverAmount: 0,
            originalStatementAmount: nil,
            minPaymentAmount: 50,
            refundAppliedAmount: 0,
            status: .pending,
            autoDebitAccountId: nil,
            autoConfirmRepayment: false,
            source: "manual",
            evidenceRecordId: nil,
            confidence: nil,
            note: "",
            confirmedAt: nil
        )
    }
}

private struct RepaymentActionHarness {
    let useCase: RepaymentActionUseCase
    let sessionCallCount: () -> Int
    let refreshCallCount: () -> Int
}

private final class RepaymentActionRepositoryStub: AccountRepositoryProtocol {
    private let gate: RepaymentActionGate?
    private(set) var confirmCallCount = 0
    private(set) var revokeCallCount = 0
    private(set) var lastPaymentId: String?

    init(gate: RepaymentActionGate? = nil) {
        self.gate = gate
    }

    func fetchAccounts(accessToken: String) async throws -> [NativeAccount] { [] }
    func fetchDetail(account: NativeAccount, accessToken: String) async -> NativeAccountDetail {
        NativeAccountDetail(account: account, entries: [], repaymentCycles: [], payments: [], loadErrors: [:])
    }
    func fetchOpenRepaymentCycles(accessToken: String) async throws -> [NativeRepaymentCycle] { [] }
    func save(_ draft: NativeAccountDraft, userId: String, accessToken: String) async throws -> [NativeAccount] { [] }
    func setArchived(accountId: String, archived: Bool, accessToken: String) async throws -> [NativeAccount] { [] }
    func ensureRepaymentCycles(monthKey: String, accessToken: String) async throws {}

    func confirmRepayment(
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        status: NativeRepaymentStatus,
        note: String,
        accessToken: String
    ) async throws -> NativeRepaymentCycle {
        confirmCallCount += 1
        if let gate { await gate.enterAndWait() }
        return cycle(id: cycleId, accountId: "account-1", status: status)
    }

    func revokePayment(paymentId: String, accessToken: String) async throws -> NativeRepaymentCycle? {
        revokeCallCount += 1
        lastPaymentId = paymentId
        return cycle(id: "cycle-1", accountId: "account-1", status: .partialPaid)
    }

    private func cycle(id: String, accountId: String, status: NativeRepaymentStatus) -> NativeRepaymentCycle {
        NativeRepaymentCycle(
            id: id,
            accountId: accountId,
            cycleMonth: "2026-08",
            statementStartDate: "2026-08-01",
            statementEndDate: "2026-08-31",
            dueDate: "2026-08-20",
            statementAmount: 500,
            paidAmount: 120,
            remainingAmount: 380,
            carriedOverAmount: 0,
            originalStatementAmount: nil,
            minPaymentAmount: 50,
            refundAppliedAmount: 0,
            status: status,
            autoDebitAccountId: nil,
            autoConfirmRepayment: false,
            source: "manual",
            evidenceRecordId: nil,
            confidence: nil,
            note: "手动还款",
            confirmedAt: "2026-08-19T10:00:00Z"
        )
    }
}

private actor RepaymentActionGate {
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

private enum RepaymentActionTestError: LocalizedError {
    case refreshFailed

    var errorDescription: String? { "refresh_failed" }
}

private extension RepaymentActionResult {
    var accepted: RepaymentActionAccepted? {
        guard case let .accepted(value) = transaction else { return nil }
        return value
    }

    var rejection: RepaymentActionRejection? {
        guard case let .rejected(value) = transaction else { return nil }
        return value
    }

    var conflict: RepaymentActionConflict? {
        guard case let .conflict(value) = transaction else { return nil }
        return value
    }

    var isStale: Bool {
        if case .stale = transaction { return true }
        return false
    }
}
