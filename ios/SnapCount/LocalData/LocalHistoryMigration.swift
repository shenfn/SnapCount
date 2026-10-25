import Foundation
import GRDB

enum LocalHistoryMigrationStatus: String, Equatable {
    case running
    case paused
    case completed
}

struct LocalHistoryMigrationState: Equatable {
    let profileID: UUID
    let cloudUserID: String
    let generation: Int64
    let status: LocalHistoryMigrationStatus
    let pullCursor: String?
    let importedRowCount: Int
    let startedAt: Date
    let updatedAt: Date
    let completedAt: Date?
}

enum LocalHistoryMigrationError: Error, Equatable {
    case invalidWorkspace
    case invalidCloudIdentity
    case identityMismatch
    case alreadyCompleted
    case staleAttempt
}

/// Keeps one explicitly authorized cloud-history import identity per local workspace.
final class LocalHistoryMigrationStore {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func startOrResume(profileID: UUID, cloudUserID: String, at now: Date = Date()) throws -> LocalHistoryMigrationState {
        guard !cloudUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalHistoryMigrationError.invalidCloudIdentity
        }
        try database.writer.write { db in
            guard try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) == 1 else { throw LocalHistoryMigrationError.invalidWorkspace }

            if let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_history_migrations WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) {
                let current = try Self.state(from: row)
                guard current.cloudUserID == cloudUserID else { throw LocalHistoryMigrationError.identityMismatch }
                guard current.status != .completed else { throw LocalHistoryMigrationError.alreadyCompleted }
                try db.execute(sql: """
                    UPDATE local_history_migrations
                    SET generation = ?, status = 'running', updated_at = ?
                    WHERE profile_id = ?
                    """, arguments: [current.generation + 1, now, profileID.uuidString])
            } else {
                try db.execute(sql: """
                    INSERT INTO local_history_migrations (
                        profile_id, cloud_user_id, generation, status, pull_cursor,
                        imported_row_count, started_at, updated_at, completed_at
                    ) VALUES (?, ?, 1, 'running', NULL, 0, ?, ?, NULL)
                    """, arguments: [profileID.uuidString, cloudUserID, now, now])
            }
            return try Self.fetch(profileID: profileID, database: db)
        }
    }

    func state(profileID: UUID) throws -> LocalHistoryMigrationState? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_history_migrations WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) else { return nil }
            return try Self.state(from: row)
        }
    }

    /// The imported facts and their next remote cursor commit or roll back together.
    func commitBatch(
        profileID: UUID,
        cloudUserID: String,
        generation: Int64,
        nextCursor: String?,
        importedRowCount: Int,
        at now: Date = Date(),
        apply: (Database) throws -> Void
    ) throws -> LocalHistoryMigrationState {
        guard importedRowCount >= 0 else { throw LocalDataError.invalidRecord }
        return try database.writer.write { db in
            let current = try Self.fetch(profileID: profileID, database: db)
            guard current.cloudUserID == cloudUserID,
                  current.generation == generation,
                  current.status == .running else { throw LocalHistoryMigrationError.staleAttempt }

            try apply(db)
            try db.execute(sql: """
                UPDATE local_history_migrations
                SET pull_cursor = ?, imported_row_count = imported_row_count + ?, updated_at = ?
                WHERE profile_id = ? AND cloud_user_id = ? AND generation = ? AND status = 'running'
                """, arguments: [nextCursor, importedRowCount, now, profileID.uuidString, cloudUserID, generation])
            guard db.changesCount == 1 else { throw LocalHistoryMigrationError.staleAttempt }
            return try Self.fetch(profileID: profileID, database: db)
        }
    }

    func pause(profileID: UUID, cloudUserID: String, generation: Int64, at now: Date = Date()) throws -> LocalHistoryMigrationState {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE local_history_migrations SET status = 'paused', updated_at = ?
                WHERE profile_id = ? AND cloud_user_id = ? AND generation = ? AND status = 'running'
                """, arguments: [now, profileID.uuidString, cloudUserID, generation])
            guard db.changesCount == 1 else { throw LocalHistoryMigrationError.staleAttempt }
            return try Self.fetch(profileID: profileID, database: db)
        }
    }

    func complete(profileID: UUID, cloudUserID: String, generation: Int64, at now: Date = Date()) throws -> LocalHistoryMigrationState {
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE local_history_migrations
                SET status = 'completed', updated_at = ?, completed_at = ?
                WHERE profile_id = ? AND cloud_user_id = ? AND generation = ? AND status = 'running'
                """, arguments: [now, now, profileID.uuidString, cloudUserID, generation])
            guard db.changesCount == 1 else { throw LocalHistoryMigrationError.staleAttempt }
            return try Self.fetch(profileID: profileID, database: db)
        }
    }

    private static func fetch(profileID: UUID, database: Database) throws -> LocalHistoryMigrationState {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM local_history_migrations WHERE profile_id = ?",
            arguments: [profileID.uuidString]
        ) else { throw LocalHistoryMigrationError.invalidWorkspace }
        return try state(from: row)
    }

    private static func state(from row: Row) throws -> LocalHistoryMigrationState {
        guard let profileID = UUID(uuidString: row["profile_id"]),
              let status = LocalHistoryMigrationStatus(rawValue: row["status"]),
              let startedAt: Date = row["started_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalHistoryMigrationState(
            profileID: profileID,
            cloudUserID: row["cloud_user_id"],
            generation: row["generation"],
            status: status,
            pullCursor: row["pull_cursor"],
            importedRowCount: row["imported_row_count"],
            startedAt: startedAt,
            updatedAt: updatedAt,
            completedAt: row["completed_at"]
        )
    }
}
