import Foundation
import GRDB

protocol LocalBindingScopeProvider {
    func fetchScopes(cloudUserID: String) async throws -> [String]
}

struct DomainRepositoryBindingScopeProvider: LocalBindingScopeProvider {
    let repository: DomainRepositoryProtocol
    let accessTokenProvider: () async throws -> String

    func fetchScopes(cloudUserID: String) async throws -> [String] {
        let accessToken = try await accessTokenProvider()
        let definitions = try await repository.fetchDefinitions(accessToken: accessToken)
        return definitions.map(\.id)
    }
}

protocol LocalBindingRepository: AnyObject {
    func activeProfile() throws -> LocalProfile
    func workspaceSummary(profileID: UUID) throws -> LocalWorkspaceSummary
    func syncState(profileID: UUID) throws -> LocalSyncState
    func confirmBinding(profileID: UUID, cloudUserID: String) throws -> LocalSyncState
    func disableSync(profileID: UUID) throws -> LocalSyncState
}

struct LocalBindingPreviewUseCase {
    private let repository: LocalBindingRepository
    private let scopeProvider: LocalBindingScopeProvider

    init(
        repository: LocalBindingRepository,
        scopeProvider: LocalBindingScopeProvider
    ) {
        self.repository = repository
        self.scopeProvider = scopeProvider
    }

    func makePreview(
        cloudUserID: String,
        email: String?
    ) async throws -> LocalBindingPreview {
        let profile = try repository.activeProfile()
        let summary = try repository.workspaceSummary(profileID: profile.id)
        let state = try repository.syncState(profileID: profile.id)
        let binding = resolvedBinding(state.binding, candidateUserID: cloudUserID)

        let remoteScope: [String]
        if case .mismatch = binding {
            remoteScope = []
        } else {
            remoteScope = try await scopeProvider.fetchScopes(cloudUserID: cloudUserID)
        }

        let options: [LocalBindingOption] = {
            if case .mismatch = binding {
                return [.deferSync, .signOut]
            }
            return [.deferSync, .mergeAndEnable, .signOut]
        }()

        return LocalBindingPreview(
            workspaceID: summary.workspaceID,
            candidateCloudUserID: cloudUserID,
            cloudEmail: email,
            currentBinding: binding,
            localExpenseCount: summary.expenseCount,
            localAccountCount: summary.accountCount,
            pendingOutboxCount: summary.pendingOutboxCount,
            remoteScope: remoteScope,
            options: options
        )
    }

    func confirmBinding(cloudUserID: String) throws -> LocalSyncState {
        let profile = try repository.activeProfile()
        return try repository.confirmBinding(profileID: profile.id, cloudUserID: cloudUserID)
    }

    private func resolvedBinding(
        _ binding: LocalWorkspaceBinding,
        candidateUserID: String
    ) -> LocalWorkspaceBinding {
        guard case .bound(let boundUserID) = binding else { return binding }
        guard boundUserID != candidateUserID else { return binding }
        return .mismatch(boundUserID: boundUserID, signedInUserID: candidateUserID)
    }
}

extension LocalProfileStore: LocalBindingRepository {
    func isCurrentSyncAttempt(profileID: UUID, cloudUserID: String, attemptID: UUID) throws -> Bool {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT p.cloud_user_id, p.sync_enabled, s.active_attempt_id, s.conflict_status
                    FROM local_profiles AS p
                    JOIN local_sync_state AS s ON s.profile_id = p.id
                    WHERE p.id = ?
                    """,
                arguments: [profileID.uuidString]
            ) else { throw LocalSyncError.invalidWorkspace }
            let boundUserID: String? = row["cloud_user_id"]
            let syncEnabled: Bool = row["sync_enabled"] ?? false
            let activeAttempt: String? = row["active_attempt_id"]
            let conflictStatus: String = row["conflict_status"] ?? "none"
            return boundUserID == cloudUserID
                && syncEnabled
                && activeAttempt == attemptID.uuidString
                && conflictStatus == "none"
        }
    }

    func syncCheckpoint(profileID: UUID) throws -> LocalSyncCheckpoint {
        let state = try syncState(profileID: profileID)
        return LocalSyncCheckpoint(
            workspaceID: profileID,
            syncGeneration: state.syncGeneration,
            pullCursor: state.pullCursor,
            lastSuccessfulSyncAt: state.lastSuccessfulSyncAt,
            activeAttemptID: state.activeAttemptID,
            pendingMutationCount: state.pendingMutationCount
        )
    }

    func workspaceSummary(profileID: UUID) throws -> LocalWorkspaceSummary {
        try database.writer.read { db in
            guard try String.fetchOne(
                db,
                sql: "SELECT id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) != nil else {
                throw LocalSyncError.invalidWorkspace
            }

            let expenseCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_expenses WHERE profile_id = ? AND deleted_at IS NULL",
                arguments: [profileID.uuidString]
            ) ?? 0
            let accountCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_accounts WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) ?? 0
            let pendingOutboxCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_outbox_operations WHERE profile_id = ? AND status <> 'sent'",
                arguments: [profileID.uuidString]
            ) ?? 0
            return LocalWorkspaceSummary(
                workspaceID: profileID,
                expenseCount: expenseCount,
                accountCount: accountCount,
                pendingOutboxCount: pendingOutboxCount
            )
        }
    }

    func syncState(profileID: UUID) throws -> LocalSyncState {
        try database.writer.write { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT cloud_user_id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) else {
                throw LocalSyncError.invalidWorkspace
            }
            try ensureSyncState(db: db, profileID: profileID)
            let boundUserID: String? = profileRow["cloud_user_id"]
            return try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
        }
    }

    func confirmBinding(profileID: UUID, cloudUserID: String) throws -> LocalSyncState {
        try database.writer.write { db in
            guard try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) == 1 else {
                throw LocalSyncError.invalidWorkspace
            }
            let currentUserID: String? = try String.fetchOne(
                db,
                sql: "SELECT cloud_user_id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            )
            if let currentUserID, currentUserID != cloudUserID {
                throw LocalSyncError.bindingMismatch(
                    boundUserID: currentUserID,
                    candidateUserID: cloudUserID
                )
            }

            try ensureSyncState(db: db, profileID: profileID)
            let generation = (try Int64.fetchOne(
                db,
                sql: "SELECT sync_generation FROM local_sync_state WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) ?? 0) + 1
            try db.execute(
                sql: """
                    UPDATE local_profiles
                    SET cloud_user_id = ?, sync_enabled = 1
                    WHERE id = ?
                    """,
                arguments: [cloudUserID, profileID.uuidString]
            )
            try db.execute(
                sql: """
                    UPDATE local_sync_state
                    SET sync_generation = ?, sync_status = 'ready', active_attempt_id = NULL
                    WHERE profile_id = ?
                    """,
                arguments: [generation, profileID.uuidString]
            )
            return try syncState(db: db, profileID: profileID, boundUserID: cloudUserID)
        }
    }

    func disableSync(profileID: UUID) throws -> LocalSyncState {
        try database.writer.write { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT cloud_user_id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) else {
                throw LocalSyncError.invalidWorkspace
            }
            let boundUserID: String? = profileRow["cloud_user_id"]
            try ensureSyncState(db: db, profileID: profileID)
            let generation = (try Int64.fetchOne(
                db,
                sql: "SELECT sync_generation FROM local_sync_state WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) ?? 0) + 1
            try db.execute(
                sql: "UPDATE local_profiles SET sync_enabled = 0 WHERE id = ?",
                arguments: [profileID.uuidString]
            )
            try db.execute(
                sql: """
                    UPDATE local_sync_state
                    SET sync_generation = ?, sync_status = 'disabled', active_attempt_id = NULL
                    WHERE profile_id = ?
                    """,
                arguments: [generation, profileID.uuidString]
            )
            return try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
        }
    }

    func updateCheckpoint(
        profileID: UUID,
        pullCursor: String?,
        attemptID: UUID?,
        lastSuccessfulSyncAt: Date?
    ) throws -> LocalSyncCheckpoint {
        try database.writer.write { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT cloud_user_id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) else {
                throw LocalSyncError.invalidWorkspace
            }
            let boundUserID: String? = profileRow["cloud_user_id"]
            try ensureSyncState(db: db, profileID: profileID)
            try db.execute(
                sql: """
                    UPDATE local_sync_state
                    SET pull_cursor = ?, active_attempt_id = ?, last_successful_sync_at = ?
                    WHERE profile_id = ?
                    """,
                arguments: [
                    pullCursor,
                    attemptID?.uuidString,
                    lastSuccessfulSyncAt,
                    profileID.uuidString
                ]
            )
            let state = try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
            return LocalSyncCheckpoint(
                workspaceID: profileID,
                syncGeneration: state.syncGeneration,
                pullCursor: state.pullCursor,
                lastSuccessfulSyncAt: state.lastSuccessfulSyncAt,
                activeAttemptID: state.activeAttemptID,
                pendingMutationCount: state.pendingMutationCount
            )
        }
    }

    func canUploadOutbox(profileID: UUID, cloudUserID: String) throws -> Bool {
        let state = try syncState(profileID: profileID)
        guard case .bound(let boundUserID) = state.binding,
              boundUserID == cloudUserID,
              state.status != .disabled,
              state.conflictState != .unresolved else {
            return false
        }
        return true
    }

    func beginSync(profileID: UUID, cloudUserID: String, attemptID: UUID = UUID()) throws -> LocalSyncState {
        try database.writer.write { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT cloud_user_id, sync_enabled FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ) else {
                throw LocalSyncError.invalidWorkspace
            }
            let boundUserID: String? = profileRow["cloud_user_id"]
            let syncEnabled: Bool = profileRow["sync_enabled"] ?? false
            guard boundUserID == cloudUserID, syncEnabled else {
                throw LocalSyncError.syncNotAuthorized
            }
            try ensureSyncState(db: db, profileID: profileID)
            let state = try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
            guard state.conflictState == .none else { throw LocalSyncError.syncNotAuthorized }
            try db.execute(
                sql: """
                    UPDATE local_sync_state
                    SET sync_status = 'syncing', active_attempt_id = ?
                    WHERE profile_id = ? AND sync_generation = ?
                    """,
                arguments: [attemptID.uuidString, profileID.uuidString, state.syncGeneration]
            )
            return try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
        }
    }

    func completeSync(
        profileID: UUID,
        attemptID: UUID,
        pullCursor: String?,
        completedAt: Date
    ) throws -> LocalSyncState {
        try database.writer.write { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT cloud_user_id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ),
            let boundUserID: String = profileRow["cloud_user_id"],
            let activeAttempt: String = try String.fetchOne(
                db,
                sql: "SELECT active_attempt_id FROM local_sync_state WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) else {
                throw LocalSyncError.invalidWorkspace
            }
            guard activeAttempt == attemptID.uuidString else { throw LocalSyncError.staleAttempt }
            try db.execute(
                sql: """
                    UPDATE local_sync_state
                    SET pull_cursor = ?, last_successful_sync_at = ?,
                        active_attempt_id = NULL, sync_status = 'synced'
                    WHERE profile_id = ? AND active_attempt_id = ?
                    """,
                arguments: [pullCursor, completedAt, profileID.uuidString, attemptID.uuidString]
            )
            return try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
        }
    }

    func failSync(profileID: UUID, attemptID: UUID) throws -> LocalSyncState {
        try database.writer.write { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT cloud_user_id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ),
            let boundUserID: String = profileRow["cloud_user_id"] else {
                throw LocalSyncError.invalidWorkspace
            }
            guard try String.fetchOne(
                db,
                sql: "SELECT active_attempt_id FROM local_sync_state WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) == attemptID.uuidString else { throw LocalSyncError.staleAttempt }
            try db.execute(
                sql: """
                    UPDATE local_sync_state
                    SET active_attempt_id = NULL, sync_status = 'failed'
                    WHERE profile_id = ? AND active_attempt_id = ?
                    """,
                arguments: [profileID.uuidString, attemptID.uuidString]
            )
            return try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
        }
    }

    func markSyncConflict(profileID: UUID, attemptID: UUID) throws -> LocalSyncState {
        try database.writer.write { db in
            guard let profileRow = try Row.fetchOne(
                db,
                sql: "SELECT cloud_user_id FROM local_profiles WHERE id = ?",
                arguments: [profileID.uuidString]
            ),
            let boundUserID: String = profileRow["cloud_user_id"] else {
                throw LocalSyncError.invalidWorkspace
            }
            guard try String.fetchOne(
                db,
                sql: "SELECT active_attempt_id FROM local_sync_state WHERE profile_id = ?",
                arguments: [profileID.uuidString]
            ) == attemptID.uuidString else { throw LocalSyncError.staleAttempt }
            try db.execute(
                sql: """
                    UPDATE local_sync_state
                    SET active_attempt_id = NULL, conflict_status = 'unresolved', sync_status = 'failed'
                    WHERE profile_id = ? AND active_attempt_id = ?
                    """,
                arguments: [profileID.uuidString, attemptID.uuidString]
            )
            return try syncState(db: db, profileID: profileID, boundUserID: boundUserID)
        }
    }

    private func ensureSyncState(db: Database, profileID: UUID) throws {
        try db.execute(
            sql: "INSERT OR IGNORE INTO local_sync_state (profile_id) VALUES (?)",
            arguments: [profileID.uuidString]
        )
    }

    private func syncState(
        db: Database,
        profileID: UUID,
        boundUserID: String?
    ) throws -> LocalSyncState {
        guard let row = try Row.fetchOne(
            db,
            sql: """
                SELECT sync_generation, pull_cursor, last_successful_sync_at,
                       active_attempt_id, sync_status, conflict_status
                FROM local_sync_state
                WHERE profile_id = ?
                """,
            arguments: [profileID.uuidString]
        ) else {
            throw LocalSyncError.invalidWorkspace
        }
        let pendingCount = try Int.fetchOne(
            db,
            sql: "SELECT COUNT(*) FROM local_outbox_operations WHERE profile_id = ? AND status <> 'sent'",
            arguments: [profileID.uuidString]
        ) ?? 0
        let activeAttemptID: String? = row["active_attempt_id"]
        let statusRaw: String = row["sync_status"] ?? "disabled"
        let conflictRaw: String = row["conflict_status"] ?? "none"
        let syncGeneration: Int64 = row["sync_generation"]
        let pullCursor: String? = row["pull_cursor"]
        let lastSuccessfulSyncAt: Date? = row["last_successful_sync_at"]
        return LocalSyncState(
            workspaceID: profileID,
            binding: boundUserID.map(LocalWorkspaceBinding.bound) ?? .unbound,
            status: LocalSyncStatus(rawValue: statusRaw) ?? .disabled,
            conflictState: LocalConflictState(rawValue: conflictRaw) ?? .none,
            syncGeneration: syncGeneration,
            pullCursor: pullCursor,
            lastSuccessfulSyncAt: lastSuccessfulSyncAt,
            activeAttemptID: activeAttemptID.flatMap(UUID.init(uuidString:)),
            pendingMutationCount: pendingCount
        )
    }
}
