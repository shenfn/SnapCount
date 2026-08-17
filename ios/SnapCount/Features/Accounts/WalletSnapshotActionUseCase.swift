import Foundation

enum WalletSnapshotActionOperation: String, Hashable {
    case create
    case link
}

struct WalletSnapshotActionCommand: Hashable {
    let operation: WalletSnapshotActionOperation
    let recordId: String
    let accountId: String?

    static func create(recordId: String) -> Self {
        Self(operation: .create, recordId: recordId, accountId: nil)
    }

    static func link(recordId: String, accountId: String) -> Self {
        Self(operation: .link, recordId: recordId, accountId: accountId)
    }
}

struct WalletSnapshotActionUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum WalletSnapshotActionRejection: String, Equatable {
    case unauthenticated
    case invalidInput = "invalid_input"
}

enum WalletSnapshotActionConflict: String, Equatable {
    case walletSnapshotBusy = "wallet_snapshot_busy"
    case walletSnapshotConflict = "wallet_snapshot_conflict"
}

enum WalletSnapshotActionStaleReason: String, Equatable {
    case sessionChanged = "session_changed"
}

enum WalletSnapshotActionTransaction: Equatable {
    case accepted(NativeWalletSnapshotOutcome)
    case rejected(WalletSnapshotActionRejection)
    case conflict(WalletSnapshotActionConflict)
    case failed(String)
    case stale(WalletSnapshotActionStaleReason)
}

enum WalletSnapshotActionRefresh: Equatable {
    case notStarted
    case succeeded
    case failed(String)
}

struct WalletSnapshotActionResult: Equatable {
    let transaction: WalletSnapshotActionTransaction
    let refresh: WalletSnapshotActionRefresh

    static func rejected(_ reason: WalletSnapshotActionRejection) -> Self {
        Self(transaction: .rejected(reason), refresh: .notStarted)
    }

    static func conflict(_ reason: WalletSnapshotActionConflict) -> Self {
        Self(transaction: .conflict(reason), refresh: .notStarted)
    }

    static var stale: Self {
        Self(transaction: .stale(.sessionChanged), refresh: .notStarted)
    }
}

@MainActor
final class WalletSnapshotActionUseCase {
    typealias ContextProvider = () -> WalletSnapshotActionUserContext
    typealias Refresh = () async throws -> Void

    private struct Identity: Hashable {
        let userId: String
        let recordId: String
    }

    private struct InFlightAction {
        let token: UUID
        let command: WalletSnapshotActionCommand
        let task: Task<WalletSnapshotActionResult, Never>
    }

    private let repository: WalletSnapshotRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private let refresh: Refresh
    private var inFlight: [Identity: InFlightAction] = [:]
    private var resetGeneration = 0

    init(
        repository: WalletSnapshotRepositoryProtocol,
        sessionProvider: @escaping NativeSessionProvider,
        contextProvider: @escaping ContextProvider,
        refresh: @escaping Refresh
    ) {
        self.repository = repository
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
        self.refresh = refresh
    }

    func perform(
        _ command: WalletSnapshotActionCommand,
        snapshot: NativeWalletSnapshot,
        account: NativeAccount? = nil
    ) async -> WalletSnapshotActionResult {
        guard isValid(command, snapshot: snapshot, account: account) else {
            return .rejected(.invalidInput)
        }

        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .rejected(.unauthenticated)
        }

        let normalizedRecordId = command.recordId.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = Identity(userId: context.userId, recordId: normalizedRecordId)
        if let existing = inFlight[identity] {
            guard existing.command == command else {
                return .conflict(.walletSnapshotConflict)
            }
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return WalletSnapshotActionResult.stale }
            return await self.execute(
                command,
                snapshot: snapshot,
                account: account,
                context: context,
                expectedResetGeneration: expectedResetGeneration
            )
        }
        inFlight[identity] = InFlightAction(token: token, command: command, task: task)

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
        _ command: WalletSnapshotActionCommand,
        snapshot: NativeWalletSnapshot,
        account: NativeAccount?,
        context: WalletSnapshotActionUserContext,
        expectedResetGeneration: Int
    ) async -> WalletSnapshotActionResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return .stale
            }
            return WalletSnapshotActionResult(
                transaction: .failed(error.localizedDescription),
                refresh: .notStarted
            )
        }

        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        let repositoryResult: NativeWalletSnapshotLinkResult
        do {
            switch command.operation {
            case .create:
                repositoryResult = try await repository.createAccount(
                    from: snapshot,
                    userId: session.user.id,
                    accessToken: session.accessToken
                )
            case .link:
                guard let account else { return .rejected(.invalidInput) }
                repositoryResult = try await repository.link(
                    snapshot,
                    to: account,
                    userId: session.user.id,
                    accessToken: session.accessToken
                )
            }
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return .stale
            }
            return WalletSnapshotActionResult(
                transaction: .failed(error.localizedDescription),
                refresh: .notStarted
            )
        }

        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        do {
            try await refresh()
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return .stale
            }
            return WalletSnapshotActionResult(
                transaction: .accepted(repositoryResult.outcome),
                refresh: .succeeded
            )
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return .stale
            }
            return WalletSnapshotActionResult(
                transaction: .accepted(repositoryResult.outcome),
                refresh: .failed(error.localizedDescription)
            )
        }
    }

    private func isValid(
        _ command: WalletSnapshotActionCommand,
        snapshot: NativeWalletSnapshot,
        account: NativeAccount?
    ) -> Bool {
        let recordId = command.recordId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recordId.isEmpty,
              recordId == snapshot.id.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }

        switch command.operation {
        case .create:
            return command.accountId == nil && account == nil
        case .link:
            guard let accountId = command.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !accountId.isEmpty,
                  let account else {
                return false
            }
            return account.id == accountId
        }
    }

    private func isCurrent(
        _ expected: WalletSnapshotActionUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        guard expectedResetGeneration == resetGeneration else { return false }
        let current = contextProvider()
        return current.isSignedIn
            && current.userId == expected.userId
            && current.generation == expected.generation
    }
}
