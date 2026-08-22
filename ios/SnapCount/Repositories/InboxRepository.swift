import Foundation

enum InboxArchiveDomains {
    static let all: [NativeArchiveDomain] = [
        NativeArchiveDomain(id: "expense", title: "消费", systemImage: "creditcard"),
        NativeArchiveDomain(id: "income", title: "收入", systemImage: "arrow.down.circle"),
        NativeArchiveDomain(id: "sport", title: "运动", systemImage: "figure.run"),
        NativeArchiveDomain(id: "sleep", title: "睡眠", systemImage: "moon"),
        NativeArchiveDomain(id: "reading", title: "阅读", systemImage: "book"),
        NativeArchiveDomain(id: "food", title: "饮食", systemImage: "fork.knife"),
        NativeArchiveDomain(id: "wallet", title: "钱包", systemImage: "wallet.pass")
    ]
}

struct NativeStagingDiscardResult: Equatable {
    let recordId: String
    let status: String
    let cleanupStatus: String
    let cleanupQueued: Bool
}

struct NativeStagingRetryResult: Equatable {
    let recordId: String
    let route: String
    let displayText: String
    let notificationText: String
}

struct NativeStagingArchiveResult: Equatable {
    let recordId: String
    let targetRecordId: String
    let targetReference: String
    let idempotentRetry: Bool
}

protocol StagingLifecycleRepositoryProtocol {
    func discard(id: String, accessToken: String) async throws -> NativeStagingDiscardResult
    func retry(id: String, accessToken: String) async throws -> NativeStagingRetryResult
    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> NativeStagingArchiveResult
}

protocol InboxRepositoryProtocol: ScreenshotRepaymentRepositoryProtocol, StagingLifecycleRepositoryProtocol {
    func confirmStagingRepayment(
        id: String,
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        note: String,
        accessToken: String
    ) async throws -> NativeRepaymentCycle
    func resolveImageURL(path: String, accessToken: String) async throws -> URL
    func confirmPending(_ draft: NativePendingResolutionDraft, accessToken: String) async throws
}

final class InboxRepository: InboxRepositoryProtocol {
    private let remoteService: NativeDataService
    private let remoteClient: SupabaseRemoteClientProtocol

    init(
        remoteService: NativeDataService = NativeDataService(),
        remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()
    ) {
        self.remoteService = remoteService
        self.remoteClient = remoteClient
    }

    func discard(id: String, accessToken: String) async throws -> NativeStagingDiscardResult {
        try await remoteService.discardStagingRecord(id: id, accessToken: accessToken)
    }

    func retry(id: String, accessToken: String) async throws -> NativeStagingRetryResult {
        try await remoteService.retryStagingRecord(id: id, accessToken: accessToken)
    }

    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> NativeStagingArchiveResult {
        try await remoteService.archiveStagingRecord(
            record,
            domainKey: domainKey,
            accessToken: accessToken
        )
    }

    func confirmStagingRepayment(
        id: String,
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        note: String,
        accessToken: String
    ) async throws -> NativeRepaymentCycle {
        guard paidAmount > 0 else {
            throw SupabaseRemoteError.requestFailed("请输入有效的还款金额")
        }
        let row = try await remoteClient.rpc(
            RepaymentCycleRow.self,
            name: "confirm_staging_repayment",
            body: [
                "p_staging_id": AnyCodable(id),
                "p_cycle_id": AnyCodable(cycleId),
                "p_paid_amount": AnyCodable(paidAmount),
                "p_paid_at": AnyCodable(ISO8601DateFormatter().string(from: Date())),
                "p_debit_account_id": AnyCodable(nullableString(debitAccountId)),
                "p_status": AnyCodable(NSNull()),
                "p_note": AnyCodable(note)
            ],
            accessToken: accessToken
        )
        guard let cycle = row.native else {
            throw SupabaseRemoteError.requestFailed("服务端返回了无法识别的还款状态")
        }
        return cycle
    }

    func resolveImageURL(path: String, accessToken: String) async throws -> URL {
        try await remoteService.resolveImageURL(path: path, accessToken: accessToken)
    }

    func confirmPending(_ draft: NativePendingResolutionDraft, accessToken: String) async throws {
        guard let amount = draft.amount else {
            throw SupabaseRemoteError.requestFailed("金额格式不正确")
        }
        func nullable(_ value: String?) -> Any {
            guard let value, !value.isEmpty else { return NSNull() }
            return value
        }
        _ = try await remoteClient.rpc(
            AnyCodable.self,
            name: "confirm_pending_transaction_with_account",
            body: [
                "p_pending_id": AnyCodable(draft.pendingId),
                "p_entry_type": AnyCodable(draft.kind.rawValue),
                "p_amount": AnyCodable(amount),
                "p_merchant_or_source_name": AnyCodable(nullable(draft.merchantOrSourceName)),
                "p_platform": AnyCodable(nullable(draft.kind == .expense ? draft.platform : nil)),
                "p_category": AnyCodable(nullable(draft.kind == .expense ? draft.category : nil)),
                "p_payment_method": AnyCodable(nullable(draft.kind == .expense ? draft.paymentMethod : nil)),
                "p_income_category": AnyCodable(nullable(draft.kind == .income ? draft.incomeCategory : nil)),
                "p_account_id": AnyCodable(nullable(draft.accountId))
            ],
            accessToken: accessToken
        )
    }

    private func nullableString(_ value: String?) -> Any {
        guard let value, !value.isEmpty else { return NSNull() }
        return value
    }
}
