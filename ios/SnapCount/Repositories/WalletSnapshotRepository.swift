import Foundation

protocol WalletSnapshotRepositoryProtocol {
    func fetchUnlinked(accessToken: String) async throws -> [NativeWalletSnapshot]
    func fetch(id: String, accessToken: String) async throws -> NativeWalletSnapshot?
    func createAccount(
        from snapshot: NativeWalletSnapshot,
        userId: String,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult
    func link(
        _ snapshot: NativeWalletSnapshot,
        to account: NativeAccount,
        userId: String,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult
}

final class WalletSnapshotRepository: WalletSnapshotRepositoryProtocol {
    private let remoteClient: SupabaseRemoteClientProtocol

    init(remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()) {
        self.remoteClient = remoteClient
    }

    func fetchUnlinked(accessToken: String) async throws -> [NativeWalletSnapshot] {
        let rows = try await remoteClient.get(
            [WalletSnapshotRow].self,
            path: "rest/v1/data_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,occurred_at,domain_key,title,summary,payload_jsonb,source_image_path,source_image_hash,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at"),
                URLQueryItem(name: "domain_key", value: "eq.wallet"),
                URLQueryItem(name: "linked_account_id", value: "is.null"),
                URLQueryItem(name: "order", value: "occurred_at.desc.nullslast,created_at.desc"),
                URLQueryItem(name: "limit", value: "20")
            ],
            accessToken: accessToken
        )
        return rows.compactMap(\.native)
    }

    func fetch(id: String, accessToken: String) async throws -> NativeWalletSnapshot? {
        let rows = try await remoteClient.get(
            [WalletSnapshotRow].self,
            path: "rest/v1/data_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,occurred_at,domain_key,title,summary,payload_jsonb,source_image_path,source_image_hash,linked_account_id,account_snapshot_kind,snapshot_balance,snapshot_at"),
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        return rows.first?.native
    }

    func createAccount(
        from snapshot: NativeWalletSnapshot,
        userId: String,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult {
        try await applyWalletSnapshot(snapshot, accountId: nil, accessToken: accessToken)
    }

    func link(
        _ snapshot: NativeWalletSnapshot,
        to account: NativeAccount,
        userId: String,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult {
        try await applyWalletSnapshot(snapshot, accountId: account.id, accessToken: accessToken)
    }

    private func applyWalletSnapshot(
        _ snapshot: NativeWalletSnapshot,
        accountId: String?,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult {
        do {
            let response = try await remoteClient.rpc(
                WalletSnapshotApplyResponse.self,
                name: "apply_wallet_snapshot",
                body: [
                    "p_record_id": AnyCodable(snapshot.id),
                    "p_account_id": AnyCodable(nullable(accountId))
                ],
                accessToken: accessToken
            )
            return try response.row.nativeResult()
        } catch let error as SupabaseRemoteError {
            throw normalizedWalletSnapshotError(error)
        } catch is DecodingError {
            throw SupabaseRemoteError.requestFailed("invalid_response")
        }
    }

    private func nullable<T>(_ value: T?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func normalizedWalletSnapshotError(_ error: SupabaseRemoteError) -> SupabaseRemoteError {
        guard case .requestFailed(let message) = error else { return error }
        let reasons = [
            "not_authenticated", "wallet_snapshot_not_found", "invalid_wallet_snapshot",
            "account_not_found", "account_archived", "account_kind_mismatch",
            "snapshot_link_conflict", "repayment_evidence_conflict"
        ]
        guard let reason = reasons.first(where: { message.contains($0) }) else { return error }
        return .requestFailed(reason)
    }
}

private struct WalletSnapshotRow: Decodable {
    let id: String
    let createdAt: String
    let occurredAt: String?
    let domainKey: String
    let title: String?
    let summary: String?
    let payloadJSONB: [String: AnyCodable]?
    let sourceImagePath: String?
    let sourceImageHash: String?
    let linkedAccountId: String?
    let accountSnapshotKind: String?
    let snapshotBalance: Double?
    let snapshotAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, summary
        case createdAt = "created_at"
        case occurredAt = "occurred_at"
        case domainKey = "domain_key"
        case payloadJSONB = "payload_jsonb"
        case sourceImagePath = "source_image_path"
        case sourceImageHash = "source_image_hash"
        case linkedAccountId = "linked_account_id"
        case accountSnapshotKind = "account_snapshot_kind"
        case snapshotBalance = "snapshot_balance"
        case snapshotAt = "snapshot_at"
    }

    var native: NativeWalletSnapshot? {
        guard domainKey == "wallet" else { return nil }
        let payload = payloadJSONB ?? [:]
        let rawKind = accountSnapshotKind
            ?? payload.string("account_snapshot_kind")
            ?? (payload.string("record_kind") == "liability_snapshot" ? "liability" : "asset")
        guard let kind = NativeWalletSnapshotKind(rawValue: rawKind) else { return nil }
        let balance = snapshotBalance ?? payload.double("snapshot_balance") ?? payload.double("amount") ?? 0
        guard balance >= 0 else { return nil }
        let occurredAt = occurredAt ?? createdAt
        return NativeWalletSnapshot(
            id: id,
            title: title ?? "钱包快照",
            summary: summary ?? "",
            occurredAt: occurredAt,
            createdAt: createdAt,
            payload: payload,
            imagePath: sourceImagePath,
            imageHash: sourceImageHash,
            linkedAccountId: linkedAccountId ?? payload.string("linked_account_id"),
            kind: kind,
            balance: balance,
            snapshotAt: snapshotAt ?? occurredAt
        )
    }
}

private struct WalletAccountRow: Decodable {
    let id: String
    let name: String
    let type: String
    let institution: String?
    let last4: String?
    let currency: String?
    let initialBalance: Double?
    let currentBalance: Double?
    let snapshotBalance: Double?
    let snapshotAt: String?
    let sourceRecordTable: String?
    let sourceRecordId: String?
    let billDay: Int?
    let paymentDueDay: Int?
    let autoDebitAccountId: String?
    let autoConfirmRepayment: Bool?
    let gracePeriodDays: Int?
    let lastReconciledAt: String?
    let isDefaultExpense: Bool?
    let isDefaultIncome: Bool?
    let isArchived: Bool?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, institution, last4, currency
        case initialBalance = "initial_balance"
        case currentBalance = "current_balance"
        case snapshotBalance = "snapshot_balance"
        case snapshotAt = "snapshot_at"
        case sourceRecordTable = "source_record_table"
        case sourceRecordId = "source_record_id"
        case billDay = "bill_day"
        case paymentDueDay = "payment_due_day"
        case autoDebitAccountId = "auto_debit_account_id"
        case autoConfirmRepayment = "auto_confirm_repayment"
        case gracePeriodDays = "grace_period_days"
        case lastReconciledAt = "last_reconciled_at"
        case isDefaultExpense = "is_default_expense"
        case isDefaultIncome = "is_default_income"
        case isArchived = "is_archived"
        case sortOrder = "sort_order"
    }

    var native: NativeAccount {
        NativeAccount(
            id: id, name: name, type: NativeAccountType.normalized(type), institution: institution ?? "",
            last4: last4 ?? "", currency: currency ?? "CNY", initialBalance: initialBalance ?? 0,
            currentBalance: currentBalance ?? 0, snapshotBalance: snapshotBalance, snapshotAt: snapshotAt,
            sourceRecordTable: sourceRecordTable ?? "", sourceRecordId: sourceRecordId ?? "",
            billDay: billDay, paymentDueDay: paymentDueDay, autoDebitAccountId: autoDebitAccountId,
            autoConfirmRepayment: autoConfirmRepayment ?? false, gracePeriodDays: gracePeriodDays ?? 0,
            lastReconciledAt: lastReconciledAt, isDefaultExpense: isDefaultExpense ?? false,
            isDefaultIncome: isDefaultIncome ?? false, isArchived: isArchived ?? false,
            sortOrder: sortOrder ?? 0
        )
    }
}

private struct WalletSnapshotApplyResponse: Decodable {
    let row: WalletSnapshotApplyRow

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let object = try? container.decode(WalletSnapshotApplyRow.self) {
            row = object
            return
        }
        let rows = try container.decode([WalletSnapshotApplyRow].self)
        guard let first = rows.first else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "钱包快照命令返回空结果")
        }
        row = first
    }
}

private struct WalletSnapshotApplyRow: Decodable {
    let outcome: String
    let recordId: String?
    let linkedAccountId: String?
    let account: WalletAccountRow?
    let cycle: WalletRepaymentCycleRow?
    let payment: WalletPaymentRow?
    let balanceChanged: Bool?
    let reviewRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case outcome, account, cycle, payment
        case recordId = "record_id"
        case linkedAccountId = "linked_account_id"
        case balanceChanged = "balance_changed"
        case reviewRequired = "review_required"
    }

    func nativeResult() throws -> NativeWalletSnapshotLinkResult {
        guard let outcome = NativeWalletSnapshotOutcome(rawValue: outcome),
              let recordId,
              let linkedAccountId,
              let account,
              account.id == linkedAccountId else {
            throw SupabaseRemoteError.requestFailed("invalid_response")
        }
        return NativeWalletSnapshotLinkResult(
            accountId: linkedAccountId,
            outcome: outcome,
            recordId: recordId,
            cycle: cycle?.native,
            payment: payment?.native,
            balanceChanged: balanceChanged ?? false,
            reviewRequired: reviewRequired ?? false
        )
    }
}

private struct WalletRepaymentCycleRow: Decodable {
    let id: String
    let accountId: String
    let cycleMonth: String
    let statementStartDate: String?
    let statementEndDate: String?
    let dueDate: String?
    let status: String
    let autoDebitAccountId: String?
    let autoConfirmRepayment: Bool?
    let source: String?
    let evidenceRecordId: String?
    let confidence: Double?
    let note: String?
    let confirmedAt: String?
    let statementAmount: Double?
    let paidAmount: Double?
    let remainingAmount: Double?
    let carriedOverAmount: Double?
    let originalStatementAmount: Double?
    let minPaymentAmount: Double?
    let refundAppliedAmount: Double?

    enum CodingKeys: String, CodingKey {
        case id, status, source, confidence, note
        case accountId = "account_id"
        case cycleMonth = "cycle_month"
        case statementStartDate = "statement_start_date"
        case statementEndDate = "statement_end_date"
        case dueDate = "due_date"
        case autoDebitAccountId = "auto_debit_account_id"
        case autoConfirmRepayment = "auto_confirm_repayment"
        case evidenceRecordId = "evidence_record_id"
        case confirmedAt = "confirmed_at"
        case statementAmount = "statement_amount"
        case paidAmount = "paid_amount"
        case remainingAmount = "remaining_amount"
        case carriedOverAmount = "carried_over_amount"
        case originalStatementAmount = "original_statement_amount"
        case minPaymentAmount = "min_payment_amount"
        case refundAppliedAmount = "refund_applied_amount"
    }

    var native: NativeRepaymentCycle? {
        guard let status = NativeRepaymentStatus(rawValue: status) else { return nil }
        return NativeRepaymentCycle(
            id: id,
            accountId: accountId,
            cycleMonth: cycleMonth,
            statementStartDate: statementStartDate,
            statementEndDate: statementEndDate,
            dueDate: dueDate,
            statementAmount: statementAmount ?? 0,
            paidAmount: paidAmount ?? 0,
            remainingAmount: remainingAmount ?? 0,
            carriedOverAmount: carriedOverAmount ?? 0,
            originalStatementAmount: originalStatementAmount,
            minPaymentAmount: minPaymentAmount,
            refundAppliedAmount: refundAppliedAmount ?? 0,
            status: status,
            autoDebitAccountId: autoDebitAccountId,
            autoConfirmRepayment: autoConfirmRepayment ?? false,
            source: source ?? "system",
            evidenceRecordId: evidenceRecordId,
            confidence: confidence,
            note: note ?? "",
            confirmedAt: confirmedAt
        )
    }
}

private struct WalletPaymentRow: Decodable {
    let id: String
    let accountId: String
    let statementId: String?
    let debitAccountId: String?
    let amount: Double?
    let overpaymentAmount: Double?
    let paidAt: String
    let source: String?
    let evidenceRecordId: String?
    let status: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, source, status, note
        case accountId = "account_id"
        case statementId = "statement_id"
        case debitAccountId = "debit_account_id"
        case overpaymentAmount = "overpayment_amount"
        case paidAt = "paid_at"
        case evidenceRecordId = "evidence_record_id"
    }

    var native: NativeLiabilityPayment {
        NativeLiabilityPayment(
            id: id,
            accountId: accountId,
            statementId: statementId,
            debitAccountId: debitAccountId,
            amount: amount ?? 0,
            overpaymentAmount: overpaymentAmount ?? 0,
            paidAt: paidAt,
            source: source ?? "manual",
            evidenceRecordId: evidenceRecordId,
            status: status ?? "confirmed",
            note: note ?? ""
        )
    }
}
