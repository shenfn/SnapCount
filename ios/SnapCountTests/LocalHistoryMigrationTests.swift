import Foundation
import GRDB
import XCTest
@testable import SnapCount

final class LocalHistoryMigrationTests: XCTestCase {
    func testLF03903PersistsCursorOnlyWithBatchAndRejectsStaleIdentityAfterResume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-history-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profile = try LocalProfileStore(database: database).activeProfile()
        let store = LocalHistoryMigrationStore(database: database)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertThrowsError(try store.startOrResume(profileID: profile.id, cloudUserID: "  ")) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .invalidCloudIdentity)
        }
        XCTAssertNil(try store.state(profileID: profile.id))
        let firstRun = try store.startOrResume(profileID: profile.id, cloudUserID: "synthetic-user-a", at: startedAt)

        let firstRecordID = UUID()
        let firstBatch = try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation,
            nextCursor: "records:1", importedRowCount: 1, at: startedAt.addingTimeInterval(1)
        ) { db in
            try Self.insertRecord(id: firstRecordID, profileID: profile.id, title: "第一批", db: db)
        }
        XCTAssertEqual(firstBatch.pullCursor, "records:1")
        XCTAssertEqual(firstBatch.importedRowCount, 1)

        try database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_history_migration_batch
                BEFORE INSERT ON local_records
                WHEN NEW.title = '失败批次'
                BEGIN SELECT RAISE(ABORT, 'synthetic batch failure'); END;
                """)
        }
        let failedRecordID = UUID()
        XCTAssertThrowsError(try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation,
            nextCursor: "records:2", importedRowCount: 1, at: startedAt.addingTimeInterval(2)
        ) { db in
            try Self.insertRecord(id: failedRecordID, profileID: profile.id, title: "失败批次", db: db)
        })
        let afterFailure = try XCTUnwrap(store.state(profileID: profile.id))
        XCTAssertEqual(afterFailure.pullCursor, "records:1")
        XCTAssertEqual(afterFailure.importedRowCount, 1)
        XCTAssertEqual(try Int.fetchOne(database.writer, sql: "SELECT COUNT(*) FROM local_records WHERE id = ?", arguments: [failedRecordID.uuidString]), 0)

        _ = try store.pause(profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation)
        let resumed = try store.startOrResume(profileID: profile.id, cloudUserID: "synthetic-user-a", at: startedAt.addingTimeInterval(3))
        XCTAssertEqual(resumed.generation, firstRun.generation + 1)
        XCTAssertEqual(resumed.pullCursor, "records:1")

        var staleBatchWasApplied = false
        XCTAssertThrowsError(try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation,
            nextCursor: "stale", importedRowCount: 1
        ) { _ in staleBatchWasApplied = true }) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .staleAttempt)
        }
        XCTAssertFalse(staleBatchWasApplied)
        XCTAssertThrowsError(try store.startOrResume(profileID: profile.id, cloudUserID: "synthetic-user-b")) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .identityMismatch)
        }

        let secondRecordID = UUID()
        _ = try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: resumed.generation,
            nextCursor: nil, importedRowCount: 1
        ) { db in
            try Self.insertRecord(id: secondRecordID, profileID: profile.id, title: "第二批", db: db)
        }
        let completed = try store.complete(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: resumed.generation
        )
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.importedRowCount, 2)
        XCTAssertEqual(try Int.fetchOne(database.writer, sql: "SELECT COUNT(*) FROM local_records WHERE profile_id = ?", arguments: [profile.id.uuidString]), 2)
    }

    private static func insertRecord(id: UUID, profileID: UUID, title: String, db: Database) throws {
        try db.execute(sql: """
            INSERT INTO local_records (
                id, profile_id, domain_key, title, summary, payload_json, record_date,
                created_at, updated_at, source_kind, domain_version
            ) VALUES (?, ?, 'food', ?, 'synthetic', '{}', '2026-10-25', ?, ?, 'imported', 1)
            """, arguments: [id.uuidString, profileID.uuidString, title, Date(), Date()])
    }
}
