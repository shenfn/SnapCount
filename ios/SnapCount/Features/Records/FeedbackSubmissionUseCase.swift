import Foundation

struct FeedbackSubmissionInput: Equatable {
    let recordId: String
    let feedbackIdentity: String
    let choice: NativeAIFeedbackReviewChoice
    let freeText: String
    let exposureEventId: String?
}
struct FeedbackSubmissionUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum FeedbackSubmissionRejection: Equatable {
    case unauthenticated
    case invalidInput
}

enum FeedbackSubmissionTransaction: Equatable {
    case accepted
    case rejected(FeedbackSubmissionRejection)
    case failed(String)
    case stale
}

struct FeedbackSubmissionResult: Equatable {
    let transaction: FeedbackSubmissionTransaction
}

@MainActor
final class FeedbackSubmissionUseCase {
    typealias ContextProvider = () -> FeedbackSubmissionUserContext
    typealias ApplyAccepted = (FeedbackSubmissionInput) -> Void

    private struct Identity: Hashable {
        let userId: String
        let recordId: String
        let feedbackIdentity: String
    }

    private struct InFlight {
        let token: UUID
        let task: Task<FeedbackSubmissionResult, Never>
    }

    private let repository: NativeRecordFeedbackRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private let applyAccepted: ApplyAccepted
    private var inFlight: [Identity: InFlight] = [:]
    private var resetGeneration = 0

    init(
        repository: NativeRecordFeedbackRepositoryProtocol,
        sessionProvider: @escaping NativeSessionProvider,
        contextProvider: @escaping ContextProvider,
        applyAccepted: @escaping ApplyAccepted = { _ in }
    ) {
        self.repository = repository
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
        self.applyAccepted = applyAccepted
    }

    func perform(_ input: FeedbackSubmissionInput) async -> FeedbackSubmissionResult {
        guard isValid(input) else {
            return FeedbackSubmissionResult(transaction: .rejected(.invalidInput))
        }
        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return FeedbackSubmissionResult(transaction: .rejected(.unauthenticated))
        }

        let identity = Identity(
            userId: context.userId,
            recordId: input.recordId,
            feedbackIdentity: input.feedbackIdentity
        )
        if let existing = inFlight[identity] {
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else {
                return FeedbackSubmissionResult(transaction: .stale)
            }
            return await self.execute(
                input,
                context: context,
                expectedResetGeneration: expectedResetGeneration
            )
        }
        inFlight[identity] = InFlight(token: token, task: task)
        let result = await task.value
        if inFlight[identity]?.token == token {
            inFlight.removeValue(forKey: identity)
        }
        return result
    }

    func reset() {
        resetGeneration += 1
        inFlight.removeAll()
    }

    private func execute(
        _ input: FeedbackSubmissionInput,
        context: FeedbackSubmissionUserContext,
        expectedResetGeneration: Int
    ) async -> FeedbackSubmissionResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return FeedbackSubmissionResult(transaction: .stale)
        }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: FeedbackSubmissionResult(transaction: .failed(error.localizedDescription))
            )
        }
        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return FeedbackSubmissionResult(transaction: .stale)
        }

        do {
            try await repository.submitFeedback(
                recordId: input.recordId,
                choice: input.choice,
                freeText: input.freeText,
                exposureEventId: input.exposureEventId,
                accessToken: session.accessToken
            )
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: FeedbackSubmissionResult(transaction: .failed(error.localizedDescription))
            )
        }

        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return FeedbackSubmissionResult(transaction: .stale)
        }
        applyAccepted(input)
        return FeedbackSubmissionResult(transaction: .accepted)
    }

    private func isValid(_ input: FeedbackSubmissionInput) -> Bool {
        !input.recordId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !input.feedbackIdentity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isCurrent(
        _ context: FeedbackSubmissionUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        let current = contextProvider()
        return resetGeneration == expectedResetGeneration
            && current.isSignedIn
            && current.userId == context.userId
            && current.generation == context.generation
    }

    private func currentOrStale(
        _ context: FeedbackSubmissionUserContext,
        expectedResetGeneration: Int,
        result: FeedbackSubmissionResult
    ) -> FeedbackSubmissionResult {
        isCurrent(context, expectedResetGeneration: expectedResetGeneration)
            ? result
            : FeedbackSubmissionResult(transaction: .stale)
    }
}
