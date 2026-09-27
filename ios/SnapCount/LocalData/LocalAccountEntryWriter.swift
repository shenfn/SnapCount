import Foundation
import GRDB

/// Shared local ledger primitives. Domain repositories own transaction boundaries
/// and decide when a source should create or replace an entry.
enum LocalAccountEntryWriter {
    static func validateAccount(
        id: UUID,
        profileID: UUID,
        database: Database
    ) throws {
        guard let storedProfileID = try String.fetchOne(
            database,
            sql: "SELECT profile_id FROM local_accounts WHERE id = ?",
            arguments: [id.uuidString]
        ), storedProfileID == profileID.uuidString else {
            throw LocalDataError.invalidIdentifier
        }
    }

    @discardableResult
    static func voidActiveEntry(
        sourceKind: String,
        sourceID: UUID,
        voidedAt: Date,
        database: Database
    ) throws -> Bool {
        guard let entryID = try String.fetchOne(
            database,
            sql: """
                SELECT id FROM local_account_entries
                WHERE source_kind = ? AND source_id = ? AND voided_at IS NULL
                """,
            arguments: [sourceKind, sourceID.uuidString]
        ) else {
            return false
        }
        try database.execute(
            sql: "UPDATE local_account_entries SET voided_at = ? WHERE id = ?",
            arguments: [voidedAt, entryID]
        )
        return true
    }

    static func insertEntry(
        id: UUID = UUID(),
        profileID: UUID,
        accountID: UUID,
        direction: String,
        amountMinor: Int64,
        entryKind: String,
        sourceKind: String,
        sourceID: UUID,
        occurredAt: Date,
        database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_account_entries (
                    id, profile_id, account_id, direction, amount_minor, entry_kind,
                    source_kind, source_id, occurred_at, voided_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                """,
            arguments: [
                id.uuidString,
                profileID.uuidString,
                accountID.uuidString,
                direction,
                amountMinor,
                entryKind,
                sourceKind,
                sourceID.uuidString,
                occurredAt
            ]
        )
    }
}
