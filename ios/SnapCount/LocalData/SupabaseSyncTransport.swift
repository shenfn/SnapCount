import Foundation

private struct SyncBatchResponse: Decodable {
    let acceptedOperationIDs: [UUID]
    let conflicts: [AnyCodable]
    let rejected: [AnyCodable]
    let remoteAccounts: [RemoteAccountDTO]
    let remoteExpenses: [RemoteExpenseDTO]
    let remoteAccountEntries: [RemoteEntryDTO]
    let nextPullCursor: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case acceptedOperationIDs = "accepted_operation_ids"
        case conflicts, rejected
        case remoteAccounts = "remote_accounts"
        case remoteExpenses = "remote_expenses"
        case remoteAccountEntries = "remote_account_entries"
        case nextPullCursor = "next_pull_cursor"
        case error
    }
}

private struct RemoteAccountDTO: Decodable {
    let aggregateID: UUID
    let version: Int64
    let changeKind: String
    let name: String?
    let type: String?
    let currency: String?
    let initialBalance: Double?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case aggregateID = "aggregate_id"
        case version, changeKind = "change_kind", name, type, currency
        case initialBalance = "initial_balance", deletedAt = "deleted_at"
    }
}

private struct RemoteExpenseDTO: Decodable {
    let aggregateID: UUID
    let version: Int64
    let changeKind: String
    let amount: Double?
    let merchantName: String?
    let platform: String?
    let category: String?
    let paymentMethod: String?
    let transactionDate: String?
    let transactionTime: String?
    let note: String?
    let accountID: UUID?
    let deletedAt: String?

    enum CodingKeys: String, CodingKey {
        case aggregateID = "aggregate_id"
        case version, changeKind = "change_kind", amount
        case merchantName = "merchant_name", platform, category, note
        case paymentMethod = "payment_method"
        case transactionDate = "transaction_date"
        case transactionTime = "transaction_time"
        case accountID = "account_id", deletedAt = "deleted_at"
    }
}

private struct RemoteEntryDTO: Decodable {
    let sourceID: UUID
    let accountID: UUID
    let direction: String
    let amount: Double
    let entryType: String
    let isVoided: Bool
    let voidedReason: String?

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id", accountID = "account_id"
        case direction, amount, entryType = "entry_type"
        case isVoided = "is_voided", voidedReason = "voided_reason"
    }
}

final class SupabaseSyncTransport: LocalSyncTransport {
    private let remoteClient: SupabaseRemoteClientProtocol
    private let accessToken: () async throws -> String
    private let workspaceID: (UUID) -> UUID
    private let clientGeneration: () -> Int

    init(
        remoteClient: SupabaseRemoteClientProtocol,
        accessToken: @escaping () async throws -> String,
        workspaceID: @escaping (UUID) -> UUID = { $0 },
        clientGeneration: @escaping () -> Int = { 1 }
    ) {
        self.remoteClient = remoteClient
        self.accessToken = accessToken
        self.workspaceID = workspaceID
        self.clientGeneration = clientGeneration
    }

    func synchronize(
        cloudUserID: String,
        profileID: UUID,
        pullCursor: String?,
        uploads: [LocalOutboxUpload]
    ) async throws -> LocalSyncTransportResult {
        let operations = try uploads.map(operationBody).map { $0.mapValues(\.value) }
        let body: [String: AnyCodable] = [
            "p_workspace_id": AnyCodable(workspaceID(profileID).uuidString),
            "p_client_generation": AnyCodable(clientGeneration()),
            "p_pull_cursor": AnyCodable(pullCursor ?? NSNull()),
            "p_operations": AnyCodable(operations)
        ]
        let response: SyncBatchResponse = try await remoteClient.rpc(
            SyncBatchResponse.self,
            name: "sync_expense_batch",
            body: body,
            accessToken: try await accessToken()
        )
        if let error = response.error {
            if error == "cursor_expired" {
                throw LocalSyncError.cursorExpired
            }
            throw SupabaseRemoteError.requestFailed(error)
        }
        let snapshot = LocalRemoteSnapshot(
            accounts: response.remoteAccounts.compactMap { account in
                if account.changeKind == "delete" {
                    return LocalRemoteAccount(id: account.aggregateID, name: "", kind: "other", currency: account.currency ?? "CNY", openingBalanceMinor: 0, version: account.version, deletedAt: parseDate(account.deletedAt) ?? Date())
                }
                guard let name = account.name, let kind = account.type else { return nil }
                return LocalRemoteAccount(
                    id: account.aggregateID,
                    name: name,
                    kind: kind,
                    currency: account.currency ?? "CNY",
                    openingBalanceMinor: Int64((account.initialBalance ?? 0) * 100),
                    version: account.version,
                    deletedAt: parseDate(account.deletedAt)
                )
            },
            expenses: response.remoteExpenses.compactMap { expense in
                if expense.changeKind == "delete" {
                    return LocalRemoteExpense(id: expense.aggregateID, accountID: expense.accountID ?? UUID(), amountMinor: 0, currency: "CNY", merchantName: "", platform: "", category: "", paymentMethod: "", transactionDate: "1970-01-01", transactionTime: nil, note: nil, version: expense.version, deletedAt: parseDate(expense.deletedAt) ?? Date())
                }
                guard let accountID = expense.accountID,
                      let amount = expense.amount,
                      let merchantName = expense.merchantName,
                      let category = expense.category,
                      let paymentMethod = expense.paymentMethod,
                      let transactionDate = expense.transactionDate else { return nil }
                return LocalRemoteExpense(
                    id: expense.aggregateID,
                    accountID: accountID,
                    amountMinor: Int64((amount * 100).rounded()),
                    currency: "CNY",
                    merchantName: merchantName,
                    platform: expense.platform ?? "",
                    category: category,
                    paymentMethod: paymentMethod,
                    transactionDate: transactionDate,
                    transactionTime: expense.transactionTime,
                    note: expense.note,
                    version: expense.version,
                    deletedAt: parseDate(expense.deletedAt)
                )
            },
            accountEntries: response.remoteAccountEntries.map { entry in
                LocalRemoteAccountEntry(
                    id: entry.sourceID,
                    accountID: entry.accountID,
                    direction: entry.direction,
                    amountMinor: Int64((entry.amount * 100).rounded()),
                    entryKind: entry.entryType,
                    sourceID: entry.sourceID,
                    voided: entry.isVoided,
                    voidedReason: entry.voidedReason
                )
            }
        )
        let conflictDictionaries = response.conflicts.compactMap { $0.value as? [String: Any] }
        let conflictedAggregateIDs = Set(conflictDictionaries.compactMap { dictionary -> UUID? in
            guard let raw = dictionary["aggregate_id"] as? String else { return nil }
            return UUID(uuidString: raw)
        })
        let conflictedExpenseIDs = Set(conflictDictionaries.compactMap { dictionary -> UUID? in
            guard dictionary["aggregate_kind"] as? String == "expense",
                  let raw = dictionary["aggregate_id"] as? String else { return nil }
            return UUID(uuidString: raw)
        })
        let rejectedOperations = try response.rejected.map { value -> LocalSyncRejectedOperation in
            guard let dictionary = value.value as? [String: Any],
                  let operationID = dictionary["operation_id"] as? String,
                  let id = UUID(uuidString: operationID),
                  let reason = dictionary["reason"] as? String else {
                throw LocalSyncError.invalidResponse
            }
            return LocalSyncRejectedOperation(operationID: id, reason: reason)
        }
        return LocalSyncTransportResult(
            nextPullCursor: response.nextPullCursor,
            remoteSnapshot: snapshot,
            acceptedOperationIDs: response.acceptedOperationIDs,
            rejectedOperations: rejectedOperations,
            conflictedAggregateIDs: conflictedAggregateIDs,
            conflictedExpenseIDs: conflictedExpenseIDs
        )
    }

    private func operationBody(_ upload: LocalOutboxUpload) throws -> [String: AnyCodable] {
        let data = Data(upload.payloadJSON.utf8)
        let payload = try JSONDecoder().decode([String: AnyCodable].self, from: data)
        return [
            "operation_id": AnyCodable(upload.operationID.uuidString),
            "idempotency_key": AnyCodable(upload.idempotencyKey),
            "aggregate_kind": AnyCodable(upload.aggregateKind),
            "aggregate_id": AnyCodable(upload.aggregateID.uuidString),
            "operation_kind": AnyCodable(upload.operationKind),
            "aggregate_version": AnyCodable(Int(upload.aggregateVersion)),
            "base_version": AnyCodable(max(0, Int(upload.aggregateVersion - 1))),
            "payload": AnyCodable(normalizePayload(payload))
        ]
    }

    private func normalizePayload(_ payload: [String: AnyCodable]) -> [String: Any] {
        var result = payload.mapValues(\.value)
        let aliases = [
            "accountID": "account_id", "amountMinor": "amount_minor",
            "merchantName": "merchant_name", "paymentMethod": "payment_method",
            "transactionDate": "transaction_date", "transactionTime": "transaction_time",
            "openingBalanceMinor": "opening_balance_minor", "localVersion": "local_version"
        ]
        for (from, to) in aliases where result[to] == nil {
            if let value = result.removeValue(forKey: from) { result[to] = value }
        }
        if let amountMinor = result["amount_minor"] as? Int { result["amount"] = Double(amountMinor) / 100 }
        return result
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
