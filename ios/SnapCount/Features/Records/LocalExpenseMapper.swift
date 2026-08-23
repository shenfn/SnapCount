import Foundation

enum LocalExpenseMapper {
    static let allowedAccountKinds: Set<String> = ["cash", "wallet_balance", "debit_card"]

    static func createDraft(
        _ command: LocalExpenseCommand,
        profileID: UUID
    ) throws -> LocalExpenseDraft {
        LocalExpenseDraft(
            id: command.id,
            profileID: profileID,
            accountID: command.accountID,
            amountMinor: try amountMinor(command.amountText),
            currency: command.currency,
            merchantName: command.merchantName,
            platform: command.platform,
            category: command.category,
            paymentMethod: command.paymentMethod,
            transactionDate: command.transactionDate,
            transactionTime: command.transactionTime,
            note: command.note,
            createdAt: command.createdAt
        )
    }

    static func update(_ command: LocalExpenseUpdateCommand) throws -> LocalExpenseUpdate {
        LocalExpenseUpdate(
            id: command.id,
            expectedVersion: command.expectedVersion,
            accountID: command.accountID,
            amountMinor: try amountMinor(command.amountText),
            currency: command.currency,
            merchantName: command.merchantName,
            platform: command.platform,
            category: command.category,
            paymentMethod: command.paymentMethod,
            transactionDate: command.transactionDate,
            transactionTime: command.transactionTime,
            note: command.note,
            updatedAt: command.updatedAt
        )
    }

    static func amountMinor(_ text: String) throws -> Int64 {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal > 0 else {
            throw LocalDataError.invalidAmount
        }
        var scaled = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        guard rounded > 0,
              rounded <= Decimal(Int64.max) else {
            throw LocalDataError.invalidAmount
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    static func openingBalanceMinor(_ text: String) throws -> Int64 {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0 else {
            throw LocalDataError.invalidAmount
        }
        var scaled = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        guard rounded >= 0,
              rounded <= Decimal(Int64.max) else {
            throw LocalDataError.invalidAmount
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
