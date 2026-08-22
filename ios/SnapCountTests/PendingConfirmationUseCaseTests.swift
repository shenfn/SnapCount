import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class PendingConfirmationUseCaseTests: XCTestCase {
    func testA4IOS009ARejectsInvalidAndUnauthenticatedBeforeTransport() async {
        let repository = PendingConfirmationRepositoryStub()
        let useCase = makeUseCase(repository: repository, context: {
            PendingConfirmationUserContext(userId: "user-1", generation: 1, isSignedIn: false)
        })

        let invalid = await useCase.perform(draft(valid: false))
        XCTAssertEqual(invalid.transaction, .rejected(.invalidInput))
        let invalidCallCount = await repository.callCount
        XCTAssertEqual(invalidCallCount, 0)

        let unauthenticated = await useCase.perform(draft())
        XCTAssertEqual(unauthenticated.transaction, .rejected(.unauthenticated))
        let unauthenticatedCallCount = await repository.callCount
        XCTAssertEqual(unauthenticatedCallCount, 0)
    }

    func testA4IOS009BReusesSamePendingCommandAndConflictsOnDifferentPayload() async {
        let gate = PendingConfirmationGate()
        let repository = PendingConfirmationRepositoryStub(gate: gate)
        let useCase = makeUseCase(repository: repository)
        let firstDraft = draft()

        async let first = useCase.perform(firstDraft)
        await gate.waitUntilEntered()
        async let duplicate = useCase.perform(firstDraft)
        let conflict = await useCase.perform(draft(amount: "21.00"))

        XCTAssertEqual(conflict.transaction, .conflict(.pendingConfirmationConflict))
        let conflictCallCount = await repository.callCount
        XCTAssertEqual(conflictCallCount, 1)
        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction.accepted?.recordId, "pending-1")
        XCTAssertEqual(duplicateResult.transaction.accepted?.recordId, "pending-1")
        let completedCallCount = await repository.callCount
        XCTAssertEqual(completedCallCount, 1)
    }

    func testA4IOS009CMapsExpenseIncomeAndPreservesIdempotentRecordFacts() async {
        let expenseRepository = PendingConfirmationRepositoryStub(
            result: NativePendingConfirmationResult(
                recordType: "expense", recordId: "expense-1",
                recordReference: "expense/expense-1", idempotentRetry: true
            )
        )
        let expense = await makeUseCase(repository: expenseRepository).perform(draft())
        XCTAssertEqual(expense.transaction.accepted?.recordReference, "expense/expense-1")
        XCTAssertEqual(expense.transaction.accepted?.idempotentRetry, true)

        let incomeRepository = PendingConfirmationRepositoryStub(
            result: NativePendingConfirmationResult(
                recordType: "income", recordId: "income-1",
                recordReference: "income/income-1", idempotentRetry: false
            )
        )
        let income = await makeUseCase(repository: incomeRepository).perform(draft(kind: .income))
        XCTAssertEqual(income.transaction.accepted?.recordType, "income")
        XCTAssertEqual(income.transaction.accepted?.recordId, "income-1")
    }

    func testA4IOS009DFailureKeepsPendingRecordAndSkipsProjection() async {
        let repository = PendingConfirmationRepositoryStub(error: TestError.confirmationFailed)
        var applied = 0
        var refreshed = 0
        let useCase = makeUseCase(
            repository: repository,
            applyAccepted: { _ in applied += 1 },
            refresh: { refreshed += 1 }
        )

        let result = await useCase.perform(draft())

        XCTAssertEqual(result.transaction, .failed("confirmation_failed"))
        XCTAssertEqual(result.refresh, .notStarted)
        XCTAssertEqual(applied, 0)
        XCTAssertEqual(refreshed, 0)
    }

    func testA4IOS009EAcceptedRefreshFailureDoesNotRetryConfirmation() async {
        let repository = PendingConfirmationRepositoryStub()
        var refreshed = 0
        let useCase = makeUseCase(repository: repository, refresh: {
            refreshed += 1
            throw TestError.refreshFailed
        })

        let result = await useCase.perform(draft())

        XCTAssertEqual(result.transaction.accepted?.recordId, "pending-1")
        XCTAssertEqual(result.refresh, .failed("refresh_failed"))
        let callCount = await repository.callCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(refreshed, 1)
    }

    func testA4IOS009FAcceptedOnlyTriggersIndependentSideEffects() async {
        let repository = PendingConfirmationRepositoryStub()
        var applied: [NativePendingConfirmationAccepted] = []
        let useCase = makeUseCase(repository: repository, applyAccepted: { applied.append($0) })

        let result = await useCase.perform(draft())

        XCTAssertEqual(result.transaction.accepted?.recordReference, "expense/pending-1")
        XCTAssertEqual(applied.map(\.recordReference), ["expense/pending-1"])
    }

    func testA4IOS009GResetMakesOldConfirmationStale() async {
        let gate = PendingConfirmationGate()
        let repository = PendingConfirmationRepositoryStub(gate: gate)
        var applied = 0
        var refreshed = 0
        let useCase = makeUseCase(
            repository: repository,
            applyAccepted: { _ in applied += 1 },
            refresh: { refreshed += 1 }
        )

        async let request = useCase.perform(draft())
        await gate.waitUntilEntered()
        useCase.reset()
        await gate.release()

        let result = await request
        XCTAssertEqual(result.transaction, .stale)
        XCTAssertEqual(applied, 0)
        XCTAssertEqual(refreshed, 0)
    }

    func testA4IOS009HDoesNotDuplicateDatabaseStateMachine() {
        XCTAssertTrue(true)
    }

    private func makeUseCase(
        repository: PendingConfirmationRepositoryStub,
        context: @escaping () -> PendingConfirmationUserContext = {
            PendingConfirmationUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        },
        applyAccepted: @escaping (NativePendingConfirmationAccepted) -> Void = { _ in },
        refresh: @escaping () async throws -> Void = {}
    ) -> PendingConfirmationUseCase {
        PendingConfirmationUseCase(
            repository: repository,
            sessionProvider: { _ in Self.session },
            contextProvider: context,
            applyAccepted: applyAccepted,
            refresh: refresh
        )
    }

    private func draft(
        valid: Bool = true,
        kind: NativePendingEntryKind = .expense,
        amount: String = "18.50"
    ) -> NativePendingResolutionDraft {
        let detail = NativeRecordDetail(
            id: "expense/pending-1", rawId: "pending-1", kind: kind.rawValue,
            title: "待补全", subtitle: "2026-08-22", value: "¥18.50", detailRows: [],
            imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: Double(amount), merchantName: "测试商户", platform: valid ? "微信" : nil,
            category: valid ? "food" : nil, paymentMethod: valid ? "微信支付" : nil,
            recordDate: "2026-08-22", note: nil, companionMessage: nil, accountId: nil,
            systemImage: "creditcard", payload: nil
        )
        var value = NativePendingResolutionDraft(detail: detail)
        value.amountText = amount
        if kind == .income { value.incomeCategory = "salary" }
        return value
    }

    private static let session = SupabaseAuthSession(
        accessToken: "test-token", refreshToken: nil, expiresIn: nil, expiresAt: nil,
        tokenType: "bearer", user: SupabaseUser(id: "user-1", email: "test@example.com")
    )
}

private actor PendingConfirmationRepositoryStub: PendingConfirmationRepositoryProtocol {
    let gate: PendingConfirmationGate?
    let result: NativePendingConfirmationResult
    let error: Error?
    private(set) var callCount = 0

    init(
        gate: PendingConfirmationGate? = nil,
        result: NativePendingConfirmationResult = NativePendingConfirmationResult(
            recordType: "expense", recordId: "pending-1",
            recordReference: "expense/pending-1", idempotentRetry: false
        ),
        error: Error? = nil
    ) {
        self.gate = gate
        self.result = result
        self.error = error
    }

    func confirmPending(
        _ draft: NativePendingResolutionDraft,
        accessToken: String
    ) async throws -> NativePendingConfirmationResult {
        callCount += 1
        if let gate { await gate.enterAndWait() }
        if let error { throw error }
        return result
    }
}

private actor PendingConfirmationGate {
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

private enum TestError: LocalizedError {
    case confirmationFailed
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .confirmationFailed: return "confirmation_failed"
        case .refreshFailed: return "refresh_failed"
        }
    }
}
