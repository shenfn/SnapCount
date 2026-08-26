import Foundation

struct LocalProfile: Equatable {
    let id: UUID
    let createdAt: Date
    let cloudUserID: String?
    let syncEnabled: Bool
}

struct LocalAccountDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let name: String
    let kind: String
    let currency: String
    let openingBalanceMinor: Int64
    let createdAt: Date
}

struct LocalAccount: Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let name: String
    let kind: String
    let currency: String
    let openingBalanceMinor: Int64
    let createdAt: Date
}

struct LocalExpenseDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let accountID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let createdAt: Date
}

struct LocalExpenseUpdate: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let accountID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let updatedAt: Date
}

struct LocalExpense: Equatable {
    let id: UUID
    let profileID: UUID
    let accountID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let localVersion: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct LocalExpenseTombstone: Equatable {
    let id: UUID
    let profileID: UUID
    let localVersion: Int64
    let deletedAt: Date
}

struct LocalAccountEntry: Equatable {
    let id: UUID
    let profileID: UUID
    let accountID: UUID
    let direction: String
    let amountMinor: Int64
    let entryKind: String
    let sourceKind: String
    let sourceID: UUID
    let occurredAt: Date
    let voidedAt: Date?
}

struct LocalOutboxOperation: Equatable {
    let sequence: Int64
    let operationID: UUID
    let profileID: UUID
    let aggregateKind: String
    let aggregateID: UUID
    let operationKind: String
    let aggregateVersion: Int64
    let idempotencyKey: String
    let status: String
    let attemptCount: Int
    let createdAt: Date
}

struct LocalOutboxUpload: Equatable {
    let sequence: Int64
    let operationID: UUID
    let profileID: UUID
    let aggregateKind: String
    let aggregateID: UUID
    let operationKind: String
    let aggregateVersion: Int64
    let idempotencyKey: String
    let payloadJSON: String
    let attemptCount: Int
    let createdAt: Date
}

struct LocalRemoteAccount: Equatable {
    let id: UUID
    let name: String
    let kind: String
    let currency: String
    let openingBalanceMinor: Int64
    let version: Int64
    let deletedAt: Date?
}

struct LocalRemoteExpense: Equatable {
    let id: UUID
    let accountID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let version: Int64
    let deletedAt: Date?
}

struct LocalRemoteAccountEntry: Equatable {
    let id: UUID
    let accountID: UUID
    let direction: String
    let amountMinor: Int64
    let entryKind: String
    let sourceID: UUID
    let voided: Bool
    let voidedReason: String?
}

struct LocalRemoteSnapshot: Equatable {
    let accounts: [LocalRemoteAccount]
    let expenses: [LocalRemoteExpense]
    let accountEntries: [LocalRemoteAccountEntry]
}

enum LocalDataError: Error, Equatable {
    case invalidAmount
    case invalidAccountKind
    case accountRequired
    case invalidIdentifier
    case invalidRecord
    case recordNotFound
    case versionConflict(expected: Int64, actual: Int64)
}

enum LocalWorkspaceBinding: Equatable {
    case unbound
    case bound(String)
    case mismatch(boundUserID: String, signedInUserID: String)
}

enum LocalSyncStatus: String, Equatable {
    case disabled
    case ready
    case syncing
    case synced
    case failed
}

enum LocalConflictState: String, Equatable {
    case none
    case unresolved
}

struct LocalSyncCheckpoint: Equatable {
    let workspaceID: UUID
    let syncGeneration: Int64
    let pullCursor: String?
    let lastSuccessfulSyncAt: Date?
    let activeAttemptID: UUID?
    let pendingMutationCount: Int
}

struct LocalSyncState: Equatable {
    let workspaceID: UUID
    let binding: LocalWorkspaceBinding
    let status: LocalSyncStatus
    let conflictState: LocalConflictState
    let syncGeneration: Int64
    let pullCursor: String?
    let lastSuccessfulSyncAt: Date?
    let activeAttemptID: UUID?
    let pendingMutationCount: Int
}

struct LocalWorkspaceSummary: Equatable {
    let workspaceID: UUID
    let expenseCount: Int
    let accountCount: Int
    let pendingOutboxCount: Int
}

enum LocalBindingOption: Equatable {
    case deferSync
    case mergeAndEnable
    case signOut
}

struct LocalBindingPreview: Equatable {
    let workspaceID: UUID
    let candidateCloudUserID: String
    let cloudEmail: String?
    let currentBinding: LocalWorkspaceBinding
    let localExpenseCount: Int
    let localAccountCount: Int
    let pendingOutboxCount: Int
    let remoteScope: [String]
    let options: [LocalBindingOption]
}

enum LocalSyncError: Error, Equatable {
    case bindingMismatch(boundUserID: String, candidateUserID: String)
    case invalidWorkspace
    case syncNotAuthorized
    case staleAttempt
    case remoteConflict
}
