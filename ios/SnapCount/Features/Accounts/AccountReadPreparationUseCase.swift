import Foundation

protocol AccountReadPreparationRepositoryProtocol {
    func ensureRepaymentCycles(monthKey: String, accessToken: String) async throws
}

struct AccountReadPreparationUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum AccountReadPreparationRejection: String, Equatable {
    case unauthenticated
    case invalidInput = "invalid_input"
}

enum AccountReadPreparationTransaction: Equatable {
    case accepted
    case rejected(AccountReadPreparationRejection)
    case failed(String)
    case stale
}

struct AccountReadPreparationResult: Equatable {
    let transaction: AccountReadPreparationTransaction

    static func rejected(_ reason: AccountReadPreparationRejection) -> Self {
        Self(transaction: .rejected(reason))
    }

    static var accepted: Self { Self(transaction: .accepted) }
    static var stale: Self { Self(transaction: .stale) }
}

@MainActor
final class AccountReadPreparationUseCase {
    typealias ContextProvider = () -> AccountReadPreparationUserContext

    private struct Identity: Hashable {
        let userId: String
        let monthKey: String
    }

    private struct InFlightPreparation {
        let token: UUID
        let task: Task<AccountReadPreparationResult, Never>
    }

    private let repository: AccountReadPreparationRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private var inFlight: [Identity: InFlightPreparation] = [:]
    private var resetGeneration = 0

    init(
        repository: AccountReadPreparationRepositoryProtocol,
        sessionProvider: @escaping NativeSessionProvider,
        contextProvider: @escaping ContextProvider
    ) {
        self.repository = repository
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
    }

    func prepare(monthKey: String) async -> AccountReadPreparationResult {
        let normalizedMonthKey = monthKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedMonthKey.range(
            of: #"^\d{4}-(0[1-9]|1[0-2])$"#,
            options: .regularExpression
        ) != nil else {
            return .rejected(.invalidInput)
        }

        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .rejected(.unauthenticated)
        }

        let identity = Identity(userId: context.userId, monthKey: normalizedMonthKey)
        if let existing = inFlight[identity] {
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return .stale }
            return await self.execute(
                monthKey: normalizedMonthKey,
                context: context,
                expectedResetGeneration: expectedResetGeneration
            )
        }
        inFlight[identity] = InFlightPreparation(token: token, task: task)

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
        monthKey: String,
        context: AccountReadPreparationUserContext,
        expectedResetGeneration: Int
    ) async -> AccountReadPreparationResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return AccountReadPreparationResult(transaction: .failed(error.localizedDescription))
        }

        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }

        do {
            try await repository.ensureRepaymentCycles(monthKey: monthKey, accessToken: session.accessToken)
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return AccountReadPreparationResult(transaction: .failed(error.localizedDescription))
        }

        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        return .accepted
    }

    private func isCurrent(
        _ expected: AccountReadPreparationUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        guard expectedResetGeneration == resetGeneration else { return false }
        let current = contextProvider()
        return current.isSignedIn
            && current.userId == expected.userId
            && current.generation == expected.generation
    }
}
