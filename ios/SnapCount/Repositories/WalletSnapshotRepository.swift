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
        guard snapshot.linkedAccountId == nil else {
            throw SupabaseRemoteError.requestFailed("这条快照已经关联账户")
        }

        let existing = try await sourceAccount(snapshotId: snapshot.id, accessToken: accessToken)
        if let existing {
            return try await link(snapshot, to: existing.native, userId: userId, accessToken: accessToken)
        }

        var body: [String: AnyCodable] = [
            "user_id": AnyCodable(userId),
            "name": AnyCodable(snapshot.accountName),
            "type": AnyCodable(snapshot.accountType.rawValue),
            "institution": AnyCodable(nullable(snapshot.institution)),
            "last4": AnyCodable(nullable(snapshot.last4)),
            "currency": AnyCodable("CNY"),
            "initial_balance": AnyCodable(snapshot.balance),
            "current_balance": AnyCodable(snapshot.balance),
            "snapshot_balance": AnyCodable(snapshot.balance),
            "snapshot_at": AnyCodable(snapshot.snapshotAt),
            "source_record_table": AnyCodable("data_records"),
            "source_record_id": AnyCodable(snapshot.id)
        ]
        if snapshot.kind == .liability {
            body["bill_day"] = AnyCodable(nullable(snapshot.billDay))
            body["payment_due_day"] = AnyCodable(nullable(snapshot.paymentDueDay))
        }

        let rows = try await remoteClient.post(
            [WalletAccountRow].self,
            path: "rest/v1/accounts",
            queryItems: [],
            body: body,
            accessToken: accessToken
        )
        guard let account = rows.first else {
            throw SupabaseRemoteError.requestFailed("账户创建成功，但没有返回账户编号")
        }

        try await linkRecord(snapshot, accountId: account.id, accessToken: accessToken)
        var warnings: [String] = []
        if snapshot.kind == .liability {
            do {
                try await upsertRepaymentCycle(
                    snapshot,
                    accountId: account.id,
                    userId: userId,
                    accessToken: accessToken
                )
            } catch {
                warnings.append("账户已创建，但还款账期暂未同步")
            }
        }
        return NativeWalletSnapshotLinkResult(accountId: account.id, warnings: warnings)
    }

    func link(
        _ snapshot: NativeWalletSnapshot,
        to account: NativeAccount,
        userId: String,
        accessToken: String
    ) async throws -> NativeWalletSnapshotLinkResult {
        var accountPatch: [String: AnyCodable] = [
            "snapshot_balance": AnyCodable(snapshot.balance),
            "snapshot_at": AnyCodable(snapshot.snapshotAt),
            "source_record_table": AnyCodable("data_records"),
            "source_record_id": AnyCodable(snapshot.id),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
        ]
        if snapshot.kind == .liability {
            if let billDay = snapshot.billDay { accountPatch["bill_day"] = AnyCodable(billDay) }
            if let paymentDueDay = snapshot.paymentDueDay { accountPatch["payment_due_day"] = AnyCodable(paymentDueDay) }
        }

        try await remoteClient.patch(
            path: "rest/v1/accounts",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(account.id)")],
            body: accountPatch,
            accessToken: accessToken
        )
        try await linkRecord(snapshot, accountId: account.id, accessToken: accessToken)

        var warnings: [String] = []
        if snapshot.kind == .liability {
            do {
                try await upsertRepaymentCycle(
                    snapshot,
                    accountId: account.id,
                    userId: userId,
                    accessToken: accessToken
                )
            } catch {
                warnings.append("快照已关联，但还款账期暂未同步")
            }
            do {
                try await reconcileLiability(snapshot, account: account, accessToken: accessToken)
            } catch {
                warnings.append("快照已关联，但当前欠款校准失败")
            }
        }
        return NativeWalletSnapshotLinkResult(accountId: account.id, warnings: warnings)
    }

    private func sourceAccount(snapshotId: String, accessToken: String) async throws -> WalletAccountRow? {
        let rows = try await remoteClient.get(
            [WalletAccountRow].self,
            path: "rest/v1/accounts",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "source_record_table", value: "eq.data_records"),
                URLQueryItem(name: "source_record_id", value: "eq.\(snapshotId)"),
                URLQueryItem(name: "order", value: "created_at.asc"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        return rows.first
    }

    private func linkRecord(
        _ snapshot: NativeWalletSnapshot,
        accountId: String,
        accessToken: String
    ) async throws {
        var payload = snapshot.payload
        payload["linked_account_id"] = AnyCodable(accountId)
        payload["account_snapshot_kind"] = AnyCodable(snapshot.kind.rawValue)
        payload["snapshot_balance"] = AnyCodable(snapshot.balance)
        try await remoteClient.patch(
            path: "rest/v1/data_records",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(snapshot.id)")],
            body: [
                "linked_account_id": AnyCodable(accountId),
                "account_snapshot_kind": AnyCodable(snapshot.kind.rawValue),
                "snapshot_balance": AnyCodable(snapshot.balance),
                "snapshot_at": AnyCodable(snapshot.snapshotAt),
                "payload_jsonb": AnyCodable(payload.mapValues(\.value))
            ],
            accessToken: accessToken
        )
    }

    private func upsertRepaymentCycle(
        _ snapshot: NativeWalletSnapshot,
        accountId: String,
        userId: String,
        accessToken: String
    ) async throws {
        guard let cycleMonth = snapshot.cycleMonth, snapshot.balance > 0 else { return }
        let dueDate = snapshot.dueDate ?? dueDate(monthKey: cycleMonth, day: snapshot.paymentDueDay)
        let paidAmount = snapshot.status == .paid ? snapshot.balance : 0
        let remainingAmount = snapshot.status == .paid ? 0 : snapshot.balance
        _ = try await remoteClient.upsert(
            [WalletRepaymentCycleIDRow].self,
            path: "rest/v1/account_repayment_cycles",
            queryItems: [URLQueryItem(name: "on_conflict", value: "account_id,cycle_month")],
            body: [
                "user_id": AnyCodable(userId),
                "account_id": AnyCodable(accountId),
                "cycle_month": AnyCodable(cycleMonth),
                "statement_start_date": AnyCodable(nullable(snapshot.statementStartDate)),
                "statement_end_date": AnyCodable(nullable(snapshot.statementEndDate)),
                "due_date": AnyCodable(nullable(dueDate)),
                "statement_amount": AnyCodable(snapshot.balance),
                "paid_amount": AnyCodable(paidAmount),
                "remaining_amount": AnyCodable(remainingAmount),
                "carried_over_amount": AnyCodable(0),
                "status": AnyCodable(snapshot.status.rawValue),
                "source": AnyCodable("screenshot"),
                "evidence_record_id": AnyCodable(snapshot.id),
                "confidence": AnyCodable(nullable(snapshot.confidence)),
                "statement_source_priority": AnyCodable(90),
                "original_statement_amount": AnyCodable(snapshot.balance),
                "note": AnyCodable(snapshot.status == .paid ? "来源快照显示已还款" : "来源快照生成待还周期")
            ],
            accessToken: accessToken
        )
    }

    private func reconcileLiability(
        _ snapshot: NativeWalletSnapshot,
        account: NativeAccount,
        accessToken: String
    ) async throws {
        let delta = ((snapshot.balance - account.currentBalance) * 100).rounded() / 100
        guard abs(delta) >= 0.01 else { return }
        _ = try await remoteClient.rpc(
            WalletAccountEntryIDRow.self,
            name: "create_account_entry_for_record",
            body: [
                "p_account_id": AnyCodable(account.id),
                "p_direction": AnyCodable(delta > 0 ? "in" : "out"),
                "p_amount": AnyCodable(abs(delta)),
                "p_entry_type": AnyCodable("adjustment"),
                "p_source_table": AnyCodable("data_records"),
                "p_source_id": AnyCodable(snapshot.id),
                "p_occurred_at": AnyCodable(snapshot.snapshotAt),
                "p_note": AnyCodable("由负债快照校准当前总欠款至 ¥\(String(format: "%.2f", snapshot.balance))")
            ],
            accessToken: accessToken
        )
        try await remoteClient.patch(
            path: "rest/v1/accounts",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(account.id)")],
            body: ["last_reconciled_at": AnyCodable(snapshot.snapshotAt)],
            accessToken: accessToken
        )
    }

    private func dueDate(monthKey: String, day: Int?) -> String? {
        guard let day else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: monthKey + "-01"),
              let range = Calendar(identifier: .gregorian).range(of: .day, in: .month, for: start) else {
            return nil
        }
        return "\(monthKey)-\(String(format: "%02d", min(max(day, 1), range.count)))"
    }

    private func nullable<T>(_ value: T?) -> Any {
        guard let value else { return NSNull() }
        return value
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

private struct WalletRepaymentCycleIDRow: Decodable { let id: String }
private struct WalletAccountEntryIDRow: Decodable { let id: String }
