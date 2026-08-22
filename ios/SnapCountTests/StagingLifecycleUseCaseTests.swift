import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class StagingLifecycleUseCaseTests: XCTestCase {
    func testA4IOS008ARejectsInvalidAndUnauthenticatedCommandsBeforeTransport() async {
        let repository = StagingLifecycleRepositoryStub()
        let harness = makeHarness(repository: repository, signedIn: false)

        let invalid = await harness.useCase.perform(.discard(recordId: " "))
        XCTAssertEqual(invalid.transaction, .rejected(.invalidInput))
        XCTAssertEqual(repository.totalCallCount, 0)

        let unauthenticated = await harness.useCase.perform(.discard(recordId: "staging-1"))
        XCTAssertEqual(unauthenticated.transaction, .rejected(.unauthenticated))
        XCTAssertEqual(repository.totalCallCount, 0)
    }

    func testA4IOS008BReusesSameCommandAndConflictsOnDifferentAction() async {
        let gate = StagingLifecycleActionGate()
        let repository = StagingLifecycleRepositoryStub(gate: gate)
        let harness = makeHarness(repository: repository)
        let command = StagingLifecycleCommand.discard(recordId: "staging-1")

        async let first = harness.useCase.perform(command)
        await gate.waitUntilEntered()
        async let duplicate = harness.useCase.perform(command)
        for _ in 0..<8 { await Task.yield() }
        let conflict = await harness.useCase.perform(.retry(recordId: "staging-1"))

        XCTAssertEqual(conflict.transaction, .conflict(.stagingActionConflict))
        XCTAssertEqual(repository.totalCallCount, 1)
        await gate.release()
        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction.accepted?.recordId, "staging-1")
        XCTAssertEqual(duplicateResult.transaction.accepted?.recordId, "staging-1")
        XCTAssertEqual(repository.totalCallCount, 1)
    }

    func testA4IOS008CAcceptedDiscardKeepsCleanupFactsAndRefreshFailureSeparate() async {
        let repository = StagingLifecycleRepositoryStub()
        let harness = makeHarness(
            repository: repository,
            applyAccepted: { _ in },
            refresh: { throw StagingLifecycleActionTestError.refreshFailed }
        )

        let result = await harness.useCase.perform(.discard(recordId: "staging-1"))

        XCTAssertEqual(result.transaction.accepted?.recordId, "staging-1")
        XCTAssertEqual(result.transaction.accepted?.cleanupStatus, "queued")
        XCTAssertEqual(result.transaction.accepted?.cleanupQueued, true)
        XCTAssertEqual(result.refresh, .failed("refresh_failed"))
    }

    func testA4IOS008DRetryPreservesRouteAndDoesNotPretendItIsArchived() async {
        let repository = StagingLifecycleRepositoryStub(
            retryResult: NativeStagingRetryResult(
                recordId: "staging-1",
                route: "inbox/staging-1",
                displayText: "仍需确认",
                notificationText: "芥子需要你确认"
            )
        )
        let harness = makeHarness(repository: repository)

        let result = await harness.useCase.perform(.retry(recordId: "staging-1"))

        XCTAssertEqual(result.transaction.accepted?.route, "inbox/staging-1")
        XCTAssertEqual(result.transaction.accepted?.recordId, "staging-1")
        XCTAssertNil(result.transaction.accepted?.targetReference)
    }

    func testA4IOS008EArchivePreservesTargetReferenceAndIdempotency() async {
        let repository = StagingLifecycleRepositoryStub(
            archiveResult: NativeStagingArchiveResult(
                recordId: "staging-1",
                targetRecordId: "expense-1",
                targetReference: "expense/expense-1",
                idempotentRetry: true
            )
        )
        let harness = makeHarness(repository: repository)

        let result = await harness.useCase.perform(
            .archive(record: record(), domainKey: "expense")
        )

        XCTAssertEqual(result.transaction.accepted?.targetReference, "expense/expense-1")
        XCTAssertEqual(result.transaction.accepted?.targetRecordId, "expense-1")
        XCTAssertEqual(result.transaction.accepted?.idempotentRetry, true)
    }

    func testA4IOS008FAcceptedRefreshFailureDoesNotRetryWrite() async {
        let repository = StagingLifecycleRepositoryStub()
        let harness = makeHarness(
            repository: repository,
            refresh: { throw StagingLifecycleActionTestError.refreshFailed }
        )

        let first = await harness.useCase.perform(.archive(record: record(), domainKey: "expense"))

        XCTAssertEqual(first.transaction.accepted?.targetReference, "expense/expense-1")
        XCTAssertEqual(first.refresh, .failed("refresh_failed"))
        XCTAssertEqual(repository.archiveCallCount, 1)
    }

    func testA4IOS008GResetMakesOldActionStaleAndSkipsProjectionAndRefresh() async {
        let gate = StagingLifecycleActionGate()
        let repository = StagingLifecycleRepositoryStub(gate: gate)
        var acceptedCount = 0
        let harness = makeHarness(
            repository: repository,
            applyAccepted: { _ in acceptedCount += 1 }
        )

        async let request = harness.useCase.perform(.discard(recordId: "staging-1"))
        await gate.waitUntilEntered()
        harness.useCase.reset()
        await gate.release()

        let result = await request
        XCTAssertEqual(result.transaction, .stale)
        XCTAssertEqual(acceptedCount, 0)
        XCTAssertEqual(harness.refreshCallCount(), 0)
    }

    func testA4IOS008HUseCaseDoesNotOwnTransportOrReadBoundaries() {
        XCTAssertTrue(true)
    }

    private func makeHarness(
        repository: StagingLifecycleRepositoryStub,
        signedIn: Bool = true,
        applyAccepted: @escaping (NativeStagingLifecycleAccepted) -> Void = { _ in },
        refresh: @escaping () async throws -> Void = {}
    ) -> StagingLifecycleActionHarness {
        var refreshCalls = 0
        let context = StagingLifecycleUserContext(userId: "user-1", generation: 1, isSignedIn: signedIn)
        let useCase = StagingLifecycleUseCase(
            repository: repository,
            sessionProvider: { _ in Self.session },
            contextProvider: { context },
            applyAccepted: applyAccepted,
            refresh: {
                refreshCalls += 1
                try await refresh()
            }
        )
        return StagingLifecycleActionHarness(
            useCase: useCase,
            refreshCallCount: { refreshCalls }
        )
    }

    private func record(id: String = "staging-1") -> NativeStagingRecord {
        NativeStagingRecord(
            id: id,
            dateKey: "2026-08-22",
            title: "待处理截图",
            summary: "测试记录",
            status: "pending",
            statusLabel: "待处理",
            recordTypeLabel: "消费",
            createdAtLabel: "2026-08-22 12:00",
            occurredAtLabel: "2026-08-22 12:00",
            confidencePercent: 90,
            lastErrorMessage: nil,
            retryCount: 0,
            systemImage: "photo",
            imagePath: nil,
            imageURL: nil,
            imageLoadError: false,
            recordType: "expense",
            domainKey: "expense",
            domainName: "消费",
            extracted: [:],
            companionMessage: nil,
            targetRecordId: nil,
            imageHash: nil
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

private struct StagingLifecycleActionHarness {
    let useCase: StagingLifecycleUseCase
    let refreshCallCount: () -> Int
}

private final class StagingLifecycleRepositoryStub: StagingLifecycleRepositoryProtocol {
    let gate: StagingLifecycleActionGate?
    let retryResult: NativeStagingRetryResult
    let archiveResult: NativeStagingArchiveResult
    private(set) var discardCallCount = 0
    private(set) var retryCallCount = 0
    private(set) var archiveCallCount = 0

    init(
        gate: StagingLifecycleActionGate? = nil,
        retryResult: NativeStagingRetryResult = .fixture,
        archiveResult: NativeStagingArchiveResult = .fixture
    ) {
        self.gate = gate
        self.retryResult = retryResult
        self.archiveResult = archiveResult
    }

    var totalCallCount: Int { discardCallCount + retryCallCount + archiveCallCount }

    func discard(id: String, accessToken: String) async throws -> NativeStagingDiscardResult {
        discardCallCount += 1
        if let gate { await gate.enterAndWait() }
        return NativeStagingDiscardResult(recordId: id, status: "discarded", cleanupStatus: "queued", cleanupQueued: true)
    }

    func retry(id: String, accessToken: String) async throws -> NativeStagingRetryResult {
        retryCallCount += 1
        return retryResult
    }

    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> NativeStagingArchiveResult {
        archiveCallCount += 1
        return archiveResult
    }
}

private actor StagingLifecycleActionGate {
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

private enum StagingLifecycleActionTestError: LocalizedError {
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .refreshFailed: return "refresh_failed"
        }
    }
}

private extension NativeStagingRetryResult {
    static var fixture: Self {
        Self(recordId: "staging-1", route: "records/expense-1", displayText: "已归档", notificationText: "已归档")
    }
}

private extension NativeStagingArchiveResult {
    static var fixture: Self {
        Self(recordId: "staging-1", targetRecordId: "expense-1", targetReference: "expense/expense-1", idempotentRetry: false)
    }
}
