import Foundation

struct LocalSyncTransportResult: Equatable {
    let remoteArchive: Data?
    let nextPullCursor: String?
    let remoteSnapshot: LocalRemoteSnapshot?
    let acceptedOperationIDs: [UUID]?
    let conflictedExpenseIDs: Set<UUID>

    init(remoteArchive: Data? = nil, nextPullCursor: String? = nil, remoteSnapshot: LocalRemoteSnapshot? = nil, acceptedOperationIDs: [UUID]? = nil, conflictedExpenseIDs: Set<UUID> = []) {
        self.remoteArchive = remoteArchive
        self.nextPullCursor = nextPullCursor
        self.remoteSnapshot = remoteSnapshot
        self.acceptedOperationIDs = acceptedOperationIDs
        self.conflictedExpenseIDs = conflictedExpenseIDs
    }
}

protocol LocalSyncTransport {
    func synchronize(
        cloudUserID: String,
        profileID: UUID,
        pullCursor: String?,
        uploads: [LocalOutboxUpload]
    ) async throws -> LocalSyncTransportResult
}

protocol LocalSyncStateStore: AnyObject {
    func syncCheckpoint(profileID: UUID) throws -> LocalSyncCheckpoint
    func isCurrentSyncAttempt(profileID: UUID, cloudUserID: String, attemptID: UUID) throws -> Bool
    func beginSync(profileID: UUID, cloudUserID: String, attemptID: UUID) throws -> LocalSyncState
    func completeSync(profileID: UUID, attemptID: UUID, pullCursor: String?, completedAt: Date) throws -> LocalSyncState
    func failSync(profileID: UUID, attemptID: UUID) throws -> LocalSyncState
    func markSyncConflict(profileID: UUID, attemptID: UUID) throws -> LocalSyncState
}

extension LocalProfileStore: LocalSyncStateStore {}

struct LocalSyncRunResult: Equatable {
    let state: LocalSyncState
    let uploadedOperationCount: Int
    let importedRecordCount: Int
}

struct LocalSyncCoordinator {
    private let stateStore: LocalSyncStateStore
    private let repository: LocalExpenseRepositoryProtocol
    private let portability: LocalExpensePortability
    private let transport: LocalSyncTransport
    private let now: () -> Date
    private let attemptID: () -> UUID

    init(
        stateStore: LocalSyncStateStore,
        repository: LocalExpenseRepositoryProtocol,
        portability: LocalExpensePortability,
        transport: LocalSyncTransport,
        now: @escaping () -> Date = Date.init,
        attemptID: @escaping () -> UUID = UUID.init
    ) {
        self.stateStore = stateStore
        self.repository = repository
        self.portability = portability
        self.transport = transport
        self.now = now
        self.attemptID = attemptID
    }

    func synchronize(profileID: UUID, cloudUserID: String) async throws -> LocalSyncRunResult {
        let currentAttemptID = attemptID()
        _ = try stateStore.beginSync(
            profileID: profileID,
            cloudUserID: cloudUserID,
            attemptID: currentAttemptID
        )
        let uploads = try repository.pendingOutboxUploads(profileID: profileID)
        let checkpoint = try stateStore.syncCheckpoint(profileID: profileID)

        do {
            let result = try await transport.synchronize(
                cloudUserID: cloudUserID,
                profileID: profileID,
                pullCursor: checkpoint.pullCursor,
                uploads: uploads
            )
            guard try stateStore.isCurrentSyncAttempt(
                profileID: profileID,
                cloudUserID: cloudUserID,
                attemptID: currentAttemptID
            ) else {
                throw LocalSyncError.staleAttempt
            }
            var importedRecordCount = 0
            if let snapshot = result.remoteSnapshot {
                importedRecordCount = try repository.applyRemoteSnapshot(snapshot, profileID: profileID, excludingExpenseIDs: result.conflictedExpenseIDs)
            } else if let archive = result.remoteArchive {
                do {
                    let imported = try portability.importArchive(
                        archive,
                        importedAt: now(),
                        enqueueOutbox: false,
                        expectedProfileID: profileID
                    )
                    importedRecordCount = imported.insertedExpenses + imported.insertedAccounts
                } catch {
                    _ = try stateStore.markSyncConflict(profileID: profileID, attemptID: currentAttemptID)
                    throw error
                }
            }
            let acceptedIDs = result.acceptedOperationIDs ?? uploads.map(\.operationID)
            if !acceptedIDs.isEmpty {
                try repository.markOutboxSent(operationIDs: acceptedIDs)
            }
            if !result.conflictedExpenseIDs.isEmpty {
                _ = try stateStore.markSyncConflict(profileID: profileID, attemptID: currentAttemptID)
                throw LocalSyncError.remoteConflict
            }
            let state = try stateStore.completeSync(
                profileID: profileID,
                attemptID: currentAttemptID,
                pullCursor: result.nextPullCursor,
                completedAt: now()
            )
            return LocalSyncRunResult(
                state: state,
                uploadedOperationCount: uploads.count,
                importedRecordCount: importedRecordCount
            )
        } catch {
            if !(error is LocalSyncError) {
                try? repository.markOutboxFailed(
                    operationIDs: uploads.map(\.operationID),
                    error: String(describing: error)
                )
                _ = try? stateStore.failSync(profileID: profileID, attemptID: currentAttemptID)
            }
            throw error
        }
    }

}
