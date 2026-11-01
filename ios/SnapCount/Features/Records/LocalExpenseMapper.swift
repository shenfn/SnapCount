import Foundation

enum LocalExpenseMapper {
    static let allowedAccountKinds: Set<String> = ["cash", "wallet_balance", "debit_card", "credit_card", "credit_line", "other"]

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

    static func amountMinor(from value: AnyCodable?) throws -> Int64 {
        guard let value else { throw LocalDataError.invalidAmount }
        let text: String
        switch value.value {
        case let string as String:
            text = string
        case is Bool:
            throw LocalDataError.invalidAmount
        case let number as NSNumber:
            text = number.stringValue
        case let int as Int:
            text = String(int)
        case let int64 as Int64:
            text = String(int64)
        case let double as Double:
            text = String(double)
        default:
            throw LocalDataError.invalidAmount
        }
        let normalized = text
            .replacingOccurrences(of: ",", with: "")
        guard let range = normalized.range(of: #"[-+]?\d+(?:\.\d+)?"#, options: .regularExpression) else {
            throw LocalDataError.invalidAmount
        }
        return try amountMinor(String(normalized[range]))
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

    static func nonnegativeAmountMinor(_ text: String) throws -> Int64 {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0 else {
            throw LocalDataError.invalidAmount
        }
        var scaled = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        guard rounded >= 0, rounded <= Decimal(Int64.max) else { throw LocalDataError.invalidAmount }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
