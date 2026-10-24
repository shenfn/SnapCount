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
    ) throws -> UUID {
        let operationID = UUID()
        try database.writer.write { db in
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT attempt_count, profile_id, status FROM local_image_intakes WHERE id = ?",
                arguments: [id]
            ) {
                guard let storedProfileID: String = row["profile_id"], storedProfileID == profileID.uuidString else {
                    throw LocalDataError.invalidIdentifier
                }
                let status: String = row["status"]
                guard status != LocalImageIntakeStatus.receiving.rawValue else {
                    throw LocalImageRecognitionError.alreadyInProgress
                }
                guard status != LocalImageIntakeStatus.completed.rawValue else {
                    throw LocalImageRecognitionError.alreadyCompleted
                }
                let attempts: Int = row["attempt_count"]
                guard attempts < 4 else { throw LocalImageRecognitionError.retryLimitReached }
                try db.execute(
                    sql: """
                        UPDATE local_image_intakes
                        SET capture_kind = ?, filename = ?, status = 'receiving', image_path = ?,
                            image_hash = ?, failure_message = NULL, cleanup_message = NULL,
                            attempt_count = attempt_count + 1, operation_id = ?, updated_at = ?
                        WHERE id = ? AND profile_id = ? AND status = 'failed'
                        """,
                    arguments: [
                        captureKind, filename, imagePath, imageHash,
                        operationID.uuidString, date, id, profileID.uuidString
                    ]
                )
                guard db.changesCount == 1 else { throw LocalImageRecognitionError.alreadyInProgress }
            } else {
                try db.execute(
                    sql: """
                        INSERT INTO local_image_intakes (
                            id, profile_id, capture_kind, filename, status, image_path,
                            image_hash, failure_message, attempt_count, created_at, updated_at, operation_id
                        ) VALUES (?, ?, ?, ?, 'receiving', ?, ?, NULL, 1, ?, ?, ?)
                        """,
                    arguments: [
                        id, profileID.uuidString, captureKind, filename, imagePath,
                        imageHash, date, date, operationID.uuidString
                    ]
                )
            }
            guard try Self.intake(db, id: id)?.profileID == profileID else {
                throw LocalDataError.invalidIdentifier
            }
        }
        return operationID
    }

    func markFailed(id: String, profileID: UUID, operationID: UUID, message: String, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE local_image_intakes
                    SET status = 'failed', failure_message = ?, operation_id = NULL, updated_at = ?
                    WHERE id = ? AND profile_id = ? AND status = 'receiving' AND operation_id = ?
                    """,
                arguments: [message, date, id, profileID.uuidString, operationID.uuidString]
            )
        }
    }

    func markCompleted(id: String, profileID: UUID, operationID: UUID, cleanupMessage: String?, at date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE local_image_intakes
                    SET status = 'completed', failure_message = NULL, cleanup_message = ?, operation_id = NULL, updated_at = ?
                    WHERE id = ? AND profile_id = ? AND status = 'receiving' AND operation_id = ?
                    """,
                arguments: [cleanupMessage, date, id, profileID.uuidString, operationID.uuidString]
            )
            guard db.changesCount == 1 else { throw CancellationError() }
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

    func isReceiving(id: String, profileID: UUID, operationID: UUID) throws -> Bool {
        try database.writer.read { db in
            (try Int.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM local_image_intakes
                        WHERE id = ? AND profile_id = ? AND status = 'receiving' AND operation_id = ?
                    )
                    """,
                arguments: [id, profileID.uuidString, operationID.uuidString]
            ) ?? 0) != 0
        }
    }

    func recoverInterrupted(profileID: UUID, before date: Date) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE local_image_intakes
                    SET status = 'failed', failure_message = '识别进程已中断，可重试或手动处理',
                        operation_id = NULL, updated_at = ?
                    WHERE profile_id = ? AND status = 'receiving' AND updated_at < ?
                    """,
                arguments: [Date(), profileID.uuidString, date]
            )
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
                sql: "SELECT status, image_path FROM local_image_intakes WHERE id = ? AND profile_id = ?",
                arguments: [id, profileID.uuidString]
            ), let status = LocalImageIntakeStatus(rawValue: row["status"]), status == .failed,
               let imagePath: String = row["image_path"] else {
                throw LocalDataError.recordNotFound
            }
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO local_image_cleanups (
                        id, profile_id, image_path, attempt_count, last_error, created_at, updated_at
                    ) VALUES (?, ?, ?, 0, NULL, ?, ?)
                    """,
                arguments: [UUID().uuidString, profileID.uuidString, imagePath, Date(), Date()]
            )
            try db.execute(
                sql: "DELETE FROM local_image_intakes WHERE id = ? AND profile_id = ?",
                arguments: [id, profileID.uuidString]
            )
            guard db.changesCount == 1 else { throw LocalDataError.recordNotFound }
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
