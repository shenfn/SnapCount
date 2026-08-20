import Foundation

struct AccountManagementSaveCommand: Hashable {
    let accountId: String?
    let name: String
    let type: NativeAccountType
    let institution: String
    let last4: String
    let initialBalance: Double
    let billDay: Int?
    let paymentDueDay: Int?
    let autoDebitAccountId: String?
    let autoConfirmRepayment: Bool
    let isDefaultExpense: Bool
    let isDefaultIncome: Bool

    var validationMessage: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "请输入账户名称" }
        guard trimmedName.count <= 30 else { return "账户名称最多 30 个字" }
        guard last4.isEmpty || last4.range(of: #"^\d{4}$"#, options: .regularExpression) != nil else {
            return "尾号必须是 4 位数字"
        }
        guard initialBalance.isFinite, initialBalance >= 0 else {
            return "初始余额必须是非负数字"
        }
        if let billDay, !(1...31).contains(billDay) { return "账单日必须是 1-31 之间的整数" }
        if let paymentDueDay, !(1...31).contains(paymentDueDay) { return "还款日必须是 1-31 之间的整数" }
        return nil
    }
}

enum AccountManagementActionCommand: Hashable {
    case save(AccountManagementSaveCommand)
    case setArchived(accountId: String, archived: Bool)

    var accountId: String? {
        switch self {
        case .save(let command): return command.accountId
        case .setArchived(let accountId, _): return accountId
        }
    }
}

struct AccountManagementUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
}

enum AccountManagementActionRejection: String, Equatable {
    case unauthenticated
    case invalidInput = "invalid_input"
}

enum AccountManagementActionConflict: String, Equatable {
    case accountCommandConflict = "account_command_conflict"
}

enum AccountManagementActionTransaction: Equatable {
    case accepted(NativeAccount)
    case rejected(AccountManagementActionRejection)
    case conflict(AccountManagementActionConflict)
    case failed(String)
    case stale

    var acceptedAccount: NativeAccount? {
        guard case .accepted(let account) = self else { return nil }
        return account
    }

    var failureReason: String? {
        guard case .failed(let reason) = self else { return nil }
        return reason
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.accepted(let left), .accepted(let right)):
            return left.id == right.id
                && left.isArchived == right.isArchived
                && left.isDefaultExpense == right.isDefaultExpense
                && left.isDefaultIncome == right.isDefaultIncome
        case (.rejected(let left), .rejected(let right)): return left == right
        case (.conflict(let left), .conflict(let right)): return left == right
        case (.failed(let left), .failed(let right)): return left == right
        case (.stale, .stale): return true
        default: return false
        }
    }
}

enum AccountManagementActionRefresh: Equatable {
    case notStarted
    case succeeded
    case failed(String)
}

struct AccountManagementActionResult {
    let transaction: AccountManagementActionTransaction
    let refresh: AccountManagementActionRefresh

    static func rejected(_ reason: AccountManagementActionRejection) -> Self {
        Self(transaction: .rejected(reason), refresh: .notStarted)
    }

    static func conflict(_ reason: AccountManagementActionConflict) -> Self {
        Self(transaction: .conflict(reason), refresh: .notStarted)
    }

    static var stale: Self {
        Self(transaction: .stale, refresh: .notStarted)
    }
}

@MainActor
final class AccountManagementActionUseCase {
    typealias ContextProvider = () -> AccountManagementUserContext
    typealias ApplyAccepted = (NativeAccount) -> Void
    typealias Refresh = (_ accountId: String) async throws -> Void

    private struct Identity: Hashable {
        let userId: String
        let accountKey: String
    }

    private struct InFlightAction {
        let token: UUID
        let command: AccountManagementActionCommand
        let task: Task<AccountManagementActionResult, Never>
    }

    private let repository: AccountManagementRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private let applyAccepted: ApplyAccepted
    private let refresh: Refresh
    private var inFlight: [Identity: InFlightAction] = [:]
    private var resetGeneration = 0

    init(
        repository: AccountManagementRepositoryProtocol,
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

    func perform(_ command: AccountManagementActionCommand) async -> AccountManagementActionResult {
        guard isValid(command) else { return .rejected(.invalidInput) }

        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .rejected(.unauthenticated)
        }

        let identity = Identity(
            userId: context.userId,
            accountKey: command.accountId ?? "create"
        )
        if let existing = inFlight[identity] {
            guard existing.command == command else {
                return .conflict(.accountCommandConflict)
            }
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return AccountManagementActionResult.stale }
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
        _ command: AccountManagementActionCommand,
        context: AccountManagementUserContext,
        expectedResetGeneration: Int
    ) async -> AccountManagementActionResult {
        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return AccountManagementActionResult(
                transaction: .failed(error.localizedDescription),
                refresh: .notStarted
            )
        }

        guard session.user.id == context.userId,
              isCurrent(context, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        let account: NativeAccount
        do {
            switch command {
            case .save(let saveCommand):
                account = try await repository.saveAccount(saveCommand, accessToken: session.accessToken)
            case .setArchived(let accountId, let archived):
                account = try await repository.setAccountArchived(
                    accountId: accountId,
                    archived: archived,
                    accessToken: session.accessToken
                )
            }
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return AccountManagementActionResult(
                transaction: .failed(error.localizedDescription),
                refresh: .notStarted
            )
        }

        guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
        applyAccepted(account)

        do {
            try await refresh(account.id)
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return AccountManagementActionResult(
                transaction: .accepted(account),
                refresh: .succeeded
            )
        } catch {
            guard isCurrent(context, expectedResetGeneration: expectedResetGeneration) else { return .stale }
            return AccountManagementActionResult(
                transaction: .accepted(account),
                refresh: .failed(error.localizedDescription)
            )
        }
    }

    private func isValid(_ command: AccountManagementActionCommand) -> Bool {
        switch command {
        case .save(let saveCommand):
            return saveCommand.validationMessage == nil
        case .setArchived(let accountId, _):
            return !accountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func isCurrent(
        _ expected: AccountManagementUserContext,
        expectedResetGeneration: Int
    ) -> Bool {
        guard expectedResetGeneration == resetGeneration else { return false }
        let current = contextProvider()
        return current.isSignedIn
            && current.userId == expected.userId
            && current.generation == expected.generation
    }
}
