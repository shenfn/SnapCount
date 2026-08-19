import Foundation

enum RepaymentActionCommand: Hashable {
    case confirm(
        cycleId: String,
        accountId: String,
        paidAmount: Double,
        debitAccountId: String?,
        status: NativeRepaymentStatus,
        note: String
    )
    case revoke(paymentId: String, cycleId: String, accountId: String)

    var cycleId: String {
        switch self {
        case .confirm(let cycleId, _, _, _, _, _), .revoke(_, let cycleId, _):
            return cycleId
        }
    }

    var accountId: String {
        switch self {
        case .confirm(_, let accountId, _, _, _, _), .revoke(_, _, let accountId):
            return accountId
        }
    }
}

struct RepaymentActionUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum RepaymentActionRejection: String, Equatable {
    case unauthenticated
    case invalidInput = "invalid_input"
}

enum RepaymentActionConflict: String, Equatable {
    case repaymentConflict = "repayment_conflict"
}

enum RepaymentActionOperation: String, Equatable {
    case confirm
    case revoke
}

struct RepaymentActionAccepted {
    let operation: RepaymentActionOperation
    let cycle: NativeRepaymentCycle
    let recordedDebit: Bool
}

enum RepaymentActionTransaction {
    case accepted(RepaymentActionAccepted)
    case rejected(RepaymentActionRejection)
    case conflict(RepaymentActionConflict)
    case failed(String)
    case stale
}

enum RepaymentActionRefresh: Equatable {
    case notStarted
    case succeeded
    case failed(String)
}

struct RepaymentActionResult {
    let transaction: RepaymentActionTransaction
    let refresh: RepaymentActionRefresh

    static func rejected(_ reason: RepaymentActionRejection) -> Self {
        Self(transaction: .rejected(reason), refresh: .notStarted)
    }

    static func conflict(_ reason: RepaymentActionConflict) -> Self {
        Self(transaction: .conflict(reason), refresh: .notStarted)
    }

    static var stale: Self {
        Self(transaction: .stale, refresh: .notStarted)
    }
}

@MainActor
final class RepaymentActionUseCase {
    typealias ContextProvider = () -> RepaymentActionUserContext
    typealias ApplyAccepted = (NativeRepaymentCycle) -> Void
    typealias Refresh = (_ accountId: String) async throws -> Void

    private struct Identity: Hashable {
        let userId: String
        let cycleId: String
    }

    private struct InFlightAction {
        let token: UUID
        let command: RepaymentActionCommand
        let task: Task<RepaymentActionResult, Never>
    }

    private let repository: AccountRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private let applyAccepted: ApplyAccepted
    private let refresh: Refresh
    private var inFlight: [Identity: InFlightAction] = [:]
    private var resetGeneration = 0

    init(
        repository: AccountRepositoryProtocol,
        sessionProvider: @escaping NativeSessionProvider,
        contextProvider: @escaping ContextProvider,
        applyAccepted: @escaping ApplyAccepted = { _ in },
        refresh: @escaping Refresh
    ) {
        self.repository = repository
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
        self.applyAccepted = applyAccepted
        self.refresh = refresh
    }

    func perform(_ command: RepaymentActionCommand) async -> RepaymentActionResult {
        guard isValid(command) else { return .rejected(.invalidInput) }

        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .rejected(.unauthenticated)
        }

        let identity = Identity(
            userId: context.userId,
            cycleId: command.cycleId.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let existing = inFlight[identity] {
            guard existing.command == command else {
                return .conflict(.repaymentConflict)
            }
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return RepaymentActionResult.stale }
            return await self.execute(
                command,
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
        _ command: RepaymentActionCommand,
        context: RepaymentActionUserContext,
        expectedResetGeneration: Int
    ) async -> RepaymentActionResult {
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
            return RepaymentActionResult(
                transaction: .failed(error.localizedDescription),
                refresh: .notStarted
            )
        }

        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        let accepted: RepaymentActionAccepted
        do {
            switch command {
            case .confirm(let cycleId, _, let paidAmount, let debitAccountId, let status, let note):
                let cycle = try await repository.confirmRepayment(
                    cycleId: cycleId,
                    paidAmount: paidAmount,
                    debitAccountId: debitAccountId,
                    status: status,
                    note: note,
                    accessToken: session.accessToken
                )
                accepted = RepaymentActionAccepted(
                    operation: .confirm,
                    cycle: cycle,
                    recordedDebit: debitAccountId != nil
                )
            case .revoke(let paymentId, _, _):
                guard let cycle = try await repository.revokePayment(
                    paymentId: paymentId,
                    accessToken: session.accessToken
                ) else {
                    throw SupabaseRemoteError.requestFailed("repayment_cycle_missing")
                }
                accepted = RepaymentActionAccepted(operation: .revoke, cycle: cycle, recordedDebit: false)
            }
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return .stale
            }
            return RepaymentActionResult(
                transaction: .failed(error.localizedDescription),
                refresh: .notStarted
            )
        }

        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }
        applyAccepted(accepted.cycle)

        do {
            try await refresh(command.accountId)
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return .stale
            }
            return RepaymentActionResult(
                transaction: .accepted(accepted),
                refresh: .succeeded
            )
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
                return .stale
            }
            return RepaymentActionResult(
                transaction: .accepted(accepted),
                refresh: .failed(error.localizedDescription)
            )
        }
    }

    private func isValid(_ command: RepaymentActionCommand) -> Bool {
        let cycleId = command.cycleId.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountId = command.accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cycleId.isEmpty, !accountId.isEmpty else { return false }

        switch command {
        case .confirm(_, _, let paidAmount, _, _, _):
            return paidAmount.isFinite && paidAmount > 0
        case .revoke(let paymentId, _, _):
            return !paymentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func isCurrent(
        _ expected: RepaymentActionUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        guard expectedResetGeneration == resetGeneration else { return false }
        let current = contextProvider()
        return current.isSignedIn
            && current.userId == expected.userId
            && current.generation == expected.generation
    }
}
