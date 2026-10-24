import Foundation
import GRDB

enum LocalImageIntakeStatus: String, Equatable {
    case receiving
    case failed
    case completed
}

struct LocalImageIntake: Equatable, Identifiable {
    let id: String
    let profileID: UUID
    let captureKind: String
    let filename: String
    let status: LocalImageIntakeStatus
    let imagePath: String
    let imageHash: String
    let failureMessage: String?
    let cleanupMessage: String?
    let attemptCount: Int
    let createdAt: Date
    let updatedAt: Date

    var retryCount: Int { max(0, attemptCount - 1) }
}

final class LocalImageIntakeRepository {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func activeProfile() throws -> LocalProfile {
        try LocalProfileStore(database: database).activeProfile()
    }

    func beginAttempt(
        id: String,
        profileID: UUID,
        captureKind: String,
        filename: String,
        imagePath: String,
        imageHash: String,
        at date: Date
    ) throws {
        try database.writer.write { db in
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT attempt_count, profile_id FROM local_image_intakes WHERE id = ?",
                arguments: [id]
            ), let storedProfileID: String = row["profile_id"],
               storedProfileID == profileID.uuidString,
               let attempts: Int = row["attempt_count"], attempts >= 4 {
                throw LocalImageRecognitionError.retryLimitReached
            }
            try db.execute(
                sql: """
                    INSERT INTO local_image_intakes (
                        id, profile_id, capture_kind, filename, status, image_path,
                        image_hash, failure_message, attempt_count, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, 'receiving', ?, ?, NULL, 1, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        capture_kind = excluded.capture_kind,
                        filename = excluded.filename,
                        status = 'receiving',
                        image_path = excluded.image_path,
                        image_hash = excluded.image_hash,
                        failure_message = NULL,
                        cleanup_message = NULL,
                        attempt_count = local_image_intakes.attempt_count + 1,
                        updated_at = excluded.updated_at
                    WHERE local_image_intakes.profile_id = excluded.profile_id
                    """,
                arguments: [
                    id, profileID.uuidString, captureKind, filename, imagePath,
                    imageHash, date, date
                ]
            )
            guard try Self.intake(db, id: id)?.profileID == profileID else {
                throw LocalDataError.invalidIdentifier
            }
        }
    }

    func markFailed(id: String, profileID: UUID, message: String, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE local_image_intakes
                    SET status = 'failed', failure_message = ?, updated_at = ?
                    WHERE id = ? AND profile_id = ? AND status = 'receiving'
                    """,
                arguments: [message, date, id, profileID.uuidString]
            )
        }
    }

    func markCompleted(id: String, profileID: UUID, cleanupMessage: String?, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE local_image_intakes
                    SET status = 'completed', failure_message = NULL, cleanup_message = ?, updated_at = ?
                    WHERE id = ? AND profile_id = ?
                    """,
                arguments: [cleanupMessage, date, id, profileID.uuidString]
            )
        }
    }

    func enqueueImageCleanup(profileID: UUID, imagePath: String, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO local_image_cleanups (
                        id, profile_id, image_path, attempt_count, last_error, created_at, updated_at
                    ) VALUES (?, ?, ?, 0, NULL, ?, ?)
                    """,
                arguments: [UUID().uuidString, profileID.uuidString, imagePath, date, date]
            )
        }
    }

    func removeMissingIntake(id: String, profileID: UUID) throws {
        try database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM local_image_intakes WHERE id = ? AND profile_id = ?",
                arguments: [id, profileID.uuidString]
            )
        }
    }

    func intake(id: String, profileID: UUID) throws -> LocalImageIntake? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_image_intakes WHERE id = ? AND profile_id = ?",
                arguments: [id, profileID.uuidString]
            ) else { return nil }
            return try Self.intake(from: row)
        }
    }

    func isReceiving(id: String, profileID: UUID) throws -> Bool {
        try database.writer.read { db in
            (try Int.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM local_image_intakes
                        WHERE id = ? AND profile_id = ? AND status = 'receiving'
                    )
                    """,
                arguments: [id, profileID.uuidString]
            ) ?? 0) != 0
        }
    }

    func failedIntakes(profileID: UUID) throws -> [LocalImageIntake] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_image_intakes
                    WHERE profile_id = ? AND status IN ('failed', 'receiving')
                    ORDER BY updated_at DESC, id
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.intake(from:))
        }
    }

    func discard(id: String, profileID: UUID) throws {
        try database.writer.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT status FROM local_image_intakes WHERE id = ? AND profile_id = ?",
                arguments: [id, profileID.uuidString]
            ), let status = LocalImageIntakeStatus(rawValue: row["status"]), status != .completed else {
                throw LocalDataError.recordNotFound
            }
            try db.execute(
                sql: "DELETE FROM local_image_intakes WHERE id = ? AND profile_id = ?",
                arguments: [id, profileID.uuidString]
            )
        }
    }

    private static func intake(_ db: Database, id: String) throws -> LocalImageIntake? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM local_image_intakes WHERE id = ?",
            arguments: [id]
        ) else { return nil }
        return try intake(from: row)
    }

    private static func intake(from row: Row) throws -> LocalImageIntake {
        guard let profileID = UUID(uuidString: row["profile_id"]),
              let status = LocalImageIntakeStatus(rawValue: row["status"]),
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalImageIntake(
            id: row["id"],
            profileID: profileID,
            captureKind: row["capture_kind"],
            filename: row["filename"],
            status: status,
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            failureMessage: row["failure_message"],
            cleanupMessage: row["cleanup_message"],
            attemptCount: row["attempt_count"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
