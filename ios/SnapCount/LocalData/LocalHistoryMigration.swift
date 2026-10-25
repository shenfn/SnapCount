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
    let expectedScopes: Set<String>
    let cursors: LocalHistoryMigrationCursors
    let importedRowCount: Int
    let startedAt: Date
    let updatedAt: Date
    let completedAt: Date?
}

struct LocalHistoryMigrationCursors: Codable, Equatable {
    fileprivate(set) var nextByScope: [String: String] = [:]
    fileprivate(set) var completedScopes: Set<String> = []

    mutating func advance(scope: String, nextCursor: String?) {
        if let nextCursor {
            nextByScope[scope] = nextCursor
            completedScopes.remove(scope)
        } else {
            nextByScope.removeValue(forKey: scope)
            completedScopes.insert(scope)
        }
    }
}

enum LocalHistoryMigrationError: Error, Equatable {
    case invalidWorkspace
    case invalidCloudIdentity
    case invalidCursorScope
    case invalidExpectedScopes
    case expectedScopesChanged
    case incompleteScopes
    case identityMismatch
    case alreadyCompleted
    case staleAttempt
}

extension LocalHistoryMigrationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .identityMismatch: return "迁移缓存属于另一个云账户，请核对登录账户和本机工作区。"
        case .alreadyCompleted: return "此工作区已完成历史迁移，不能将已完成任务重新作为首次迁移。"
        case .staleAttempt: return "迁移已暂停或身份代次已变化，请重新预检后继续。"
        case .incompleteScopes: return "源数据仍有未完成的分页，不能提交迁移。"
        case .invalidCloudIdentity: return "云账户或会话无效，请重新登录后继续。"
        case .invalidWorkspace: return "迁移与当前本机工作区不匹配，尚未入账。"
        case .invalidCursorScope, .invalidExpectedScopes, .expectedScopesChanged:
            return "迁移范围或分页状态不一致，请丢弃预检后重新读取。"
        }
    }
}

/// Keeps one explicitly authorized cloud-history import identity per local workspace.
final class LocalHistoryMigrationStore {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func startOrResume(
        profileID: UUID,
        cloudUserID: String,
        expectedScopes: Set<String>,
        at now: Date = Date()
    ) throws -> LocalHistoryMigrationState {
        guard !cloudUserID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalHistoryMigrationError.invalidCloudIdentity
        }
        let normalizedScopes = Set(expectedScopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !normalizedScopes.isEmpty,
              normalizedScopes.count == expectedScopes.count,
              !normalizedScopes.contains("") else {
            throw LocalHistoryMigrationError.invalidExpectedScopes
        }
        let expectedScopesJSON = try JSONEncoder().encode(normalizedScopes.sorted())
        return try database.writer.write { db in
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
                guard current.expectedScopes == normalizedScopes else { throw LocalHistoryMigrationError.expectedScopesChanged }
                guard current.status != .completed else { throw LocalHistoryMigrationError.alreadyCompleted }
                try db.execute(sql: """
                    UPDATE local_history_migrations
                    SET generation = ?, status = 'running', updated_at = ?
                    WHERE profile_id = ?
                    """, arguments: [current.generation + 1, now, profileID.uuidString])
            } else {
                try db.execute(sql: """
                    INSERT INTO local_history_migrations (
                        profile_id, cloud_user_id, generation, status, expected_scopes_json, source_cursors_json,
                        imported_row_count, started_at, updated_at, completed_at
                    ) VALUES (?, ?, 1, 'running', ?, '{"nextByScope":{},"completedScopes":[]}', 0, ?, ?, NULL)
                    """, arguments: [profileID.uuidString, cloudUserID, String(decoding: expectedScopesJSON, as: UTF8.self), now, now])
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
        scope: String,
        nextCursor: String?,
        importedRowCount: Int,
        at now: Date = Date(),
        apply: (Database) throws -> Void
    ) throws -> LocalHistoryMigrationState {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedScope.isEmpty else {
            throw LocalHistoryMigrationError.invalidCursorScope
        }
        guard importedRowCount >= 0 else { throw LocalDataError.invalidRecord }
        return try database.writer.write { db in
            let current = try Self.fetch(profileID: profileID, database: db)
            guard current.cloudUserID == cloudUserID,
                  current.generation == generation,
                  current.status == .running else { throw LocalHistoryMigrationError.staleAttempt }
            guard current.expectedScopes.contains(normalizedScope) else {
                throw LocalHistoryMigrationError.invalidCursorScope
            }

            try apply(db)
            var cursors = current.cursors
            cursors.advance(scope: normalizedScope, nextCursor: nextCursor)
            let cursorData = try JSONEncoder().encode(cursors)
            guard let cursorsJSON = String(data: cursorData, encoding: .utf8) else {
                throw LocalDataError.invalidRecord
            }
            try db.execute(sql: """
                UPDATE local_history_migrations
                SET source_cursors_json = ?, imported_row_count = imported_row_count + ?, updated_at = ?
                WHERE profile_id = ? AND cloud_user_id = ? AND generation = ? AND status = 'running'
                """, arguments: [cursorsJSON, importedRowCount, now, profileID.uuidString, cloudUserID, generation])
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
            try Self.complete(profileID: profileID, cloudUserID: cloudUserID, generation: generation, at: now, database: db)
        }
    }

    static func assertReady(_ state: LocalHistoryMigrationState, database db: Database) throws {
        let current = try fetch(profileID: state.profileID, database: db)
        guard current.cloudUserID == state.cloudUserID, current.generation == state.generation,
              current.status == .running else { throw LocalHistoryMigrationError.staleAttempt }
        guard current.expectedScopes == state.expectedScopes,
              current.expectedScopes.isSubset(of: current.cursors.completedScopes) else { throw LocalHistoryMigrationError.incompleteScopes }
        guard current.cursors.completedScopes.isSubset(of: current.expectedScopes),
              Set(current.cursors.nextByScope.keys).isSubset(of: current.expectedScopes) else { throw LocalHistoryMigrationError.invalidCursorScope }
    }

    static func complete(profileID: UUID, cloudUserID: String, generation: Int64, at now: Date = Date(), database db: Database) throws -> LocalHistoryMigrationState {
            let current = try fetch(profileID: profileID, database: db)
            guard current.cloudUserID == cloudUserID,
                  current.generation == generation,
                  current.status == .running else { throw LocalHistoryMigrationError.staleAttempt }
            guard current.expectedScopes.isSubset(of: current.cursors.completedScopes) else {
                throw LocalHistoryMigrationError.incompleteScopes
            }
            guard current.cursors.completedScopes.isSubset(of: current.expectedScopes),
                  Set(current.cursors.nextByScope.keys).isSubset(of: current.expectedScopes) else {
                throw LocalHistoryMigrationError.invalidCursorScope
            }
            try db.execute(sql: """
                UPDATE local_history_migrations
                SET status = 'completed', updated_at = ?, completed_at = ?
                WHERE profile_id = ? AND cloud_user_id = ? AND generation = ? AND status = 'running'
                """, arguments: [now, now, profileID.uuidString, cloudUserID, generation])
            guard db.changesCount == 1 else { throw LocalHistoryMigrationError.staleAttempt }
            return try fetch(profileID: profileID, database: db)
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
        let expectedJSON: String = row["expected_scopes_json"]
        guard let expectedData = expectedJSON.data(using: .utf8),
              let expectedScopeList = try? JSONDecoder().decode([String].self, from: expectedData) else {
            throw LocalDataError.invalidRecord
        }
        let cursorJSON: String = row["source_cursors_json"]
        guard let cursorData = cursorJSON.data(using: .utf8),
              let cursors = try? JSONDecoder().decode(LocalHistoryMigrationCursors.self, from: cursorData) else {
            throw LocalDataError.invalidRecord
        }
        return LocalHistoryMigrationState(
            profileID: profileID,
            cloudUserID: row["cloud_user_id"],
            generation: row["generation"],
            status: status,
            expectedScopes: Set(expectedScopeList),
            cursors: cursors,
            importedRowCount: row["imported_row_count"],
            startedAt: startedAt,
            updatedAt: updatedAt,
            completedAt: row["completed_at"]
        )
    }
}
