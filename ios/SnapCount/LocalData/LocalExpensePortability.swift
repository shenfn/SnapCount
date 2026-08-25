import Foundation
import GRDB

struct LocalExpenseArchive: Codable, Equatable {
    static let currentFormat = "jiezi-local-expense-archive"
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let profile: Profile
    let accounts: [Account]
    let expenses: [Expense]
    let accountEntries: [AccountEntry]

    struct Profile: Codable, Equatable {
        let id: UUID
        let createdAt: Date
    }

    struct Account: Codable, Equatable {
        let id: UUID
        let profileID: UUID
        let name: String
        let kind: String
        let currency: String
        let openingBalanceMinor: Int64
        let createdAt: Date
    }

    struct Expense: Codable, Equatable {
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
        let updatedAt: Date
        let deletedAt: Date?
    }

    struct AccountEntry: Codable, Equatable {
        let id: UUID
        let profileID: UUID
        let accountID: UUID
        let direction: String
        let amountMinor: Int64
        let entryKind: String
        let sourceKind: String
        let sourceID: UUID
        let occurredAt: Date
        let voidedAt: Date?
    }
}

struct LocalExpenseImportResult: Equatable {
    let insertedProfiles: Int
    let insertedAccounts: Int
    let insertedExpenses: Int
    let insertedAccountEntries: Int
    let insertedOutboxOperations: Int
    let skippedProfiles: Int
    let skippedAccounts: Int
    let skippedExpenses: Int
    let skippedAccountEntries: Int
}

enum LocalExpenseArchiveError: Error, Equatable {
    case invalidFormat
    case unsupportedSchemaVersion(Int)
    case invalidRelationship
    case conflictingStableID(entity: String, id: UUID)
    case duplicateStableID(entity: String, id: UUID)
}

final class LocalExpensePortability {
    private let database: LocalDatabase
    private let operationID: () -> UUID

    init(database: LocalDatabase, operationID: @escaping () -> UUID = UUID.init) {
        self.database = database
        self.operationID = operationID
    }

    func exportArchive(profileID: UUID, exportedAt: Date = Date()) throws -> Data {
        try database.writer.read { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT id, created_at FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) else {
                throw LocalDataError.invalidIdentifier
            }

            let profile = LocalExpenseArchive.Profile(
                id: profileID,
                createdAt: profileRow["created_at"]
            )
            let accounts = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, name, kind, currency,
                           opening_balance_minor, created_at
                    FROM local_accounts
                    WHERE profile_id = ?
                    ORDER BY created_at ASC, id ASC
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.accountArchive)
            let expenses = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, account_id, amount_minor, currency,
                           merchant_name, platform, category, payment_method,
                           transaction_date, transaction_time, note, local_version,
                           created_at, updated_at, deleted_at
                    FROM local_expenses
                    WHERE profile_id = ?
                    ORDER BY created_at ASC, id ASC
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.expenseArchive)
            let entries = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, account_id, direction, amount_minor,
                           entry_kind, source_kind, source_id, occurred_at, voided_at
                    FROM local_account_entries
                    WHERE profile_id = ?
                    ORDER BY occurred_at ASC, id ASC
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.entryArchive)

            let archive = LocalExpenseArchive(
                format: LocalExpenseArchive.currentFormat,
                schemaVersion: LocalExpenseArchive.currentSchemaVersion,
                exportedAt: exportedAt,
                profile: profile,
                accounts: accounts,
                expenses: expenses,
                accountEntries: entries
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(archive)
        }
    }

    func importArchive(
        _ data: Data,
        importedAt: Date = Date(),
        enqueueOutbox: Bool = true,
        expectedProfileID: UUID? = nil
    ) throws -> LocalExpenseImportResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LocalExpenseArchive.self, from: data)
        try validate(archive)
        if let expectedProfileID, archive.profile.id != expectedProfileID {
            throw LocalExpenseArchiveError.invalidRelationship
        }

        return try database.writer.write { db in
            let existingProfile = try Row.fetchOne(
                db,
                sql: "SELECT id, created_at FROM local_profiles WHERE id = ?",
                arguments: [archive.profile.id.uuidString]
            )
            if let existingProfile {
                let existingCreatedAt: Date = existingProfile["created_at"]
                if existingCreatedAt != archive.profile.createdAt {
                    throw LocalExpenseArchiveError.conflictingStableID(
                        entity: "profile",
                        id: archive.profile.id
                    )
                }
            }

            var insertedProfiles = 0
            var skippedProfiles = 0
            if existingProfile != nil {
                skippedProfiles = 1
            } else {
                try db.execute(
                    sql: """
                        INSERT INTO local_profiles (id, created_at, cloud_user_id, sync_enabled)
                        VALUES (?, ?, NULL, 0)
                        """,
                    arguments: [archive.profile.id.uuidString, archive.profile.createdAt]
                )
                insertedProfiles = 1
            }

            var insertedAccounts = 0
            var skippedAccounts = 0
            for account in archive.accounts {
                let existing = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT id, profile_id, name, kind, currency,
                               opening_balance_minor, created_at
                        FROM local_accounts WHERE id = ?
                        """,
                    arguments: [account.id.uuidString]
                )
                if let existing {
                    guard Self.accountMatches(existing, account) else {
                        throw LocalExpenseArchiveError.conflictingStableID(entity: "account", id: account.id)
                    }
                    skippedAccounts += 1
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO local_accounts (
                                id, profile_id, name, kind, currency,
                                opening_balance_minor, created_at
                            ) VALUES (?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            account.id.uuidString,
                            account.profileID.uuidString,
                            account.name,
                            account.kind,
                            account.currency,
                            account.openingBalanceMinor,
                            account.createdAt
                        ]
                    )
                    insertedAccounts += 1
                }
            }

            var insertedExpenses = 0
            var insertedExpenseIDs = Set<UUID>()
            var skippedExpenses = 0
            var insertedEntries = 0
            var skippedEntries = 0

            for expense in archive.expenses {
                let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM local_expenses WHERE id = ?",
                    arguments: [expense.id.uuidString]
                )
                if let existing {
                    guard Self.expenseMatches(existing, expense) else {
                        throw LocalExpenseArchiveError.conflictingStableID(entity: "expense", id: expense.id)
                    }
                    skippedExpenses += 1
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO local_expenses (
                                id, profile_id, account_id, amount_minor, currency, merchant_name,
                                platform, category, payment_method, transaction_date, transaction_time,
                                note, local_version, created_at, updated_at, deleted_at
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            expense.id.uuidString,
                            expense.profileID.uuidString,
                            expense.accountID.uuidString,
                            expense.amountMinor,
                            expense.currency,
                            expense.merchantName,
                            expense.platform,
                            expense.category,
                            expense.paymentMethod,
                            expense.transactionDate,
                            expense.transactionTime,
                            expense.note,
                            expense.localVersion,
                            expense.createdAt,
                            expense.updatedAt,
                            expense.deletedAt
                        ]
                    )
                    insertedExpenses += 1
                    insertedExpenseIDs.insert(expense.id)
                }
            }

            for entry in archive.accountEntries {
                let existing = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM local_account_entries WHERE id = ?",
                    arguments: [entry.id.uuidString]
                )
                if let existing {
                    guard Self.entryMatches(existing, entry) else {
                        throw LocalExpenseArchiveError.conflictingStableID(entity: "account_entry", id: entry.id)
                    }
                    skippedEntries += 1
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO local_account_entries (
                                id, profile_id, account_id, direction, amount_minor, entry_kind,
                                source_kind, source_id, occurred_at, voided_at
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                        arguments: [
                            entry.id.uuidString,
                            entry.profileID.uuidString,
                            entry.accountID.uuidString,
                            entry.direction,
                            entry.amountMinor,
                            entry.entryKind,
                            entry.sourceKind,
                            entry.sourceID.uuidString,
                            entry.occurredAt,
                            entry.voidedAt
                        ]
                    )
                    insertedEntries += 1
                }
            }

            var insertedOutbox = 0
            for expense in archive.expenses where enqueueOutbox && insertedExpenseIDs.contains(expense.id) {
                try db.execute(
                    sql: """
                        INSERT INTO local_outbox_operations (
                            operation_id, profile_id, aggregate_kind, aggregate_id, operation_kind,
                            aggregate_version, idempotency_key, payload_json, status, attempt_count,
                            next_attempt_at, last_error, created_at
                        ) VALUES (?, ?, 'expense', ?, ?, ?, ?, ?, 'pending', 0, NULL, NULL, ?)
                        """,
                    arguments: [
                        operationID().uuidString,
                        expense.profileID.uuidString,
                        expense.id.uuidString,
                        expense.deletedAt == nil ? "upsert" : "delete",
                        expense.localVersion,
                        UUID().uuidString,
                        try Self.outboxPayload(for: expense),
                        importedAt
                    ]
                )
                insertedOutbox += 1
            }

            return LocalExpenseImportResult(
                insertedProfiles: insertedProfiles,
                insertedAccounts: insertedAccounts,
                insertedExpenses: insertedExpenses,
                insertedAccountEntries: insertedEntries,
                insertedOutboxOperations: insertedOutbox,
                skippedProfiles: skippedProfiles,
                skippedAccounts: skippedAccounts,
                skippedExpenses: skippedExpenses,
                skippedAccountEntries: skippedEntries
            )
        }
    }

    private func validate(_ archive: LocalExpenseArchive) throws {
        guard archive.format == LocalExpenseArchive.currentFormat else {
            throw LocalExpenseArchiveError.invalidFormat
        }
        guard archive.schemaVersion == LocalExpenseArchive.currentSchemaVersion else {
            throw LocalExpenseArchiveError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        try validateUnique(archive.accounts.map(\.id), entity: "account")
        try validateUnique(archive.expenses.map(\.id), entity: "expense")
        try validateUnique(archive.accountEntries.map(\.id), entity: "account_entry")

        let accountIDs = Set(archive.accounts.map(\.id))
        let expenseIDs = Set(archive.expenses.map(\.id))
        guard archive.accounts.allSatisfy({ $0.profileID == archive.profile.id }),
              archive.expenses.allSatisfy({
                  $0.profileID == archive.profile.id && accountIDs.contains($0.accountID)
              }),
              archive.accountEntries.allSatisfy({
                  $0.profileID == archive.profile.id
                      && accountIDs.contains($0.accountID)
                      && $0.sourceKind == "expense"
                      && expenseIDs.contains($0.sourceID)
              }) else {
            throw LocalExpenseArchiveError.invalidRelationship
        }
    }

    private func validateUnique(_ ids: [UUID], entity: String) throws {
        var seen = Set<UUID>()
        for id in ids where !seen.insert(id).inserted {
            throw LocalExpenseArchiveError.duplicateStableID(entity: entity, id: id)
        }
    }

    private static func accountArchive(_ row: Row) -> LocalExpenseArchive.Account {
        LocalExpenseArchive.Account(
            id: UUID(uuidString: row["id"])!,
            profileID: UUID(uuidString: row["profile_id"])!,
            name: row["name"],
            kind: row["kind"],
            currency: row["currency"],
            openingBalanceMinor: row["opening_balance_minor"],
            createdAt: row["created_at"]
        )
    }

    private static func expenseArchive(_ row: Row) -> LocalExpenseArchive.Expense {
        LocalExpenseArchive.Expense(
            id: UUID(uuidString: row["id"])!,
            profileID: UUID(uuidString: row["profile_id"])!,
            accountID: UUID(uuidString: row["account_id"])!,
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
            updatedAt: row["updated_at"],
            deletedAt: row["deleted_at"]
        )
    }

    private static func entryArchive(_ row: Row) -> LocalExpenseArchive.AccountEntry {
        LocalExpenseArchive.AccountEntry(
            id: UUID(uuidString: row["id"])!,
            profileID: UUID(uuidString: row["profile_id"])!,
            accountID: UUID(uuidString: row["account_id"])!,
            direction: row["direction"],
            amountMinor: row["amount_minor"],
            entryKind: row["entry_kind"],
            sourceKind: row["source_kind"],
            sourceID: UUID(uuidString: row["source_id"])!,
            occurredAt: row["occurred_at"],
            voidedAt: row["voided_at"]
        )
    }

    private static func accountMatches(_ row: Row, _ value: LocalExpenseArchive.Account) -> Bool {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]) else {
            return false
        }
        let createdAt: Date = row["created_at"]
        let name: String = row["name"]
        let kind: String = row["kind"]
        let currency: String = row["currency"]
        let openingBalanceMinor: Int64 = row["opening_balance_minor"]
        return id == value.id
            && profileID == value.profileID
            && name == value.name
            && kind == value.kind
            && currency == value.currency
            && openingBalanceMinor == value.openingBalanceMinor
            && createdAt == value.createdAt
    }

    private static func expenseMatches(_ row: Row, _ value: LocalExpenseArchive.Expense) -> Bool {
        expenseArchive(row) == value
    }

    private static func entryMatches(_ row: Row, _ value: LocalExpenseArchive.AccountEntry) -> Bool {
        entryArchive(row) == value
    }

    private static func outboxPayload(for expense: LocalExpenseArchive.Expense) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(expense), as: UTF8.self)
    }
}
