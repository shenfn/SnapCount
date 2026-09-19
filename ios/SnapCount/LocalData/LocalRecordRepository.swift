import Foundation
import GRDB

protocol LocalRecordRepositoryProtocol {
    func createRecord(_ draft: LocalRecordDraft) throws -> LocalRecord
    func updateRecord(_ update: LocalRecordUpdateCommand, profileID: UUID) throws -> LocalRecord
    func deleteRecord(_ command: LocalRecordDeleteCommand, profileID: UUID) throws -> LocalRecordTombstone
    func record(id: UUID) throws -> LocalRecord?
    func records(profileID: UUID, monthKey: String) throws -> [LocalRecord]
    func recordTombstone(id: UUID) throws -> LocalRecordTombstone?
    func createStaging(_ draft: LocalStagingDraft) throws -> LocalStagingRecord
    func staging(id: String) throws -> LocalStagingRecord?
    func stagingRecords(profileID: UUID) throws -> [LocalStagingRecord]
    func archiveStaging(id: String, recordID: UUID, updatedAt: Date, profileID: UUID) throws -> LocalRecord
    func discardStaging(id: String, updatedAt: Date, profileID: UUID) throws
}

final class LocalRecordRepository: LocalRecordRepositoryProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) throws {
        self.database = database
    }

    func createRecord(_ draft: LocalRecordDraft) throws -> LocalRecord {
        guard LocalRecordValidation.supportedDomainKeys.contains(draft.domainKey) else {
            throw LocalDataError.invalidRecord
        }
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_records (
                        id, profile_id, domain_key, title, summary, payload_json,
                        record_date, record_time, note, image_path, image_hash,
                        local_version, created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString,
                    draft.profileID.uuidString,
                    draft.domainKey,
                    draft.title,
                    draft.summary,
                    draft.payloadJSON,
                    draft.recordDate,
                    draft.recordTime,
                    draft.note,
                    draft.imagePath,
                    draft.imageHash,
                    draft.createdAt,
                    draft.createdAt
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ?",
                arguments: [draft.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.record(from: row)
        }
    }

    func updateRecord(_ update: LocalRecordUpdateCommand, profileID: UUID) throws -> LocalRecord {
        try database.writer.write { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ?",
                arguments: [update.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            try Self.assertProfile(current, profileID: profileID)
            let actualVersion: Int64 = current["local_version"]
            let deletedAt: Date? = current["deleted_at"]
            guard deletedAt == nil else { throw LocalDataError.recordNotFound }
            guard actualVersion == update.expectedVersion else {
                throw LocalDataError.versionConflict(expected: update.expectedVersion, actual: actualVersion)
            }

            let payloadJSON = try LocalRecordCodec.encode(update.payload)
            try db.execute(
                sql: """
                    UPDATE local_records
                    SET title = ?, summary = ?, payload_json = ?, record_date = ?,
                        record_time = ?, note = ?, local_version = local_version + 1,
                        updated_at = ?
                    WHERE id = ? AND deleted_at IS NULL AND local_version = ?
                    """,
                arguments: [
                    update.title,
                    update.summary,
                    payloadJSON,
                    update.recordDate,
                    update.recordTime,
                    update.note,
                    update.updatedAt,
                    update.id.uuidString,
                    update.expectedVersion
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ?",
                arguments: [update.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.record(from: row)
        }
    }

    func deleteRecord(
        _ command: LocalRecordDeleteCommand,
        profileID: UUID
    ) throws -> LocalRecordTombstone {
        try database.writer.write { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ?",
                arguments: [command.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            try Self.assertProfile(current, profileID: profileID)
            let actualVersion: Int64 = current["local_version"]
            let deletedAt: Date? = current["deleted_at"]
            guard deletedAt == nil else { throw LocalDataError.recordNotFound }
            guard actualVersion == command.expectedVersion else {
                throw LocalDataError.versionConflict(expected: command.expectedVersion, actual: actualVersion)
            }
            try db.execute(
                sql: """
                    UPDATE local_records
                    SET local_version = local_version + 1, updated_at = ?, deleted_at = ?
                    WHERE id = ? AND deleted_at IS NULL AND local_version = ?
                    """,
                arguments: [
                    command.deletedAt,
                    command.deletedAt,
                    command.id.uuidString,
                    command.expectedVersion
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ?",
                arguments: [command.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.tombstone(from: row)
        }
    }

    func record(id: UUID) throws -> LocalRecord? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ? AND deleted_at IS NULL",
                arguments: [id.uuidString]
            ) else { return nil }
            return try Self.record(from: row)
        }
    }

    func records(profileID: UUID, monthKey: String) throws -> [LocalRecord] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_records
                    WHERE profile_id = ? AND deleted_at IS NULL AND record_date LIKE ?
                    ORDER BY record_date DESC, record_time DESC, created_at DESC, id DESC
                    """,
                arguments: [profileID.uuidString, "\(monthKey)-%"]
            ).map(Self.record(from:))
        }
    }

    func recordTombstone(id: UUID) throws -> LocalRecordTombstone? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ? AND deleted_at IS NOT NULL",
                arguments: [id.uuidString]
            ) else { return nil }
            return try Self.tombstone(from: row)
        }
    }

    func createStaging(_ draft: LocalStagingDraft) throws -> LocalStagingRecord {
        guard LocalRecordValidation.supportedDomainKeys.contains(draft.domainKey) else {
            throw LocalDataError.invalidRecord
        }
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_staging_records (
                        id, profile_id, domain_key, status, confidence, title, summary,
                        payload_json, record_date, record_time, image_path, image_hash,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    draft.id,
                    draft.profileID.uuidString,
                    draft.domainKey,
                    draft.status.rawValue,
                    draft.confidence,
                    draft.title,
                    draft.summary,
                    draft.payloadJSON,
                    draft.recordDate,
                    draft.recordTime,
                    draft.imagePath,
                    draft.imageHash,
                    draft.createdAt,
                    draft.createdAt
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_staging_records WHERE id = ?",
                arguments: [draft.id]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.staging(from: row)
        }
    }

    func staging(id: String) throws -> LocalStagingRecord? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_staging_records WHERE id = ?",
                arguments: [id]
            ) else { return nil }
            return try Self.staging(from: row)
        }
    }

    func stagingRecords(profileID: UUID) throws -> [LocalStagingRecord] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_staging_records
                    WHERE profile_id = ? AND status = 'pending_review'
                    ORDER BY record_date DESC, record_time DESC, created_at DESC, id DESC
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.staging(from:))
        }
    }

    func archiveStaging(
        id: String,
        recordID: UUID,
        updatedAt: Date,
        profileID: UUID
    ) throws -> LocalRecord {
        try database.writer.write { db in
            guard let stagingRow = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_staging_records WHERE id = ?",
                arguments: [id]
            ) else { throw LocalDataError.recordNotFound }
            try Self.assertProfile(stagingRow, profileID: profileID)
            let status: String = stagingRow["status"]
            let targetRecordID: String? = stagingRow["target_record_id"]
            if status == LocalStagingRecordStatus.archived.rawValue,
               let targetRecordID,
               let targetRow = try Row.fetchOne(
                   db,
                   sql: "SELECT * FROM local_records WHERE id = ? AND profile_id = ? AND deleted_at IS NULL",
                   arguments: [targetRecordID, profileID.uuidString]
               ) {
                return try Self.record(from: targetRow)
            }
            guard status == LocalStagingRecordStatus.pendingReview.rawValue else {
                throw LocalDataError.invalidRecord
            }
            let stagingProfileID: String = stagingRow["profile_id"]
            let domainKey: String = stagingRow["domain_key"]
            let title: String = stagingRow["title"]
            let summary: String = stagingRow["summary"]
            let payloadJSON: String = stagingRow["payload_json"]
            let recordDate: String = stagingRow["record_date"]
            let recordTime: String? = stagingRow["record_time"]
            let imagePath: String? = stagingRow["image_path"]
            let imageHash: String? = stagingRow["image_hash"]
            let createdAt: Date = stagingRow["created_at"]
            let payload = try LocalRecordCodec.normalizedPayload(
                domainKey: domainKey,
                payload: try LocalRecordCodec.decode(payloadJSON)
            )
            let normalizedPayloadJSON = try LocalRecordCodec.encode(payload)

            try db.execute(
                sql: """
                    INSERT INTO local_records (
                        id, profile_id, domain_key, title, summary, payload_json,
                        record_date, record_time, note, image_path, image_hash,
                        local_version, created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, NULL)
                    """,
                arguments: [
                    recordID.uuidString,
                    stagingProfileID,
                    domainKey,
                    title,
                    summary,
                    normalizedPayloadJSON,
                    recordDate,
                    recordTime,
                    imagePath,
                    imageHash,
                    createdAt,
                    updatedAt
                ]
            )
            try db.execute(
                sql: """
                    UPDATE local_staging_records
                    SET status = 'archived', target_record_id = ?, resolved_action = 'confirmed',
                        resolved_at = ?, image_path = NULL, image_hash = NULL, updated_at = ?
                    WHERE id = ? AND status = 'pending_review'
                    """,
                arguments: [recordID.uuidString, updatedAt, updatedAt, id]
            )
            guard let recordRow = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_records WHERE id = ?",
                arguments: [recordID.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            return try Self.record(from: recordRow)
        }
    }

    func discardStaging(id: String, updatedAt: Date, profileID: UUID) throws {
        try database.writer.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_staging_records WHERE id = ?",
                arguments: [id]
            ) else { throw LocalDataError.recordNotFound }
            try Self.assertProfile(row, profileID: profileID)
            let status: String = row["status"]
            guard status == LocalStagingRecordStatus.pendingReview.rawValue else {
                throw LocalDataError.invalidRecord
            }
            try db.execute(
                sql: """
                    UPDATE local_staging_records
                    SET status = 'discarded', resolved_action = 'discarded', resolved_at = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [updatedAt, updatedAt, id]
            )
        }
    }

    private static func assertProfile(_ row: Row, profileID: UUID) throws {
        guard let stored: String = row["profile_id"], stored == profileID.uuidString else {
            throw LocalDataError.invalidIdentifier
        }
    }

    private static func record(from row: Row) throws -> LocalRecord {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let domainKey: String = row["domain_key"],
              let title: String = row["title"],
              let summary: String = row["summary"],
              let payloadJSON: String = row["payload_json"],
              let recordDate: String = row["record_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalRecord(
            id: id,
            profileID: profileID,
            domainKey: domainKey,
            title: title,
            summary: summary,
            payloadJSON: payloadJSON,
            recordDate: recordDate,
            recordTime: row["record_time"],
            note: row["note"],
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func tombstone(from row: Row) throws -> LocalRecordTombstone {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let deletedAt: Date = row["deleted_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalRecordTombstone(
            id: id,
            profileID: profileID,
            localVersion: row["local_version"],
            deletedAt: deletedAt,
            imagePath: row["image_path"]
        )
    }

    private static func staging(from row: Row) throws -> LocalStagingRecord {
        guard let id: String = row["id"],
              let profileID = UUID(uuidString: row["profile_id"]),
              let domainKey: String = row["domain_key"],
              let statusRaw: String = row["status"],
              let status = LocalStagingRecordStatus(rawValue: statusRaw),
              let title: String = row["title"],
              let summary: String = row["summary"],
              let payloadJSON: String = row["payload_json"],
              let recordDate: String = row["record_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        let targetRecordID: String? = row["target_record_id"]
        return LocalStagingRecord(
            id: id,
            profileID: profileID,
            domainKey: domainKey,
            status: status,
            confidence: row["confidence"],
            title: title,
            summary: summary,
            payloadJSON: payloadJSON,
            recordDate: recordDate,
            recordTime: row["record_time"],
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            targetRecordID: targetRecordID.flatMap { UUID(uuidString: $0) },
            resolvedAction: row["resolved_action"],
            resolvedAt: row["resolved_at"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}
