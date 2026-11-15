import Foundation
import GRDB

/// Cached source material is separate from user facts and cannot mark a migration completed.
final class LocalHistoryMigrationCache {
    private let database: LocalDatabase
    private let imageStore: LocalImageStore
    private let checkpoints: LocalHistoryMigrationStore
    private struct Page: Codable {
        let rows: [[String: AnyCodable]]
        let nextCursor: String?
    }
    private struct Image: Codable { let path: String; let hash: String }

    init(database: LocalDatabase, imageStore: LocalImageStore) {
        self.database = database; self.imageStore = imageStore
        self.checkpoints = LocalHistoryMigrationStore(database: database)
    }

    func begin(profileID: UUID, cloudUserID: String) throws -> LocalHistoryMigrationState {
        let state = try checkpoints.startOrResume(profileID: profileID, cloudUserID: cloudUserID,
            expectedScopes: Set(LocalHistorySourceTable.allCases.map(\.rawValue)))
        try removeInterruptedImageWrites()
        try cleanupImageQueue(profileID: profileID)
        return state
    }

    /// Explicit restart after a source-change report. Only source caches/checkpoints are reset.
    func restartSource(_ state: LocalHistoryMigrationState) throws {
        try database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT cloud_user_id,generation,status FROM local_history_migrations WHERE profile_id = ?", arguments: [state.profileID.uuidString]),
                  (row["cloud_user_id"] as String) == state.cloudUserID,
                  (row["generation"] as Int64) == state.generation else { throw LocalHistoryMigrationError.staleAttempt }
            guard (row["status"] as String) != "completed" else { throw LocalHistoryMigrationError.alreadyCompleted }
            try self.enqueueCacheImages(db, state: state)
            try db.execute(sql: "DELETE FROM local_history_migration_cache WHERE profile_id = ? AND cloud_user_id = ?", arguments: [state.profileID.uuidString, state.cloudUserID])
            try db.execute(sql: "UPDATE local_history_migrations SET generation=generation+1,status='paused',source_cursors_json=?,imported_row_count=0,updated_at=?,completed_at=NULL WHERE profile_id=? AND cloud_user_id=?", arguments: ["{\"nextByScope\":{},\"completedScopes\":[]}", Date(), state.profileID.uuidString, state.cloudUserID])
        }
        try cleanupImageQueue(profileID: state.profileID)
        try removeInterruptedImageWrites()
    }

    func state(profileID: UUID) throws -> LocalHistoryMigrationState? { try checkpoints.state(profileID: profileID) }

    func assertCurrent(_ state: LocalHistoryMigrationState) throws {
        try database.writer.read { try self.assertCurrent($0, state: state) }
    }

    func page(state: LocalHistoryMigrationState, table: LocalHistorySourceTable, afterID: String?) throws -> LocalHistorySourcePage? {
        guard let data = try read(state: state, kind: "page", key: Self.pageKey(table, afterID)) else { return nil }
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard page.rows.count <= 100 else { throw LocalDataError.invalidRecord }
        return LocalHistorySourcePage(rows: page.rows, nextCursor: page.nextCursor)
    }

    func savePage(state: LocalHistoryMigrationState, table: LocalHistorySourceTable, afterID: String?, page: LocalHistorySourcePage) throws {
        let payload = try JSONEncoder().encode(Page(rows: page.rows, nextCursor: page.nextCursor))
        guard payload.count <= 16 * 1024 * 1024 else { throw LocalCompleteBackupError.archiveTooLarge }
        // Source page and cursor are in one database transaction; no cursor can outrun its bytes.
        _ = try checkpoints.commitBatch(profileID: state.profileID, cloudUserID: state.cloudUserID,
            generation: state.generation, scope: table.rawValue, nextCursor: page.nextCursor, importedRowCount: 0) { db in
            try self.write(db, state: state, kind: "page", key: Self.pageKey(table, afterID), payload: payload)
        }
    }

    func image(state: LocalHistoryMigrationState, sourcePath: String) throws -> Data? {
        guard let payload = try read(state: state, kind: "image", key: sourcePath) else { return nil }
        let image = try JSONDecoder().decode(Image.self, from: payload)
        let bytes = try imageStore.data(at: image.path)
        guard bytes.count <= 16 * 1024 * 1024, LocalImageStore.sha256(bytes) == image.hash else { throw LocalCompleteBackupError.invalidImage(sourcePath) }
        return bytes
    }

    func saveImage(state: LocalHistoryMigrationState, sourcePath: String, data: Data) throws {
        guard !data.isEmpty, data.count <= 16 * 1024 * 1024 else { throw LocalCompleteBackupError.archiveTooLarge }
        var createdPath: String?
        do {
            try database.writer.write { db in
                try self.assertCurrent(db, state: state)
                let reference = try self.imageStore.save(data: data, owner: UUID().uuidString, bucket: "history-cache")
                createdPath = reference.path
                let payload = try JSONEncoder().encode(Image(path: reference.path, hash: reference.hash))
                try self.write(db, state: state, kind: "image", key: sourcePath, payload: payload)
            }
        } catch {
            if let path = createdPath { try? imageStore.remove(path: path) }
            throw error
        }
    }

    func pause(_ state: LocalHistoryMigrationState) throws {
        _ = try checkpoints.pause(profileID: state.profileID, cloudUserID: state.cloudUserID, generation: state.generation)
    }

    /// Only call after source recheck and successful atomic fact import.
    func completeAfterImport(_ state: LocalHistoryMigrationState) throws {
        _ = try checkpoints.complete(profileID: state.profileID, cloudUserID: state.cloudUserID, generation: state.generation)
        try cleanupAfterCompletion(state)
    }

    func cleanupAfterCompletion(_ state: LocalHistoryMigrationState) throws {
        try database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT cloud_user_id,generation,status FROM local_history_migrations WHERE profile_id = ?", arguments: [state.profileID.uuidString]),
                  (row["cloud_user_id"] as String) == state.cloudUserID, (row["generation"] as Int64) == state.generation,
                  (row["status"] as String) == "completed" else { throw LocalHistoryMigrationError.staleAttempt }
            try self.enqueueCacheImages(db, state: state)
            try db.execute(sql: "DELETE FROM local_history_migration_cache WHERE profile_id=? AND cloud_user_id=?", arguments: [state.profileID.uuidString, state.cloudUserID])
        }
        try cleanupImageQueue(profileID: state.profileID)
        try removeInterruptedImageWrites()
    }

    private func enqueueCacheImages(_ db: Database, state: LocalHistoryMigrationState) throws {
        let payloads = try String.fetchAll(db, sql: "SELECT payload_json FROM local_history_migration_cache WHERE profile_id=? AND cloud_user_id=? AND cache_kind='image'", arguments: [state.profileID.uuidString, state.cloudUserID])
        for json in payloads {
            let image = try JSONDecoder().decode(Image.self, from: Data(json.utf8))
            guard image.path.hasPrefix("history-cache/") else { throw LocalDataError.invalidRecord }
            try db.execute(sql: "INSERT OR IGNORE INTO local_image_cleanups(id,profile_id,image_path,attempt_count,created_at,updated_at) VALUES(?,?,?,0,?,?)", arguments: [UUID().uuidString, state.profileID.uuidString, image.path, Date(), Date()])
        }
    }

    private func cleanupImageQueue(profileID: UUID) throws {
        let paths = try database.writer.read { db in
            try String.fetchAll(db, sql: "SELECT image_path FROM local_image_cleanups WHERE profile_id=? AND image_path LIKE 'history-cache/%'", arguments: [profileID.uuidString])
        }
        for path in paths {
            do {
                try imageStore.remove(path: path)
                try database.writer.write { db in try db.execute(sql: "DELETE FROM local_image_cleanups WHERE profile_id=? AND image_path=?", arguments: [profileID.uuidString, path]) }
            } catch { /* Keep the persisted cleanup item for the existing cleanup runner. */ }
        }
    }

    private func removeInterruptedImageWrites() throws {
        // The writer lock also covers saveImage's unique file creation and metadata commit.
        try database.writer.write { db in
            let registered = Set(try String.fetchAll(db, sql: "SELECT json_extract(payload_json,'$.path') FROM local_history_migration_cache WHERE cache_kind='image'"))
            let directory = self.imageStore.url(for: "history-cache/probe").deletingLastPathComponent()
            guard directory.lastPathComponent == "history-cache" else { throw LocalDataError.invalidIdentifier }
            guard FileManager.default.fileExists(atPath: directory.path) else { return }
            for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                guard file.lastPathComponent.range(of: "^[0-9a-f]{64}\\.jpg$", options: .regularExpression) != nil else { continue }
                let path = "history-cache/" + file.lastPathComponent
                if !registered.contains(path) { try self.imageStore.remove(path: path) }
            }
        }
    }

    private func read(state: LocalHistoryMigrationState, kind: String, key: String) throws -> Data? {
        try database.writer.read { db in
            try self.assertCurrent(db, state: state)
            guard let row = try Row.fetchOne(db, sql: "SELECT cloud_user_id, payload_json FROM local_history_migration_cache WHERE profile_id = ? AND cache_kind = ? AND cache_key = ?", arguments: [state.profileID.uuidString, kind, key]) else { return nil }
            guard (row["cloud_user_id"] as String) == state.cloudUserID else { throw LocalHistoryMigrationError.identityMismatch }
            return Data((row["payload_json"] as String).utf8)
        }
    }

    private func write(_ db: Database, state: LocalHistoryMigrationState, kind: String, key: String, payload: Data) throws {
        guard let json = String(data: payload, encoding: .utf8) else { throw LocalDataError.invalidRecord }
        let existing = try Int.fetchOne(db, sql: "SELECT COALESCE(SUM(length(CAST(payload_json AS BLOB))),0) FROM local_history_migration_cache WHERE profile_id = ? AND NOT(cache_kind = ? AND cache_key = ?)", arguments: [state.profileID.uuidString, kind, key]) ?? 0
        guard existing + payload.count <= 180 * 1024 * 1024 else { throw LocalCompleteBackupError.archiveTooLarge }
        try db.execute(sql: "INSERT INTO local_history_migration_cache (profile_id, cloud_user_id, cache_kind, cache_key, payload_json, updated_at) VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(profile_id,cache_kind,cache_key) DO UPDATE SET cloud_user_id=excluded.cloud_user_id,payload_json=excluded.payload_json,updated_at=excluded.updated_at", arguments: [state.profileID.uuidString, state.cloudUserID, kind, key, json, Date()])
    }

    private func assertCurrent(_ db: Database, state: LocalHistoryMigrationState) throws {
        guard let row = try Row.fetchOne(db, sql: "SELECT cloud_user_id,generation,status FROM local_history_migrations WHERE profile_id = ?", arguments: [state.profileID.uuidString]),
              (row["cloud_user_id"] as String) == state.cloudUserID,
              (row["generation"] as Int64) == state.generation,
              (row["status"] as String) == LocalHistoryMigrationStatus.running.rawValue else { throw LocalHistoryMigrationError.staleAttempt }
    }

    private static func pageKey(_ table: LocalHistorySourceTable, _ after: String?) -> String { table.rawValue + "/" + (after?.lowercased() ?? "start") }
}
