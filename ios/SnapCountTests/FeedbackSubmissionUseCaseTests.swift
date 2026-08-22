import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class FeedbackSubmissionUseCaseTests: XCTestCase {
    func testA4IOS010ARejectsInvalidAndUnauthenticatedBeforeTransport() async {
        let repository = FeedbackSubmissionRepositoryStub()
        let unauthenticated = makeUseCase(repository: repository, context: {
            FeedbackSubmissionUserContext(userId: "user-1", generation: 1, isSignedIn: false)
        })

        let invalid = await unauthenticated.perform(input(recordId: "", identity: "card-1"))
        XCTAssertEqual(invalid.transaction, .rejected(.invalidInput))
        let signedOut = await unauthenticated.perform(input())
        XCTAssertEqual(signedOut.transaction, .rejected(.unauthenticated))
        XCTAssertEqual(await repository.callCount, 0)
    }

    func testA4IOS010BReusesSameCommandAndAllowsDifferentIdentity() async {
        let gate = FeedbackSubmissionGate()
        let repository = FeedbackSubmissionRepositoryStub(gate: gate)
        let useCase = makeUseCase(repository: repository)

        async let first = useCase.perform(input(identity: "card-1"))
        await gate.waitUntilEntered()
        async let duplicate = useCase.perform(input(identity: "card-1"))
        async let different = useCase.perform(input(recordId: "record-2", identity: "card-2"))
        await gate.release()

        let (firstResult, duplicateResult, differentResult) = await (first, duplicate, different)
        XCTAssertEqual(firstResult.transaction, .accepted)
        XCTAssertEqual(duplicateResult.transaction, .accepted)
        XCTAssertEqual(differentResult.transaction, .accepted)
        XCTAssertEqual(await repository.callCount, 2)
    }

    func testA4IOS010CForwardsFeedbackFactsWithoutUserId() async {
        let repository = FeedbackSubmissionRepositoryStub()
        let useCase = makeUseCase(repository: repository)
        _ = await useCase.perform(input(freeText: "请更简洁", exposureEventId: "exposure-1"))

        let call = await repository.calls.first
        XCTAssertEqual(call?.recordId, "record-1")
        XCTAssertEqual(call?.choice, .helpful)
        XCTAssertEqual(call?.freeText, "请更简洁")
        XCTAssertEqual(call?.exposureEventId, "exposure-1")
    }

    func testA4IOS010DFailureDoesNotBecomeSubmitted() async {
        let repository = FeedbackSubmissionRepositoryStub(error: TestError.feedbackFailed)
        let useCase = makeUseCase(repository: repository)
        let result = await useCase.perform(input())
        XCTAssertEqual(result.transaction, .failed("feedback_failed"))
    }

    func testA4IOS010EResetMakesOldResultStale() async {
        let gate = FeedbackSubmissionGate()
        let repository = FeedbackSubmissionRepositoryStub(gate: gate)
        let useCase = makeUseCase(repository: repository)

        async let request = useCase.perform(input())
        await gate.waitUntilEntered()
        useCase.reset()
        await gate.release()

        let result = await request
        XCTAssertEqual(result.transaction, .stale)
    }

    func testA4IOS010FDoesNotExposeRefreshOrFinancialMutation() async {
        let repository = FeedbackSubmissionRepositoryStub()
        var accepted = 0
        let useCase = makeUseCase(repository: repository, applyAccepted: { accepted += 1 })
        let result = await useCase.perform(input())
        XCTAssertEqual(result.transaction, .accepted)
        XCTAssertEqual(accepted, 1)
    }

    private func makeUseCase(
        repository: FeedbackSubmissionRepositoryStub,
        context: @escaping () -> FeedbackSubmissionUserContext = {
            FeedbackSubmissionUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        },
        applyAccepted: @escaping () -> Void = {}
    ) -> FeedbackSubmissionUseCase {
        FeedbackSubmissionUseCase(
            repository: repository,
            sessionProvider: { _ in Self.session },
            contextProvider: context,
            applyAccepted: { _ in applyAccepted() }
        )
    }

    private func input(
        recordId: String = "record-1",
        identity: String = "card-1",
        freeText: String = "",
        exposureEventId: String? = nil
    ) -> FeedbackSubmissionInput {
        FeedbackSubmissionInput(
            recordId: recordId,
            feedbackIdentity: identity,
            choice: .helpful,
            freeText: freeText,
            exposureEventId: exposureEventId
        )
    }

    private static let session = SupabaseAuthSession(
        accessToken: "test-token", refreshToken: nil, expiresIn: nil, expiresAt: nil,
        tokenType: "bearer", user: SupabaseUser(id: "user-1", email: "test@example.com")
    )
}

private actor FeedbackSubmissionRepositoryStub: NativeRecordFeedbackRepositoryProtocol {
    struct Call: Equatable {
        let recordId: String
        let choice: NativeAIFeedbackReviewChoice
        let freeText: String
        let exposureEventId: String?
    }

    let gate: FeedbackSubmissionGate?
    let error: Error?
    private(set) var calls: [Call] = []

    init(gate: FeedbackSubmissionGate? = nil, error: Error? = nil) {
        self.gate = gate
        self.error = error
    }

    var callCount: Int { calls.count }

    func submitFeedback(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?,
        accessToken: String
    ) async throws {
        calls.append(Call(recordId: recordId, choice: choice, freeText: freeText, exposureEventId: exposureEventId))
        if let gate { await gate.enterAndWait() }
        if let error { throw error }
    }
}

private actor FeedbackSubmissionGate {
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
    case feedbackFailed

    var errorDescription: String? {
        switch self { case .feedbackFailed: return "feedback_failed" }
    }
}
