import Foundation

enum StagingLifecycleActionKind: Equatable {
    case discard
    case retry
    case archive
}

enum StagingLifecycleCommand {
    case discard(recordId: String)
    case retry(recordId: String)
    case archive(record: NativeStagingRecord, domainKey: String)

    var recordId: String {
        switch self {
        case .discard(let recordId), .retry(let recordId): return recordId
        case .archive(let record, _): return record.id
        }
    }

    var action: StagingLifecycleActionKind {
        switch self {
        case .discard: return .discard
        case .retry: return .retry
        case .archive: return .archive
        }
    }

    var signature: String {
        switch self {
        case .discard(let recordId): return "discard|\(recordId)"
        case .retry(let recordId): return "retry|\(recordId)"
        case .archive(let record, let domainKey): return "archive|\(record.id)|\(domainKey)|\(record.archivePayload)"
        }
    }
}

struct StagingLifecycleUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum StagingLifecycleRejection: String, Equatable {
    case unauthenticated
    case invalidInput = "invalid_input"
}

enum StagingLifecycleConflict: String, Equatable {
    case stagingActionConflict = "staging_action_conflict"
}

struct NativeStagingLifecycleAccepted: Equatable {
    let action: StagingLifecycleActionKind
    let recordId: String
    let cleanupStatus: String?
    let cleanupQueued: Bool?
    let route: String?
    let displayText: String?
    let notificationText: String?
    let targetRecordId: String?
    let targetReference: String?
    let idempotentRetry: Bool?
}

enum StagingLifecycleTransaction: Equatable {
    case accepted(NativeStagingLifecycleAccepted)
    case rejected(StagingLifecycleRejection)
    case conflict(StagingLifecycleConflict)
    case failed(String)
    case stale

    var accepted: NativeStagingLifecycleAccepted? {
        guard case .accepted(let value) = self else { return nil }
        return value
    }
}

enum StagingLifecycleRefresh: Equatable {
    case notStarted
    case succeeded
    case failed(String)

    var failureMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

struct StagingLifecycleActionResult {
    let transaction: StagingLifecycleTransaction
    let refresh: StagingLifecycleRefresh

    static func rejected(_ reason: StagingLifecycleRejection) -> Self {
        Self(transaction: .rejected(reason), refresh: .notStarted)
    }

    static func conflict(_ reason: StagingLifecycleConflict) -> Self {
        Self(transaction: .conflict(reason), refresh: .notStarted)
    }

    static var stale: Self {
        Self(transaction: .stale, refresh: .notStarted)
    }
}

@MainActor
final class StagingLifecycleUseCase {
    typealias ContextProvider = () -> StagingLifecycleUserContext
    typealias ApplyAccepted = (NativeStagingLifecycleAccepted) -> Void
    typealias Refresh = () async throws -> Void

    private struct Identity: Hashable {
        let userId: String
        let recordId: String
    }

    private struct InFlight {
        let signature: String
        let token: UUID
        let task: Task<StagingLifecycleActionResult, Never>
    }

    private let repository: StagingLifecycleRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private let applyAccepted: ApplyAccepted
    private let refresh: Refresh
    private var inFlight: [Identity: InFlight] = [:]
    private var resetGeneration = 0

    init(
        repository: StagingLifecycleRepositoryProtocol,
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

    func perform(_ command: StagingLifecycleCommand) async -> StagingLifecycleActionResult {
        guard isValid(command) else { return .rejected(.invalidInput) }
        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .rejected(.unauthenticated)
        }

        let identity = Identity(userId: context.userId, recordId: command.recordId)
        if let existing = inFlight[identity] {
            guard existing.signature == command.signature else {
                return .conflict(.stagingActionConflict)
            }
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return StagingLifecycleActionResult.stale }
            return await self.execute(
                command,
                context: context,
                expectedResetGeneration: expectedResetGeneration
            )
        }
        inFlight[identity] = InFlight(signature: command.signature, token: token, task: task)
        let result = await task.value
        if inFlight[identity]?.token == token { inFlight.removeValue(forKey: identity) }
        return result
    }

    func reset() {
        resetGeneration += 1
        inFlight.removeAll()
    }

    private func execute(
        _ command: StagingLifecycleCommand,
        context: StagingLifecycleUserContext,
        expectedResetGeneration: Int
    ) async -> StagingLifecycleActionResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: StagingLifecycleActionResult(
                    transaction: .failed(error.localizedDescription),
                    refresh: .notStarted
                )
            )
        }
        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let accepted: NativeStagingLifecycleAccepted
        do {
            switch command {
            case .discard(let recordId):
                let result = try await repository.discard(id: recordId, accessToken: session.accessToken)
                accepted = NativeStagingLifecycleAccepted(
                    action: .discard,
                    recordId: result.recordId,
                    cleanupStatus: result.cleanupStatus,
                    cleanupQueued: result.cleanupQueued,
                    route: nil,
                    displayText: nil,
                    notificationText: nil,
                    targetRecordId: nil,
                    targetReference: nil,
                    idempotentRetry: nil
                )
            case .retry(let recordId):
                let result = try await repository.retry(id: recordId, accessToken: session.accessToken)
                accepted = NativeStagingLifecycleAccepted(
                    action: .retry,
                    recordId: result.recordId,
                    cleanupStatus: nil,
                    cleanupQueued: nil,
                    route: result.route,
                    displayText: result.displayText,
                    notificationText: result.notificationText,
                    targetRecordId: nil,
                    targetReference: nil,
                    idempotentRetry: nil
                )
            case .archive(let record, let domainKey):
                let result = try await repository.archive(record, domainKey: domainKey, accessToken: session.accessToken)
                accepted = NativeStagingLifecycleAccepted(
                    action: .archive,
                    recordId: result.recordId,
                    cleanupStatus: nil,
                    cleanupQueued: nil,
                    route: nil,
                    displayText: nil,
                    notificationText: nil,
                    targetRecordId: result.targetRecordId,
                    targetReference: result.targetReference,
                    idempotentRetry: result.idempotentRetry
                )
            }
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: StagingLifecycleActionResult(
                    transaction: .failed(error.localizedDescription),
                    refresh: .notStarted
                )
            )
        }

        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        applyAccepted(accepted)
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        do {
            try await refresh()
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return StagingLifecycleActionResult(transaction: .accepted(accepted), refresh: .succeeded)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: StagingLifecycleActionResult(
                    transaction: .accepted(accepted),
                    refresh: .failed(error.localizedDescription)
                )
            )
        }
    }

    private func isValid(_ command: StagingLifecycleCommand) -> Bool {
        guard !command.recordId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if case .archive(_, let domainKey) = command {
            return !domainKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    private func isCurrent(
        _ context: StagingLifecycleUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        let current = contextProvider()
        return resetGeneration == expectedResetGeneration
            && current.userId == context.userId
            && current.generation == context.generation
            && current.isSignedIn
    }

    private func currentOrStale(
        _ context: StagingLifecycleUserContext,
        expectedResetGeneration: Int,
        result: StagingLifecycleActionResult
    ) -> StagingLifecycleActionResult {
        isCurrent(context, expectedResetGeneration: expectedResetGeneration) ? result : .stale
    }
}
