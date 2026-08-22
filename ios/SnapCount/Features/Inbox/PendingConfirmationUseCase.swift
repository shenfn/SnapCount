import Foundation

struct PendingConfirmationUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum PendingConfirmationRejection: Equatable {
    case unauthenticated
    case invalidInput
}

enum PendingConfirmationConflict: Equatable {
    case pendingConfirmationConflict
}

struct NativePendingConfirmationAccepted: Equatable {
    let pendingId: String
    let recordType: String
    let recordId: String
    let recordReference: String
    let idempotentRetry: Bool
}

enum PendingConfirmationTransaction: Equatable {
    case accepted(NativePendingConfirmationAccepted)
    case rejected(PendingConfirmationRejection)
    case conflict(PendingConfirmationConflict)
    case failed(String)
    case stale

    var accepted: NativePendingConfirmationAccepted? {
        guard case .accepted(let value) = self else { return nil }
        return value
    }
}

enum PendingConfirmationRefresh: Equatable {
    case notStarted
    case succeeded
    case failed(String)

    var failureMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

struct PendingConfirmationActionResult {
    let transaction: PendingConfirmationTransaction
    let refresh: PendingConfirmationRefresh

    static func rejected(_ reason: PendingConfirmationRejection) -> Self {
        Self(transaction: .rejected(reason), refresh: .notStarted)
    }

    static func conflict(_ reason: PendingConfirmationConflict) -> Self {
        Self(transaction: .conflict(reason), refresh: .notStarted)
    }

    static var stale: Self {
        Self(transaction: .stale, refresh: .notStarted)
    }
}

@MainActor
final class PendingConfirmationUseCase {
    typealias ContextProvider = () -> PendingConfirmationUserContext
    typealias ApplyAccepted = (NativePendingConfirmationAccepted) -> Void
    typealias Refresh = () async throws -> Void

    private struct InFlight {
        let signature: String
        let token: UUID
        let task: Task<PendingConfirmationActionResult, Never>
    }

    private let repository: PendingConfirmationRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private let applyAccepted: ApplyAccepted
    private let refresh: Refresh
    private var inFlight: [String: InFlight] = [:]
    private var resetGeneration = 0

    init(
        repository: PendingConfirmationRepositoryProtocol,
        sessionProvider: @escaping NativeSessionProvider,
        contextProvider: @escaping ContextProvider,
        applyAccepted: @escaping ApplyAccepted = { _ in },
        refresh: @escaping Refresh = {}
    ) {
        self.repository = repository
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
        self.applyAccepted = applyAccepted
        self.refresh = refresh
    }

    func perform(_ draft: NativePendingResolutionDraft) async -> PendingConfirmationActionResult {
        guard isValid(draft) else { return .rejected(.invalidInput) }
        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .rejected(.unauthenticated)
        }

        let identity = draft.pendingId
        let signature = signature(for: draft)
        if let existing = inFlight[identity] {
            guard existing.signature == signature else {
                return .conflict(.pendingConfirmationConflict)
            }
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return PendingConfirmationActionResult.stale }
            return await self.execute(
                draft,
                context: context,
                expectedResetGeneration: expectedResetGeneration
            )
        }
        inFlight[identity] = InFlight(signature: signature, token: token, task: task)
        let result = await task.value
        if inFlight[identity]?.token == token { inFlight.removeValue(forKey: identity) }
        return result
    }

    func reset() {
        resetGeneration += 1
        inFlight.removeAll()
    }

    private func execute(
        _ draft: NativePendingResolutionDraft,
        context: PendingConfirmationUserContext,
        expectedResetGeneration: Int
    ) async -> PendingConfirmationActionResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: PendingConfirmationActionResult(
                    transaction: .failed(error.localizedDescription),
                    refresh: .notStarted
                )
            )
        }
        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let result: NativePendingConfirmationResult
        do {
            result = try await repository.confirmPending(draft, accessToken: session.accessToken)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: PendingConfirmationActionResult(
                    transaction: .failed(error.localizedDescription),
                    refresh: .notStarted
                )
            )
        }

        let accepted = NativePendingConfirmationAccepted(
            pendingId: draft.pendingId,
            recordType: result.recordType,
            recordId: result.recordId,
            recordReference: result.recordReference,
            idempotentRetry: result.idempotentRetry
        )
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        applyAccepted(accepted)
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        do {
            try await refresh()
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return PendingConfirmationActionResult(transaction: .accepted(accepted), refresh: .succeeded)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: PendingConfirmationActionResult(
                    transaction: .accepted(accepted),
                    refresh: .failed(error.localizedDescription)
                )
            )
        }
    }

    private func isValid(_ draft: NativePendingResolutionDraft) -> Bool {
        !draft.pendingId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.validationMessage == nil
    }

    private func signature(for draft: NativePendingResolutionDraft) -> String {
        [
            draft.pendingId,
            draft.kind.rawValue,
            draft.amountText,
            draft.merchantOrSourceName,
            draft.platform,
            draft.category,
            draft.paymentMethod,
            draft.incomeCategory,
            draft.accountId ?? ""
        ].joined(separator: "|")
    }

    private func isCurrent(
        _ context: PendingConfirmationUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        let current = contextProvider()
        return resetGeneration == expectedResetGeneration
            && current.userId == context.userId
            && current.generation == context.generation
            && current.isSignedIn
    }

    private func currentOrStale(
        _ context: PendingConfirmationUserContext,
        expectedResetGeneration: Int,
        result: PendingConfirmationActionResult
    ) -> PendingConfirmationActionResult {
        isCurrent(context, expectedResetGeneration: expectedResetGeneration) ? result : .stale
    }
}
