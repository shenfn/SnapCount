import Foundation
import GRDB
import XCTest
@testable import SnapCount

final class LocalHistoryMigrationTests: XCTestCase {
    func testLF03903PersistsCursorOnlyWithBatchAndRejectsStaleIdentityAfterResume() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-history-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profile = try LocalProfileStore(database: database).activeProfile()
        var store = LocalHistoryMigrationStore(database: database)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertThrowsError(try store.startOrResume(
            profileID: profile.id, cloudUserID: "  ", expectedScopes: ["records"]
        )) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .invalidCloudIdentity)
        }
        XCTAssertThrowsError(try store.startOrResume(
            profileID: profile.id, cloudUserID: "synthetic-user-a", expectedScopes: []
        )) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .invalidExpectedScopes)
        }
        XCTAssertNil(try store.state(profileID: profile.id))
        let expectedScopes: Set<String> = ["records", "accounts"]
        let firstRun = try store.startOrResume(
            profileID: profile.id, cloudUserID: "synthetic-user-a", expectedScopes: expectedScopes, at: startedAt
        )

        let firstRecordID = UUID()
        let firstBatch = try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation,
            scope: "records", nextCursor: "records:1", importedRowCount: 1, at: startedAt.addingTimeInterval(1)
        ) { db in
            try Self.insertRecord(id: firstRecordID, profileID: profile.id, title: "第一批", db: db)
        }
        XCTAssertEqual(firstBatch.cursors.nextByScope["records"], "records:1")
        XCTAssertEqual(firstBatch.importedRowCount, 1)
        _ = try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation,
            scope: "accounts", nextCursor: "accounts:1", importedRowCount: 0
        ) { _ in }

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
            scope: "records", nextCursor: "records:2", importedRowCount: 1, at: startedAt.addingTimeInterval(2)
        ) { db in
            try Self.insertRecord(id: failedRecordID, profileID: profile.id, title: "失败批次", db: db)
        })
        let afterFailure = try XCTUnwrap(store.state(profileID: profile.id))
        XCTAssertEqual(afterFailure.cursors.nextByScope["records"], "records:1")
        XCTAssertEqual(afterFailure.cursors.nextByScope["accounts"], "accounts:1")
        XCTAssertEqual(afterFailure.importedRowCount, 1)
        let failedRecordCount = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_records WHERE id = ?", arguments: [failedRecordID.uuidString])
        }
        XCTAssertEqual(failedRecordCount, 0)

        _ = try store.pause(profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation)
        try database.writer.close()
        database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        store = LocalHistoryMigrationStore(database: database)
        let resumed = try store.startOrResume(
            profileID: profile.id, cloudUserID: "synthetic-user-a", expectedScopes: expectedScopes,
            at: startedAt.addingTimeInterval(3)
        )
        XCTAssertEqual(resumed.generation, firstRun.generation + 1)
        XCTAssertEqual(resumed.cursors.nextByScope["records"], "records:1")
        XCTAssertEqual(resumed.cursors.nextByScope["accounts"], "accounts:1")
        XCTAssertThrowsError(try store.startOrResume(
            profileID: profile.id, cloudUserID: "synthetic-user-a", expectedScopes: ["records"]
        )) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .expectedScopesChanged)
        }
        XCTAssertThrowsError(try store.complete(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: resumed.generation
        )) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .incompleteScopes)
        }

        var staleBatchWasApplied = false
        XCTAssertThrowsError(try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: firstRun.generation,
            scope: "records", nextCursor: "stale", importedRowCount: 1
        ) { _ in staleBatchWasApplied = true }) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .staleAttempt)
        }
        XCTAssertFalse(staleBatchWasApplied)
        XCTAssertThrowsError(try store.startOrResume(
            profileID: profile.id, cloudUserID: "synthetic-user-b", expectedScopes: expectedScopes
        )) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .identityMismatch)
        }

        let secondRecordID = UUID()
        _ = try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: resumed.generation,
            scope: "records", nextCursor: nil, importedRowCount: 1
        ) { db in
            try Self.insertRecord(id: secondRecordID, profileID: profile.id, title: "第二批", db: db)
        }
        _ = try store.commitBatch(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: resumed.generation,
            scope: "accounts", nextCursor: nil, importedRowCount: 0
        ) { _ in }
        let completed = try store.complete(
            profileID: profile.id, cloudUserID: "synthetic-user-a", generation: resumed.generation
        )
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.importedRowCount, 2)
        let importedRecordCount = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_records WHERE profile_id = ?", arguments: [profile.id.uuidString])
        }
        XCTAssertEqual(importedRecordCount, 2)
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
