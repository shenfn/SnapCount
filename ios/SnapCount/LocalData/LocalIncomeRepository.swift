import Foundation
import GRDB

protocol LocalIncomeRepositoryProtocol {
    func createIncome(_ draft: LocalIncomeDraft) throws -> LocalIncome
    func updateIncome(_ update: LocalIncomeUpdate, profileID: UUID) throws -> LocalIncome
    func deleteIncome(_ command: LocalIncomeDeleteCommand, profileID: UUID) throws -> LocalIncomeTombstone
    func income(id: UUID) throws -> LocalIncome?
    func incomes(profileID: UUID, monthKey: String) throws -> [LocalIncome]
    func incomeTombstone(id: UUID) throws -> LocalIncomeTombstone?
}

final class LocalIncomeRepository: LocalIncomeRepositoryProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) throws {
        self.database = database
    }

    func createIncome(_ draft: LocalIncomeDraft) throws -> LocalIncome {
        try validateDraft(draft)
        return try database.writer.write { db in
            if let accountID = draft.accountID {
                try LocalAccountEntryWriter.validateAccount(
                    id: accountID,
                    profileID: draft.profileID,
                    database: db
                )
            }
            try db.execute(
                sql: """
                    INSERT INTO local_incomes (
                        id, profile_id, account_id, amount_minor, currency, income_category,
                        source_name, income_date, income_time, note, local_version,
                        created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString,
                    draft.profileID.uuidString,
                    draft.accountID?.uuidString,
                    draft.amountMinor,
                    draft.currency,
                    draft.incomeCategory,
                    draft.sourceName,
                    draft.incomeDate,
                    draft.incomeTime,
                    draft.note,
                    draft.createdAt,
                    draft.createdAt
                ]
            )
            if let accountID = draft.accountID {
                try LocalAccountEntryWriter.insertEntry(
                    profileID: draft.profileID,
                    accountID: accountID,
                    direction: "in",
                    amountMinor: draft.amountMinor,
                    entryKind: "income",
                    sourceKind: "income",
                    sourceID: draft.id,
                    occurredAt: Self.occurredAt(
                        dateKey: draft.incomeDate,
                        timeKey: draft.incomeTime,
                        fallback: draft.createdAt
                    ),
                    database: db
                )
            }
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_incomes WHERE id = ?",
                arguments: [draft.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.income(from: row)
        }
    }

    func updateIncome(_ update: LocalIncomeUpdate, profileID: UUID) throws -> LocalIncome {
        guard update.amountMinor > 0,
              !update.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !update.incomeCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalDataError.invalidRecord
        }
        return try database.writer.write { db in
            let current = try activeIncome(id: update.id, database: db)
            guard current.profileID == profileID else { throw LocalDataError.invalidIdentifier }
            guard current.localVersion == update.expectedVersion else {
                throw LocalDataError.versionConflict(
                    expected: update.expectedVersion,
                    actual: current.localVersion
                )
            }
            if let accountID = update.accountID {
                try LocalAccountEntryWriter.validateAccount(
                    id: accountID,
                    profileID: profileID,
                    database: db
                )
            }

            let ledgerChanged = current.accountID != update.accountID
                || current.amountMinor != update.amountMinor
                || current.incomeDate != update.incomeDate
                || current.incomeTime != update.incomeTime
            if ledgerChanged {
                _ = try LocalAccountEntryWriter.voidActiveEntry(
                    sourceKind: "income",
                    sourceID: update.id,
                    voidedAt: update.updatedAt,
                    database: db
                )
                if let accountID = update.accountID {
                    try LocalAccountEntryWriter.insertEntry(
                        profileID: profileID,
                        accountID: accountID,
                        direction: "in",
                        amountMinor: update.amountMinor,
                        entryKind: "income",
                        sourceKind: "income",
                        sourceID: update.id,
                        occurredAt: Self.occurredAt(
                            dateKey: update.incomeDate,
                            timeKey: update.incomeTime,
                            fallback: update.updatedAt
                        ),
                        database: db
                    )
                }
            }

            try db.execute(
                sql: """
                    UPDATE local_incomes
                    SET account_id = ?, amount_minor = ?, currency = ?, income_category = ?,
                        source_name = ?, income_date = ?, income_time = ?, note = ?,
                        local_version = local_version + 1, updated_at = ?
                    WHERE id = ? AND profile_id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    update.accountID?.uuidString,
                    update.amountMinor,
                    update.currency,
                    update.incomeCategory,
                    update.sourceName,
                    update.incomeDate,
                    update.incomeTime,
                    update.note,
                    update.updatedAt,
                    update.id.uuidString,
                    profileID.uuidString
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_incomes WHERE id = ?",
                arguments: [update.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.income(from: row)
        }
    }

    func deleteIncome(
        _ command: LocalIncomeDeleteCommand,
        profileID: UUID
    ) throws -> LocalIncomeTombstone {
        try database.writer.write { db in
            let current = try activeIncome(id: command.id, database: db)
            guard current.profileID == profileID else { throw LocalDataError.invalidIdentifier }
            guard current.localVersion == command.expectedVersion else {
                throw LocalDataError.versionConflict(
                    expected: command.expectedVersion,
                    actual: current.localVersion
                )
            }
            _ = try LocalAccountEntryWriter.voidActiveEntry(
                sourceKind: "income",
                sourceID: command.id,
                voidedAt: command.deletedAt,
                database: db
            )
            try db.execute(
                sql: """
                    UPDATE local_incomes
                    SET local_version = local_version + 1, updated_at = ?, deleted_at = ?
                    WHERE id = ? AND profile_id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    command.deletedAt,
                    command.deletedAt,
                    command.id.uuidString,
                    profileID.uuidString
                ]
            )
            return LocalIncomeTombstone(
                id: current.id,
                profileID: current.profileID,
                localVersion: current.localVersion + 1,
                deletedAt: command.deletedAt
            )
        }
    }

    func income(id: UUID) throws -> LocalIncome? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_incomes WHERE id = ? AND deleted_at IS NULL",
                arguments: [id.uuidString]
            ) else { return nil }
            return try Self.income(from: row)
        }
    }

    func incomes(profileID: UUID, monthKey: String) throws -> [LocalIncome] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_incomes
                    WHERE profile_id = ? AND income_date LIKE ? AND deleted_at IS NULL
                    ORDER BY income_date DESC, income_time DESC, created_at DESC, id DESC
                    """,
                arguments: [profileID.uuidString, "\(monthKey)-%"]
            ).map(Self.income(from:))
        }
    }

    func incomeTombstone(id: UUID) throws -> LocalIncomeTombstone? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_incomes WHERE id = ? AND deleted_at IS NOT NULL",
                arguments: [id.uuidString]
            ) else { return nil }
            guard let profileID = UUID(uuidString: row["profile_id"]),
                  let deletedAt: Date = row["deleted_at"] else {
                throw LocalDataError.invalidRecord
            }
            return LocalIncomeTombstone(
                id: id,
                profileID: profileID,
                localVersion: row["local_version"],
                deletedAt: deletedAt
            )
        }
    }

    private func validateDraft(_ draft: LocalIncomeDraft) throws {
        guard draft.amountMinor > 0,
              !draft.currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.incomeCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.incomeDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalDataError.invalidRecord
        }
    }

    private func activeIncome(id: UUID, database: Database) throws -> LocalIncome {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM local_incomes WHERE id = ? AND deleted_at IS NULL",
            arguments: [id.uuidString]
        ) else {
            throw LocalDataError.recordNotFound
        }
        return try Self.income(from: row)
    }

    private static func income(from row: Row) throws -> LocalIncome {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let currency: String = row["currency"],
              let incomeCategory: String = row["income_category"],
              let incomeDate: String = row["income_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        let accountIDText: String? = row["account_id"]
        return LocalIncome(
            id: id,
            profileID: profileID,
            accountID: accountIDText.flatMap { UUID(uuidString: $0) },
            amountMinor: row["amount_minor"],
            currency: currency,
            incomeCategory: incomeCategory,
            sourceName: row["source_name"],
            incomeDate: incomeDate,
            incomeTime: row["income_time"],
            note: row["note"],
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func occurredAt(dateKey: String, timeKey: String?, fallback: Date) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: "\(dateKey) \(timeKey ?? "00:00:00")") ?? fallback
    }
}
