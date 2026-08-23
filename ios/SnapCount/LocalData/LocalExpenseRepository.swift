import Foundation
import GRDB

protocol LocalExpenseRepositoryProtocol {
    func createProfile(id: UUID, createdAt: Date) throws -> LocalProfile
    func createAccount(_ draft: LocalAccountDraft) throws -> LocalAccount
    func createExpense(_ draft: LocalExpenseDraft, operationID: UUID) throws -> LocalExpense
    func expense(id: UUID) throws -> LocalExpense?
    func expenseCount() throws -> Int
    func accountEntryCount() throws -> Int
    func pendingOutboxOperations() throws -> [LocalOutboxOperation]
    func accountBalanceMinor(accountID: UUID) throws -> Int64
}

final class LocalExpenseRepository: LocalExpenseRepositoryProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) throws {
        self.database = database
    }

    func createProfile(id: UUID, createdAt: Date) throws -> LocalProfile {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_profiles (id, created_at, cloud_user_id, sync_enabled)
                    VALUES (?, ?, NULL, 0)
                    """,
                arguments: [id.uuidString, createdAt]
            )
        }
        return LocalProfile(id: id, createdAt: createdAt, cloudUserID: nil, syncEnabled: false)
    }

    func createAccount(_ draft: LocalAccountDraft) throws -> LocalAccount {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_accounts (
                        id, profile_id, name, kind, currency, opening_balance_minor, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    draft.id.uuidString,
                    draft.profileID.uuidString,
                    draft.name,
                    draft.kind,
                    draft.currency,
                    draft.openingBalanceMinor,
                    draft.createdAt
                ]
            )
        }
        return LocalAccount(
            id: draft.id,
            profileID: draft.profileID,
            name: draft.name,
            kind: draft.kind,
            currency: draft.currency,
            openingBalanceMinor: draft.openingBalanceMinor,
            createdAt: draft.createdAt
        )
    }

    func createExpense(_ draft: LocalExpenseDraft, operationID: UUID) throws -> LocalExpense {
        guard draft.amountMinor > 0 else { throw LocalDataError.invalidAmount }
        let localVersion: Int64 = 1
        let entryID = UUID()
        let payload = try Self.outboxPayload(draft: draft, localVersion: localVersion)

        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_expenses (
                        id, profile_id, account_id, amount_minor, currency, merchant_name,
                        platform, category, payment_method, transaction_date, transaction_time,
                        note, local_version, created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString,
                    draft.profileID.uuidString,
                    draft.accountID.uuidString,
                    draft.amountMinor,
                    draft.currency,
                    draft.merchantName,
                    draft.platform,
                    draft.category,
                    draft.paymentMethod,
                    draft.transactionDate,
                    draft.transactionTime,
                    draft.note,
                    localVersion,
                    draft.createdAt,
                    draft.createdAt
                ]
            )

            try db.execute(
                sql: """
                    INSERT INTO local_account_entries (
                        id, profile_id, account_id, direction, amount_minor, entry_kind,
                        source_kind, source_id, occurred_at, voided_at
                    ) VALUES (?, ?, ?, 'out', ?, 'expense', 'expense', ?, ?, NULL)
                    """,
                arguments: [
                    entryID.uuidString,
                    draft.profileID.uuidString,
                    draft.accountID.uuidString,
                    draft.amountMinor,
                    draft.id.uuidString,
                    draft.createdAt
                ]
            )

            try db.execute(
                sql: """
                    INSERT INTO local_outbox_operations (
                        operation_id, profile_id, aggregate_kind, aggregate_id, operation_kind,
                        aggregate_version, idempotency_key, payload_json, status, attempt_count,
                        next_attempt_at, last_error, created_at
                    ) VALUES (?, ?, 'expense', ?, 'upsert', ?, ?, ?, 'pending', 0, NULL, NULL, ?)
                    """,
                arguments: [
                    operationID.uuidString,
                    draft.profileID.uuidString,
                    draft.id.uuidString,
                    localVersion,
                    operationID.uuidString,
                    payload,
                    draft.createdAt
                ]
            )
        }

        return LocalExpense(
            id: draft.id,
            profileID: draft.profileID,
            accountID: draft.accountID,
            amountMinor: draft.amountMinor,
            currency: draft.currency,
            merchantName: draft.merchantName,
            platform: draft.platform,
            category: draft.category,
            paymentMethod: draft.paymentMethod,
            transactionDate: draft.transactionDate,
            transactionTime: draft.transactionTime,
            note: draft.note,
            localVersion: localVersion,
            createdAt: draft.createdAt,
            updatedAt: draft.createdAt
        )
    }

    func expense(id: UUID) throws -> LocalExpense? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM local_expenses
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try Self.expense(from: row)
        }
    }

    func expenseCount() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_expenses WHERE deleted_at IS NULL"
            ) ?? 0
        }
    }

    func accountEntryCount() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_account_entries WHERE voided_at IS NULL"
            ) ?? 0
        }
    }

    func pendingOutboxOperations() throws -> [LocalOutboxOperation] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT sequence, operation_id, profile_id, aggregate_kind, aggregate_id,
                           operation_kind, aggregate_version, idempotency_key, status,
                           attempt_count, created_at
                    FROM local_outbox_operations
                    WHERE status = 'pending'
                    ORDER BY sequence ASC
                    """
            ).map { try Self.outboxOperation(from: $0) }
        }
    }

    func accountBalanceMinor(accountID: UUID) throws -> Int64 {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT accounts.opening_balance_minor AS opening_balance_minor,
                           COALESCE(SUM(
                               CASE entries.direction
                                   WHEN 'in' THEN entries.amount_minor
                                   WHEN 'out' THEN -entries.amount_minor
                               END
                           ), 0) AS ledger_delta_minor
                    FROM local_accounts AS accounts
                    LEFT JOIN local_account_entries AS entries
                      ON entries.account_id = accounts.id
                     AND entries.voided_at IS NULL
                    WHERE accounts.id = ?
                    GROUP BY accounts.id
                    """,
                arguments: [accountID.uuidString]
            ) else {
                throw LocalDataError.invalidIdentifier
            }
            let openingBalance: Int64 = row["opening_balance_minor"]
            let ledgerDelta: Int64 = row["ledger_delta_minor"]
            return openingBalance + ledgerDelta
        }
    }

    private static func expense(from row: Row) throws -> LocalExpense {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let accountID = UUID(uuidString: row["account_id"]) else {
            throw LocalDataError.invalidRecord
        }
        return LocalExpense(
            id: id,
            profileID: profileID,
            accountID: accountID,
            amountMinor: row["amount_minor"],
            currency: row["currency"],
            merchantName: row["merchant_name"],
            platform: row["platform"],
            category: row["category"],
            paymentMethod: row["payment_method"],
            transactionDate: row["transaction_date"],
            transactionTime: row["transaction_time"],
            note: row["note"],
            localVersion: row["local_version"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"]
        )
    }

    private static func outboxOperation(from row: Row) throws -> LocalOutboxOperation {
        guard let operationID = UUID(uuidString: row["operation_id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let aggregateID = UUID(uuidString: row["aggregate_id"]) else {
            throw LocalDataError.invalidRecord
        }
        return LocalOutboxOperation(
            sequence: row["sequence"],
            operationID: operationID,
            profileID: profileID,
            aggregateKind: row["aggregate_kind"],
            aggregateID: aggregateID,
            operationKind: row["operation_kind"],
            aggregateVersion: row["aggregate_version"],
            idempotencyKey: row["idempotency_key"],
            status: row["status"],
            attemptCount: row["attempt_count"],
            createdAt: row["created_at"]
        )
    }

    private static func outboxPayload(draft: LocalExpenseDraft, localVersion: Int64) throws -> String {
        let payload = ExpenseOutboxPayload(
            id: draft.id,
            profileID: draft.profileID,
            accountID: draft.accountID,
            amountMinor: draft.amountMinor,
            currency: draft.currency,
            merchantName: draft.merchantName,
            platform: draft.platform,
            category: draft.category,
            paymentMethod: draft.paymentMethod,
            transactionDate: draft.transactionDate,
            transactionTime: draft.transactionTime,
            note: draft.note,
            localVersion: localVersion,
            createdAt: draft.createdAt
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }
}

private struct ExpenseOutboxPayload: Encodable {
    let id: UUID
    let profileID: UUID
    let accountID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let localVersion: Int64
    let createdAt: Date
}
