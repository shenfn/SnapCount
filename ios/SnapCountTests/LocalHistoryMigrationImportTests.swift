import XCTest
import GRDB
@testable import SnapCount

final class LocalHistoryMigrationImportTests: XCTestCase {
    func testLF039PausedAttemptCannotImportFacts() throws {
        let source = try fixture(), target = try fixture()
        defer { cleanup(source); cleanup(target) }
        _ = try addAccount(source)
        let archive = try source.portability.exportBackup()
        let state = try ready(target)
        _ = try target.checkpoints.pause(profileID: target.profile.id, cloudUserID: state.cloudUserID, generation: state.generation)
        XCTAssertThrowsError(try target.portability.importBackupIntoActiveProfile(archive, historyMigration: state))
        XCTAssertEqual(try accountCount(target), 0)
        XCTAssertEqual(try target.checkpoints.state(profileID: target.profile.id)?.status, .paused)
    }

    func testLF039FactsAndCompletedCheckpointCommitTogetherAndCannotRepeat() throws {
        let source = try fixture(), target = try fixture()
        defer { cleanup(source); cleanup(target) }
        _ = try addAccount(source)
        let archive = try source.portability.exportBackup()
        let state = try ready(target)
        _ = try target.portability.importBackupIntoActiveProfile(archive, historyMigration: state)
        XCTAssertEqual(try accountCount(target), 1)
        XCTAssertEqual(try target.checkpoints.state(profileID: target.profile.id)?.status, .completed)
        XCTAssertThrowsError(try target.portability.importBackupIntoActiveProfile(archive, historyMigration: state))
        XCTAssertEqual(try accountCount(target), 1)
    }

    func testLF039CheckpointCompletionFailureRollsBackImportedFacts() throws {
        let source = try fixture(), target = try fixture()
        defer { cleanup(source); cleanup(target) }
        _ = try addAccount(source)
        let state = try ready(target)
        try target.database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER synthetic_checkpoint_failure BEFORE UPDATE ON local_history_migrations
                WHEN NEW.status = 'completed' BEGIN SELECT RAISE(ABORT, 'synthetic checkpoint failure'); END;
                """)
        }
        XCTAssertThrowsError(try target.portability.importBackupIntoActiveProfile(source.portability.exportBackup(), historyMigration: state))
        XCTAssertEqual(try accountCount(target), 0)
        XCTAssertEqual(try target.checkpoints.state(profileID: target.profile.id)?.status, .running)
    }

    func testLF039OldGenerationCannotCommitAfterResuming() throws {
        let source = try fixture(), target = try fixture()
        defer { cleanup(source); cleanup(target) }
        _ = try addAccount(source)
        let old = try ready(target)
        let newer = try target.checkpoints.startOrResume(profileID: target.profile.id,
            cloudUserID: old.cloudUserID, expectedScopes: old.expectedScopes)
        XCTAssertGreaterThan(newer.generation, old.generation)
        XCTAssertThrowsError(try target.portability.importBackupIntoActiveProfile(source.portability.exportBackup(), historyMigration: old))
        XCTAssertEqual(try accountCount(target), 0)
    }

    private struct Fixture {
        let directory: URL
        let database: LocalDatabase
        let profile: LocalProfile
        let portability: LocalCompleteBackupPortability
        let checkpoints: LocalHistoryMigrationStore
    }
    private func fixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        return Fixture(directory: directory, database: database,
            profile: try LocalProfileStore(database: database).activeProfile(),
            portability: LocalCompleteBackupPortability(database: database, imageStore: images),
            checkpoints: LocalHistoryMigrationStore(database: database))
    }
    private func cleanup(_ fixture: Fixture) { try? FileManager.default.removeItem(at: fixture.directory) }
    private func addAccount(_ fixture: Fixture) throws -> LocalAccount {
        try LocalExpenseRepository(database: fixture.database).createAccount(LocalAccountDraft(id: UUID(),
            profileID: fixture.profile.id, name: "synthetic", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10000, createdAt: Date()))
    }
    private func accountCount(_ fixture: Fixture) throws -> Int {
        try LocalExpenseRepository(database: fixture.database).accounts(profileID: fixture.profile.id).count
    }
    private func ready(_ fixture: Fixture) throws -> LocalHistoryMigrationState {
        let scopes = Set(LocalHistorySourceTable.allCases.map(\.rawValue))
        var state = try fixture.checkpoints.startOrResume(profileID: fixture.profile.id,
            cloudUserID: UUID().uuidString, expectedScopes: scopes)
        for scope in scopes {
            state = try fixture.checkpoints.commitBatch(profileID: fixture.profile.id, cloudUserID: state.cloudUserID,
                generation: state.generation, scope: scope, nextCursor: nil, importedRowCount: 0) { _ in }
        }
        return state
    }
}
