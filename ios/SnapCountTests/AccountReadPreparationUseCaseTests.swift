import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class AccountReadPreparationUseCaseTests: XCTestCase {
    func testA4IOS005ARejectsUnauthenticatedBeforeEnsure() async {
        let repository = AccountReadPreparationRepositoryStub()
        var context = AccountReadPreparationUserContext(userId: "", generation: 1, isSignedIn: false)
        let harness = makeHarness(repository: repository, contextProvider: { context })

        let result = await harness.useCase.prepare(monthKey: "2026-08")

        XCTAssertEqual(result.transaction, .rejected(.unauthenticated))
        XCTAssertEqual(repository.ensureCallCount, 0)
        XCTAssertEqual(harness.sessionCallCount(), 0)
        context = AccountReadPreparationUserContext(userId: "user-1", generation: 1, isSignedIn: true)

        let invalidMonth = await harness.useCase.prepare(monthKey: "2026-13")
        XCTAssertEqual(invalidMonth.transaction, .rejected(.invalidInput))
        XCTAssertEqual(repository.ensureCallCount, 0)
        XCTAssertEqual(harness.sessionCallCount(), 0)
    }

    func testA4IOS005BReusesSamePreparationTask() async {
        let gate = AccountReadPreparationGate()
        let repository = AccountReadPreparationRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)

        async let first = harness.useCase.prepare(monthKey: "2026-08")
        await gate.waitUntilEntered()
        async let duplicate = harness.useCase.prepare(monthKey: "2026-08")

        XCTAssertEqual(repository.ensureCallCount, 1)
        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction, .accepted)
        XCTAssertEqual(duplicateResult.transaction, .accepted)
        XCTAssertEqual(repository.ensureCallCount, 1)
    }

    func testA4IOS005CPreparationFailureIsObservableAndRetryable() async {
        let repository = AccountReadPreparationRepositoryStub(error: SupabaseRemoteError.requestFailed("prepare_failed"))
        let harness = makeHarness(repository: repository)

        let failed = await harness.useCase.prepare(monthKey: "2026-08")
        repository.error = nil
        let retried = await harness.useCase.prepare(monthKey: "2026-08")

        XCTAssertEqual(failed.transaction, .failed("prepare_failed"))
        XCTAssertEqual(retried.transaction, .accepted)
        XCTAssertEqual(repository.ensureCallCount, 2)
    }

    func testA4IOS005DResetMakesPreparationStaleWithoutSecondEnsure() async {
        let gate = AccountReadPreparationGate()
        let repository = AccountReadPreparationRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)

        async let pending = harness.useCase.prepare(monthKey: "2026-08")
        await gate.waitUntilEntered()
        harness.useCase.reset()
        await gate.release()

        let result = await pending
        XCTAssertEqual(result.transaction, .stale)
        XCTAssertEqual(repository.ensureCallCount, 1)
    }

    func testA4IOS005EUserSwitchMakesPreparationStale() async {
        let gate = AccountReadPreparationGate()
        let repository = AccountReadPreparationRepositoryStub(gate: gate)
        var context = AccountReadPreparationUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        let harness = makeHarness(repository: repository, contextProvider: { context })

        async let pending = harness.useCase.prepare(monthKey: "2026-08")
        await gate.waitUntilEntered()
        context = AccountReadPreparationUserContext(userId: "user-2", generation: 2, isSignedIn: true)
        await gate.release()

        let result = await pending
        XCTAssertEqual(result.transaction, .stale)
        XCTAssertEqual(repository.ensureCallCount, 1)
    }

    private func makeHarness(
        repository: AccountReadPreparationRepositoryStub,
        contextProvider: (() -> AccountReadPreparationUserContext)? = nil
    ) -> AccountReadPreparationHarness {
        var sessionCalls = 0
        let defaultContext = AccountReadPreparationUserContext(
            userId: "user-1",
            generation: 1,
            isSignedIn: true
        )
        let useCase = AccountReadPreparationUseCase(
            repository: repository,
            sessionProvider: { _ in
                sessionCalls += 1
                return Self.session
            },
            contextProvider: { contextProvider?() ?? defaultContext }
        )
        return AccountReadPreparationHarness(
            useCase: useCase,
            sessionCallCount: { sessionCalls }
        )
    }

    private static let session = SupabaseAuthSession(
        accessToken: "test-token",
        refreshToken: nil,
        expiresAt: nil,
        user: SupabaseAuthUser(id: "user-1", email: "test@example.com")
    )
}

private struct AccountReadPreparationHarness {
    let useCase: AccountReadPreparationUseCase
    let sessionCallCount: () -> Int
}

@MainActor
private final class AccountReadPreparationRepositoryStub: AccountReadPreparationRepositoryProtocol {
    private let gate: AccountReadPreparationGate?
    var error: Error?
    private(set) var ensureCallCount = 0
    private(set) var lastMonthKey: String?

    init(gate: AccountReadPreparationGate? = nil, error: Error? = nil) {
        self.gate = gate
        self.error = error
    }

    func ensureRepaymentCycles(monthKey: String, accessToken: String) async throws {
        ensureCallCount += 1
        lastMonthKey = monthKey
        await gate?.entered()
        await gate?.waitForRelease()
        if let error { throw error }
    }
}

private actor AccountReadPreparationGate {
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
        await withCheckedContinuation { continuation in
            enteredContinuations.append(continuation)
        }
    }

    func waitForRelease() async {
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func release() async {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
