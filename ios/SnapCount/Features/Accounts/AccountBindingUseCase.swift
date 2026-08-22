import Foundation

struct NativeAccountBindingResult: Equatable {
    let recordId: String
    let kind: NativeUnboundRecordKind
    let accountId: String
}

struct AccountBindingAccepted: Equatable {
    let result: NativeAccountBindingResult

    var recordId: String { result.recordId }
    var kind: NativeUnboundRecordKind { result.kind }
    var accountId: String { result.accountId }
}

enum AccountBindingActionRejection: String, Equatable {
    case unauthenticated
    case invalidInput = "invalid_input"
}

enum AccountBindingActionConflict: String, Equatable {
    case bindingConflict = "binding_conflict"
}

enum AccountBindingActionTransaction: Equatable {
    case accepted(AccountBindingAccepted)
    case rejected(AccountBindingActionRejection)
    case conflict(AccountBindingActionConflict)
    case failed(String)
    case stale

    var accepted: AccountBindingAccepted? {
        guard case .accepted(let value) = self else { return nil }
        return value
    }
}

enum AccountBindingActionRefresh: Equatable {
    case notStarted
    case succeeded
    case failed(String)

    var failureMessage: String? {
        guard case .failed(let message) = self else { return nil }
        return message
    }
}

struct AccountBindingActionResult {
    let transaction: AccountBindingActionTransaction
    let refresh: AccountBindingActionRefresh

    static func rejected(_ reason: AccountBindingActionRejection) -> Self {
        Self(transaction: .rejected(reason), refresh: .notStarted)
    }

    static func conflict(_ reason: AccountBindingActionConflict) -> Self {
        Self(transaction: .conflict(reason), refresh: .notStarted)
    }

    static var stale: Self {
        Self(transaction: .stale, refresh: .notStarted)
    }
}

struct AccountBindingItemResult {
    let recordId: String
    let kind: NativeUnboundRecordKind
    let accountId: String
    let transaction: AccountBindingActionTransaction
}

enum AccountBindingBatchStatus: Equatable {
    case allSucceeded
    case partial
    case failed
    case stale
}

struct AccountBindingBatchResult {
    let status: AccountBindingBatchStatus
    let items: [AccountBindingItemResult]
    let successCount: Int
    let failedCount: Int
    let refresh: AccountBindingActionRefresh
}

struct AccountBindingUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

@MainActor
final class AccountBindingUseCase {
    typealias ContextProvider = () -> AccountBindingUserContext
    typealias ApplyAccepted = (NativeAccountBindingResult) -> Void
    typealias Refresh = () async throws -> Void

    private struct Identity: Hashable {
        let userId: String
        let kind: NativeUnboundRecordKind
        let recordId: String
    }

    private struct InFlight {
        let accountId: String
        let token: UUID
        let task: Task<AccountBindingActionResult, Never>
    }

    private let repository: UnboundRecordRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private let applyAccepted: ApplyAccepted
    private let refresh: Refresh
    private var inFlight: [Identity: InFlight] = [:]
    private var resetGeneration = 0

    init(
        repository: UnboundRecordRepositoryProtocol,
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

    func bind(_ record: NativeUnboundRecord, accountId: String) async -> AccountBindingActionResult {
        guard isValid(record: record, accountId: accountId) else { return .rejected(.invalidInput) }
        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else { return .rejected(.unauthenticated) }

        let identity = Identity(userId: context.userId, kind: record.kind, recordId: record.id)
        if let existing = inFlight[identity] {
            guard existing.accountId == accountId else { return .conflict(.bindingConflict) }
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return .stale }
            return await self.execute(
                record: record,
                accountId: accountId,
                context: context,
                expectedResetGeneration: expectedResetGeneration,
                refreshAfterAccepted: true
            )
        }
        inFlight[identity] = InFlight(accountId: accountId, token: token, task: task)
        let result = await task.value
        if inFlight[identity]?.token == token { inFlight.removeValue(forKey: identity) }
        return result
    }

    func bindBatch(_ candidates: [NativeUnboundBindingCandidate]) async -> AccountBindingBatchResult {
        guard !candidates.isEmpty else {
            return AccountBindingBatchResult(status: .failed, items: [], successCount: 0, failedCount: 0, refresh: .notStarted)
        }
        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return AccountBindingBatchResult(status: .failed, items: [], successCount: 0, failedCount: candidates.count, refresh: .notStarted)
        }
        let expectedResetGeneration = resetGeneration
        do {
            let session = try await sessionProvider(false)
            guard session.user.id == context.userId,
                  isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return AccountBindingBatchResult(status: .stale, items: [], successCount: 0, failedCount: 0, refresh: .notStarted)
            }
        } catch {
            return AccountBindingBatchResult(status: .failed, items: [], successCount: 0, failedCount: candidates.count, refresh: .notStarted)
        }
        var items: [AccountBindingItemResult] = []

        for candidate in candidates {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return AccountBindingBatchResult(status: .stale, items: items, successCount: items.successCount, failedCount: items.failureCount, refresh: .notStarted)
            }
            let result = await execute(
                record: candidate.record,
                accountId: candidate.recommendation.account.id,
                context: context,
                expectedResetGeneration: expectedResetGeneration,
                refreshAfterAccepted: false
            )
            if case .stale = result.transaction {
                return AccountBindingBatchResult(status: .stale, items: items, successCount: items.successCount, failedCount: items.failureCount, refresh: .notStarted)
            }
            items.append(AccountBindingItemResult(
                recordId: candidate.record.id,
                kind: candidate.record.kind,
                accountId: candidate.recommendation.account.id,
                transaction: result.transaction
            ))
        }

        let successCount = items.successCount
        let failedCount = items.failureCount
        guard successCount > 0 else {
            return AccountBindingBatchResult(status: .failed, items: items, successCount: 0, failedCount: failedCount, refresh: .notStarted)
        }
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return AccountBindingBatchResult(status: .stale, items: items, successCount: successCount, failedCount: failedCount, refresh: .notStarted)
        }
        do {
            try await refresh()
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return AccountBindingBatchResult(status: .stale, items: items, successCount: successCount, failedCount: failedCount, refresh: .notStarted)
            }
            return AccountBindingBatchResult(
                status: failedCount == 0 ? .allSucceeded : .partial,
                items: items,
                successCount: successCount,
                failedCount: failedCount,
                refresh: .succeeded
            )
        } catch {
            return AccountBindingBatchResult(
                status: failedCount == 0 ? .allSucceeded : .partial,
                items: items,
                successCount: successCount,
                failedCount: failedCount,
                refresh: .failed(error.localizedDescription)
            )
        }
    }

    func reset() {
        resetGeneration += 1
        inFlight.removeAll()
    }

    private func execute(
        record: NativeUnboundRecord,
        accountId: String,
        context: AccountBindingUserContext,
        expectedResetGeneration: Int,
        refreshAfterAccepted: Bool
    ) async -> AccountBindingActionResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            return currentOrStale(context, expectedResetGeneration: expectedResetGeneration, result: AccountBindingActionResult(transaction: .failed(error.localizedDescription), refresh: .notStarted))
        }
        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let accepted: NativeAccountBindingResult
        do {
            accepted = try await repository.bind(record, accountId: accountId, accessToken: session.accessToken)
        } catch {
            return currentOrStale(context, expectedResetGeneration: expectedResetGeneration, result: AccountBindingActionResult(transaction: .failed(error.localizedDescription), refresh: .notStarted))
        }
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        applyAccepted(accepted)
        guard !refreshAfterAccepted else {
            do {
                try await refresh()
                guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
                return AccountBindingActionResult(transaction: .accepted(AccountBindingAccepted(result: accepted)), refresh: .succeeded)
            } catch {
                return currentOrStale(context, expectedResetGeneration: expectedResetGeneration, result: AccountBindingActionResult(transaction: .accepted(AccountBindingAccepted(result: accepted)), refresh: .failed(error.localizedDescription)))
            }
        }
        return AccountBindingActionResult(transaction: .accepted(AccountBindingAccepted(result: accepted)), refresh: .notStarted)
    }

    private func currentOrStale(
        _ context: AccountBindingUserContext,
        expectedResetGeneration: Int,
        result: AccountBindingActionResult
    ) -> AccountBindingActionResult {
        isCurrent(context, expectedResetGeneration: expectedResetGeneration) ? result : .stale
    }

    private func isValid(record: NativeUnboundRecord, accountId: String) -> Bool {
        !record.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && record.amount.isFinite
            && !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isCurrent(_ expected: AccountBindingUserContext, expectedResetGeneration: Int) -> Bool {
        guard expectedResetGeneration == resetGeneration else { return false }
        let current = contextProvider()
        return current.isSignedIn
            && current.userId == expected.userId
            && current.generation == expected.generation
    }
}

private extension Array where Element == AccountBindingItemResult {
    var successCount: Int { filter { $0.transaction.accepted != nil }.count }
    var failureCount: Int { count - successCount }
}
