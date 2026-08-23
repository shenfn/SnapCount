import Foundation
import GRDB

final class GRDBSpikeStore {
    private let databaseQueue: DatabaseQueue

    init(databaseURL: URL) throws {
        databaseQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.currentMigrator.migrate(databaseQueue)
    }

    func insertExpenseAndOutbox(
        stableID: UUID,
        operationID: UUID,
        amountMinor: Int64,
        note: String? = nil,
        injectFailureAfterExpense: Bool = false
    ) throws {
        try databaseQueue.write { database in
            try database.execute(
                sql: """
                INSERT INTO expense_records (stable_id, amount_minor, occurred_at, note)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [stableID.uuidString, amountMinor, Date(), note]
            )

            if injectFailureAfterExpense {
                throw LocalDatabaseSpikeError.injectedFailure
            }

            try database.execute(
                sql: """
                INSERT INTO outbox_operations (operation_id, record_id, operation_kind, created_at)
                VALUES (?, ?, 'upsert', ?)
                """,
                arguments: [operationID.uuidString, stableID.uuidString, Date()]
            )
        }
    }

    func expenseCount() throws -> Int {
        try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM expense_records") ?? 0
        }
    }

    func outboxCount() throws -> Int {
        try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM outbox_operations") ?? 0
        }
    }

    func expense(stableID: UUID) throws -> SpikeExpenseSnapshot? {
        try databaseQueue.read { database in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT stable_id, amount_minor, note
                FROM expense_records
                WHERE stable_id = ?
                """,
                arguments: [stableID.uuidString]
            ) else {
                return nil
            }

            guard let persistedID = UUID(uuidString: row["stable_id"]) else {
                return nil
            }
            return SpikeExpenseSnapshot(
                stableID: persistedID,
                amountMinor: row["amount_minor"],
                note: row["note"]
            )
        }
    }

    static func createVersion1Database(
        at databaseURL: URL,
        stableID: UUID,
        amountMinor: Int64
    ) throws {
        let queue = try DatabaseQueue(path: databaseURL.path)
        try version1Migrator.migrate(queue)
        try queue.write { database in
            try database.execute(
                sql: """
                INSERT INTO expense_records (stable_id, amount_minor, occurred_at)
                VALUES (?, ?, ?)
                """,
                arguments: [stableID.uuidString, amountMinor, Date()]
            )
        }
    }

    private static var version1Migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.create(table: "expense_records") { table in
                table.column("stable_id", .text).primaryKey()
                table.column("amount_minor", .integer).notNull()
                table.column("occurred_at", .datetime).notNull()
            }
            try database.create(table: "outbox_operations") { table in
                table.column("operation_id", .text).primaryKey()
                table.column("record_id", .text).notNull()
                    .references("expense_records", column: "stable_id", onDelete: .cascade)
                table.column("operation_kind", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }
        }
        return migrator
    }

    private static var currentMigrator: DatabaseMigrator {
        var migrator = version1Migrator
        migrator.registerMigration("v2") { database in
            try database.alter(table: "expense_records") { table in
                table.add(column: "note", .text)
            }
        }
        return migrator
    }
}
