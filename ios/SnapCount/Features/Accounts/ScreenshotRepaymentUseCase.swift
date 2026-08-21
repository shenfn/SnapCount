import Foundation

protocol ScreenshotRepaymentRepositoryProtocol {
    func confirmStagingRepayment(
        id: String,
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        note: String,
        accessToken: String
    ) async throws -> NativeRepaymentCycle
}

struct ScreenshotRepaymentCommand: Hashable {
    let stagingId: String
    let cycleId: String
    let paidAmount: Double
    let debitAccountId: String?
    let note: String

    init(
        stagingId: String,
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String? = nil,
        note: String = "根据还款截图确认"
    ) {
        self.stagingId = stagingId
        self.cycleId = cycleId
        self.paidAmount = paidAmount
        self.debitAccountId = debitAccountId
        self.note = note
    }
}

struct ScreenshotRepaymentUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum ScreenshotRepaymentRejection: String, Equatable {
    case unauthenticated
    case invalidInput = "invalid_input"
}

enum ScreenshotRepaymentConflict: String, Equatable {
    case screenshotRepaymentConflict = "screenshot_repayment_conflict"
}

enum ScreenshotRepaymentTransaction: Equatable {
    case accepted
    case rejected(ScreenshotRepaymentRejection)
    case conflict(ScreenshotRepaymentConflict)
    case failed(String)
    case stale
}

enum ScreenshotRepaymentRefresh: Equatable {
    case notStarted
    case succeeded
    case failed(String)
}

struct ScreenshotRepaymentResult {
    let transaction: ScreenshotRepaymentTransaction
    let cycle: NativeRepaymentCycle?
    let refresh: ScreenshotRepaymentRefresh

    static func rejected(_ reason: ScreenshotRepaymentRejection) -> Self {
        Self(transaction: .rejected(reason), cycle: nil, refresh: .notStarted)
    }

    static func conflict(_ reason: ScreenshotRepaymentConflict) -> Self {
        Self(transaction: .conflict(reason), cycle: nil, refresh: .notStarted)
    }

    static var stale: Self {
        Self(transaction: .stale, cycle: nil, refresh: .notStarted)
    }
}

@MainActor
final class ScreenshotRepaymentUseCase {
    typealias ContextProvider = () -> ScreenshotRepaymentUserContext
    typealias AcceptedHook = (NativeRepaymentCycle) async -> Void
    typealias RefreshHook = (NativeRepaymentCycle) async throws -> Void

    private struct Identity: Hashable {
        let userId: String
        let stagingId: String
    }

    private struct InFlight {
        let signature: String
        let token: UUID
        let task: Task<ScreenshotRepaymentResult, Never>
    }

    private let repository: ScreenshotRepaymentRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private var inFlight: [Identity: InFlight] = [:]
    private var resetGeneration = 0

    init(
        repository: ScreenshotRepaymentRepositoryProtocol,
        sessionProvider: @escaping NativeSessionProvider,
        contextProvider: @escaping ContextProvider
    ) {
        self.repository = repository
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
    }

    func confirm(
        _ command: ScreenshotRepaymentCommand,
        onAccepted: AcceptedHook? = nil,
        refresh: RefreshHook? = nil
    ) async -> ScreenshotRepaymentResult {
        guard isValid(command) else { return .rejected(.invalidInput) }
        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .rejected(.unauthenticated)
        }

        let identity = Identity(userId: context.userId, stagingId: command.stagingId)
        let signature = "\(command.cycleId)|\(command.paidAmount)|\(command.debitAccountId ?? "")|\(command.note)"
        if let existing = inFlight[identity] {
            return existing.signature == signature
                ? await existing.task.value
                : .conflict(.screenshotRepaymentConflict)
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return ScreenshotRepaymentResult.stale }
            return await self.execute(
                command,
                context: context,
                expectedResetGeneration: expectedResetGeneration,
                onAccepted: onAccepted,
                refresh: refresh
            )
        }
        inFlight[identity] = InFlight(signature: signature, token: token, task: task)
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
        _ command: ScreenshotRepaymentCommand,
        context: ScreenshotRepaymentUserContext,
        expectedResetGeneration: Int,
        onAccepted: AcceptedHook?,
        refresh: RefreshHook?
    ) async -> ScreenshotRepaymentResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: ScreenshotRepaymentResult(
                    transaction: .failed(error.localizedDescription),
                    cycle: nil,
                    refresh: .notStarted
                )
            )
        }
        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let cycle: NativeRepaymentCycle
        do {
            cycle = try await repository.confirmStagingRepayment(
                id: command.stagingId,
                cycleId: command.cycleId,
                paidAmount: command.paidAmount,
                debitAccountId: command.debitAccountId,
                note: command.note,
                accessToken: session.accessToken
            )
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: ScreenshotRepaymentResult(
                    transaction: .failed(error.localizedDescription),
                    cycle: nil,
                    refresh: .notStarted
                )
            )
        }

        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        if let onAccepted {
            await onAccepted(cycle)
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        }

        guard let refresh else {
            return ScreenshotRepaymentResult(transaction: .accepted, cycle: cycle, refresh: .notStarted)
        }
        do {
            try await refresh(cycle)
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return ScreenshotRepaymentResult(transaction: .accepted, cycle: cycle, refresh: .succeeded)
        } catch {
            return currentOrStale(
                context,
                expectedResetGeneration: expectedResetGeneration,
                result: ScreenshotRepaymentResult(
                    transaction: .accepted,
                    cycle: cycle,
                    refresh: .failed(error.localizedDescription)
                )
            )
        }
    }

    private func currentOrStale(
        _ context: ScreenshotRepaymentUserContext,
        expectedResetGeneration: Int,
        result: ScreenshotRepaymentResult
    ) -> ScreenshotRepaymentResult {
        isCurrent(context, expectedResetGeneration: expectedResetGeneration) ? result : .stale
    }

    private func isValid(_ command: ScreenshotRepaymentCommand) -> Bool {
        !command.stagingId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !command.cycleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && command.paidAmount.isFinite
            && command.paidAmount > 0
    }

    private func isCurrent(
        _ expected: ScreenshotRepaymentUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        guard expectedResetGeneration == resetGeneration else { return false }
        let current = contextProvider()
        return current.isSignedIn
            && current.userId == expected.userId
            && current.generation == expected.generation
    }
}
