import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class ScreenshotRepaymentUseCaseTests: XCTestCase {
    func testA4IOS006BReusesSameCommandAndRejectsDifferentCommandConflict() async {
        let gate = ScreenshotRepaymentGate()
        let repository = ScreenshotRepaymentRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let command = ScreenshotRepaymentCommand(
            stagingId: "staging-1",
            cycleId: "cycle-1",
            paidAmount: 100,
            debitAccountId: "debit-1",
            note: "根据还款截图确认"
        )

        async let first = harness.useCase.confirm(command)
        await gate.waitUntilEntered()
        async let duplicate = harness.useCase.confirm(command)
        let conflict = await harness.useCase.confirm(command.with(paidAmount: 80))

        XCTAssertEqual(conflict.transaction, .conflict(.screenshotRepaymentConflict))
        XCTAssertEqual(repository.callCount, 1)
        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction, .accepted)
        XCTAssertEqual(duplicateResult.transaction, .accepted)
        XCTAssertEqual(repository.callCount, 1)
    }

    func testA4IOS006CRejectsUnauthenticatedAndInvalidInputBeforeTransport() async {
        let repository = ScreenshotRepaymentRepositoryStub()
        var context = ScreenshotRepaymentUserContext(userId: "", generation: 1, isSignedIn: false)
        let harness = makeHarness(repository: repository, contextProvider: { context })
        let valid = ScreenshotRepaymentCommand(stagingId: "staging-1", cycleId: "cycle-1", paidAmount: 100)

        XCTAssertEqual((await harness.useCase.confirm(valid)).transaction, .rejected(.unauthenticated))
        context = ScreenshotRepaymentUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        XCTAssertEqual(
            (await harness.useCase.confirm(valid.with(stagingId: ""))).transaction,
            .rejected(.invalidInput)
        )
        XCTAssertEqual(repository.callCount, 0)
    }

    func testA4IOS006DResetMakesAcceptedTransportStaleWithoutHooks() async {
        let gate = ScreenshotRepaymentGate()
        let repository = ScreenshotRepaymentRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        var acceptedCount = 0
        var refreshCount = 0
        let command = ScreenshotRepaymentCommand(stagingId: "staging-1", cycleId: "cycle-1", paidAmount: 100)

        async let pending = harness.useCase.confirm(
            command,
            onAccepted: { _ in acceptedCount += 1 },
            refresh: { _ in refreshCount += 1 }
        )
        await gate.waitUntilEntered()
        harness.useCase.reset()
        await gate.release()

        let result = await pending
        XCTAssertEqual(result.transaction, .stale)
        XCTAssertEqual(acceptedCount, 0)
        XCTAssertEqual(refreshCount, 0)
    }

    func testA4IOS006EAcceptedProjectsBeforeRefresh() async {
        let repository = ScreenshotRepaymentRepositoryStub()
        let harness = makeHarness(repository: repository)
        var events: [String] = []
        let command = ScreenshotRepaymentCommand(stagingId: "staging-1", cycleId: "cycle-1", paidAmount: 100)

        let result = await harness.useCase.confirm(
            command,
            onAccepted: { cycle in
                events.append("accepted:\(cycle.id)")
            },
            refresh: { _ in
                events.append("refresh")
            }
        )

        XCTAssertEqual(result.transaction, .accepted)
        XCTAssertEqual(result.refresh, .succeeded)
        XCTAssertEqual(events, ["accepted:cycle-1", "refresh"])
    }

    func testA4IOS006FRefreshFailureKeepsAcceptedTransaction() async {
        let repository = ScreenshotRepaymentRepositoryStub()
        let harness = makeHarness(repository: repository)
        let command = ScreenshotRepaymentCommand(stagingId: "staging-1", cycleId: "cycle-1", paidAmount: 100)

        let result = await harness.useCase.confirm(
            command,
            onAccepted: { _ in },
            refresh: { _ in throw SupabaseRemoteError.requestFailed("refresh_failed") }
        )

        XCTAssertEqual(result.transaction, .accepted)
        guard case .failed(let message) = result.refresh else {
            return XCTFail("refresh failure must stay separate from accepted transaction")
        }
        XCTAssertEqual(message, "refresh_failed")
    }

    private func makeHarness(
        repository: ScreenshotRepaymentRepositoryStub,
        contextProvider: (() -> ScreenshotRepaymentUserContext)? = nil
    ) -> ScreenshotRepaymentHarness {
        var context = ScreenshotRepaymentUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        let useCase = ScreenshotRepaymentUseCase(
            repository: repository,
            sessionProvider: { _ in Self.session },
            contextProvider: {
                contextProvider?() ?? context
            }
        )
        return ScreenshotRepaymentHarness(useCase: useCase, context: { context })
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

private struct ScreenshotRepaymentHarness {
    let useCase: ScreenshotRepaymentUseCase
    let context: () -> ScreenshotRepaymentUserContext
}

@MainActor
private final class ScreenshotRepaymentRepositoryStub: ScreenshotRepaymentRepositoryProtocol {
    private let gate: ScreenshotRepaymentGate?
    private(set) var callCount = 0

    init(gate: ScreenshotRepaymentGate? = nil) {
        self.gate = gate
    }

    func confirmStagingRepayment(
        id: String,
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        note: String,
        accessToken: String
    ) async throws -> NativeRepaymentCycle {
        callCount += 1
        await gate?.entered()
        await gate?.waitForRelease()
        return NativeRepaymentCycle(
            id: cycleId,
            accountId: "account-1",
            cycleMonth: "2026-08",
            statementStartDate: nil,
            statementEndDate: nil,
            dueDate: "2026-08-15",
            statementAmount: 100,
            paidAmount: paidAmount,
            remainingAmount: 0,
            carriedOverAmount: 0,
            originalStatementAmount: 100,
            minPaymentAmount: nil,
            refundAppliedAmount: 0,
            status: .paid,
            autoDebitAccountId: debitAccountId,
            autoConfirmRepayment: false,
            source: "screenshot",
            evidenceRecordId: nil,
            confidence: 1,
            note: note,
            confirmedAt: "2026-08-21T00:00:00Z"
        )
    }
}

private actor ScreenshotRepaymentGate {
    private var entered = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func entered() async {
        entered = true
        let continuations = enteredContinuations
        enteredContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredContinuations.append($0) }
    }

    func waitForRelease() async {
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func release() async {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private extension ScreenshotRepaymentCommand {
    func with(
        stagingId: String? = nil,
        paidAmount: Double? = nil
    ) -> Self {
        Self(
            stagingId: stagingId ?? self.stagingId,
            cycleId: cycleId,
            paidAmount: paidAmount ?? self.paidAmount,
            debitAccountId: debitAccountId,
            note: note
        )
    }
}
