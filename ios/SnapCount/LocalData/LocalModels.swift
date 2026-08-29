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
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
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

enum LocalSyncDiagnosticPhase: String, Equatable {
    case preflight
    case transport
    case completed
    case failed
}

enum LocalSyncDiagnosticFailure: String, Equatable {
    case transport
    case notAuthorized
    case partialFailure
    case cursorExpired
    case conflict
    case invalidResponse
    case unknown
}

struct LocalSyncDiagnostic: Equatable {
    let phase: LocalSyncDiagnosticPhase
    let profileID: UUID
    let pendingOperationCount: Int
    let uploadedOperationCount: Int
    let importedRecordCount: Int
    let failure: LocalSyncDiagnosticFailure?
    let syncStatus: LocalSyncStatus?

    var summary: String {
        var parts = [
            "阶段：\(phase.title)",
            "待处理：\(pendingOperationCount)"
        ]
        if uploadedOperationCount > 0 {
            parts.append("上传：\(uploadedOperationCount)")
        }
        if importedRecordCount > 0 {
            parts.append("拉取：\(importedRecordCount)")
        }
        if let failure {
            parts.append("错误：\(failure.title)")
        }
        if let syncStatus {
            parts.append("状态：\(syncStatus.title)")
        }
        return parts.joined(separator: " · ")
    }
}

private extension LocalSyncDiagnosticPhase {
    var title: String {
        switch self {
        case .preflight: return "准备"
        case .transport: return "请求云端"
        case .completed: return "完成"
        case .failed: return "失败"
        }
    }
}

private extension LocalSyncDiagnosticFailure {
    var title: String {
        switch self {
        case .transport: return "云端请求失败"
        case .notAuthorized: return "未授权或绑定不匹配"
        case .partialFailure: return "部分操作被拒绝"
        case .cursorExpired: return "同步游标过期"
        case .conflict: return "存在数据冲突"
        case .invalidResponse: return "云端响应无效"
        case .unknown: return "未知错误"
        }
    }
}

private extension LocalSyncStatus {
    var title: String {
        switch self {
        case .disabled: return "未开启"
        case .ready: return "待同步"
        case .syncing: return "同步中"
        case .synced: return "已同步"
        case .failed: return "失败"
        }
    }
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
    case partialFailure(rejectedOperationIDs: Set<UUID>)
    case cursorExpired
    case invalidResponse
}

extension LocalSyncError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .bindingMismatch:
            return "本地 workspace 与当前账号不匹配。"
        case .invalidWorkspace:
            return "本地 workspace 不存在。"
        case .syncNotAuthorized:
            return "当前账号未授权此 workspace 同步。"
        case .staleAttempt:
            return "同步任务已过期，请重试。"
        case .remoteConflict:
            return "同步发现冲突，请处理后重试。"
        case .partialFailure:
            return "部分同步操作被云端拒绝，请检查后重试。"
        case .cursorExpired:
            return "同步记录已过期，下一次同步将重新获取完整数据。"
        case .invalidResponse:
            return "同步响应无效，请稍后重试。"
        }
    }
}
