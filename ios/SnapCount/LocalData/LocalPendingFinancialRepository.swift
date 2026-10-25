import Foundation
import GRDB

struct LocalPendingFinancialRecord: Equatable {
    let id: UUID
    let profileID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let transactionDate: String
    let transactionTime: String?
    let occurredAt: Date?
    let createdAt: Date
    var imagePath: String? = nil
    var imageHash: String? = nil
    var preferredKind: NativePendingEntryKind = .expense
}

/// LF-037.31/41/44. The original transaction, target and ledger change together.
final class LocalPendingFinancialRepository {
    private let database: LocalDatabase
    init(database: LocalDatabase) { self.database = database }

    func stage(_ record: LocalPendingFinancialRecord) throws {
        guard record.amountMinor >= 0, record.amountMinor <= 99_999_999,
              NativeLocalDate.monthKey(from: record.transactionDate) != nil else {
            throw LocalDataError.invalidRecord
        }
        try database.writer.write { db in
            if let existing = try Row.fetchOne(db, sql: "SELECT profile_id, image_hash FROM local_pending_transactions WHERE id = ?", arguments: [record.id.uuidString]) {
                guard (existing["profile_id"] as String) == record.profileID.uuidString,
                      (existing["image_hash"] as String?) == record.imageHash else { throw LocalDataError.invalidRecord }
                return
            }
            try db.execute(sql: """
                INSERT INTO local_pending_transactions
                (id, profile_id, amount_minor, currency, merchant_name, transaction_date,
                 transaction_time, occurred_at, created_at, image_path, image_hash, preferred_kind, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
                """, arguments: [record.id.uuidString, record.profileID.uuidString,
                    record.amountMinor, record.currency, record.merchantName,
                    record.transactionDate, record.transactionTime, record.occurredAt,
                    record.createdAt, record.imagePath, record.imageHash, record.preferredKind.rawValue])
        }
    }

    func pending(profileID: UUID) throws -> [LocalPendingFinancialRecord] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM local_pending_transactions WHERE profile_id = ? AND status = 'pending' ORDER BY created_at, id", arguments: [profileID.uuidString]).map(Self.record)
        }
    }

    func resolve(profileID: UUID, pendingID: UUID, draft: NativePendingResolutionDraft, at now: Date = Date()) throws -> NativePendingConfirmationAccepted {
        guard draft.validationMessage == nil,
              UUID(uuidString: draft.pendingId) == pendingID else { throw LocalDataError.invalidRecord }
        let amount = try LocalExpenseMapper.amountMinor(draft.amountText)
        guard amount > 0, amount <= 99_999_999 else { throw LocalDataError.invalidAmount }
        let accountID = draft.accountId.flatMap(UUID.init(uuidString:))
        if draft.accountId != nil && accountID == nil { throw LocalDataError.invalidRecord }
        return try database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM local_pending_transactions WHERE id = ? AND profile_id = ?", arguments: [pendingID.uuidString, profileID.uuidString]) else { throw LocalDataError.invalidRecord }
            let status: String = row["status"]
            if status != "pending" {
                guard let kind: String = row["target_kind"], kind == draft.kind.rawValue,
                      let id: String = row["target_id"], status != "deleted" else { throw LocalDataError.invalidRecord }
                return Self.accepted(pendingID: pendingID, kind: kind, id: id, retry: true)
            }
            let source = try Self.record(row)
            let targetID: UUID
            switch draft.kind {
            case .expense:
                guard let accountID else { throw LocalDataError.invalidRecord }
                targetID = pendingID
                var expense = LocalExpenseDraft(id: targetID, profileID: profileID,
                    accountID: accountID, amountMinor: amount, currency: source.currency,
                    merchantName: draft.merchantOrSourceName, platform: draft.platform,
                    category: draft.category, paymentMethod: draft.paymentMethod,
                    transactionDate: source.transactionDate, transactionTime: source.transactionTime,
                    note: nil, createdAt: source.occurredAt ?? source.createdAt)
                expense.imagePath = source.imagePath
                expense.imageHash = source.imageHash
                _ = try LocalExpenseRepository.insertExpense(expense, operationID: UUID(), database: db)
            case .income:
                targetID = UUID()
                var income = LocalIncomeDraft(id: targetID, profileID: profileID, accountID: accountID,
                    amountMinor: amount, currency: source.currency,
                    sourceName: draft.merchantOrSourceName, category: draft.incomeCategory,
                    incomeDate: source.transactionDate, occurredAt: source.occurredAt,
                    note: "由截图待补充转入收入", createdAt: now)
                income.imagePath = source.imagePath
                income.imageHash = source.imageHash
                _ = try LocalExpenseRepository.insertIncome(income, database: db)
                try db.execute(sql: "UPDATE local_income_records SET source_pending_transaction_id = ? WHERE id = ?", arguments: [pendingID.uuidString, targetID.uuidString])
            }
            try db.execute(sql: "UPDATE local_pending_transactions SET status = ?, target_kind = ?, target_id = ? WHERE id = ? AND profile_id = ? AND status = 'pending'", arguments: [draft.kind == .expense ? "done" : "converted", draft.kind.rawValue, targetID.uuidString, pendingID.uuidString, profileID.uuidString])
            guard db.changesCount == 1 else { throw LocalDataError.invalidRecord }
            return Self.accepted(pendingID: pendingID, kind: draft.kind.rawValue, id: targetID.uuidString, retry: false)
        }
    }

    func record(profileID: UUID, id: UUID) throws -> LocalPendingFinancialRecord? {
        try database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM local_pending_transactions WHERE id = ? AND profile_id = ? AND status = 'pending'", arguments: [id.uuidString, profileID.uuidString]).map(Self.record)
        }
    }

    func hasProcessedTransaction(profileID: UUID, id: UUID) throws -> Bool {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_pending_transactions WHERE id = ? AND profile_id = ? AND status IN ('pending','done','converted')", arguments: [id.uuidString, profileID.uuidString]) == 1
        }
    }

    func nativeDetail(profileID: UUID, id: UUID, imageStore: LocalImageStore) throws -> NativeRecordDetail? {
        guard let source = try record(profileID: profileID, id: id) else { return nil }
        let amount = Double(source.amountMinor) / 100
        return NativeRecordDetail(id: "expense/\(id.uuidString)", rawId: id.uuidString, kind: source.preferredKind.rawValue,
            title: source.merchantName, subtitle: source.transactionDate,
            value: String(format: "¥%.2f", amount), detailRows: [],
            imageURL: source.imagePath.map { imageStore.url(for: $0) }, imageLoadError: false,
            imagePath: source.imagePath, imageHash: source.imageHash, amount: amount,
            merchantName: source.merchantName, platform: nil, category: nil, paymentMethod: nil,
            recordDate: source.transactionDate, note: nil, companionMessage: nil, accountId: nil,
            systemImage: "creditcard", payload: nil,
            occurredAt: source.occurredAt.map { ISO8601DateFormatter().string(from: $0) },
            transactionTime: source.transactionTime, source: "local", status: "pending")
    }

    func delete(profileID: UUID, id: UUID, at now: Date = Date()) throws {
        try database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT status, image_path FROM local_pending_transactions WHERE id = ? AND profile_id = ?", arguments: [id.uuidString, profileID.uuidString]) else { throw LocalDataError.recordNotFound }
            let status: String = row["status"]
            if status == "deleted" { return }
            guard status == "pending" else { throw LocalDataError.invalidRecord }
            try db.execute(sql: "UPDATE local_pending_transactions SET status = 'deleted' WHERE id = ? AND profile_id = ?", arguments: [id.uuidString, profileID.uuidString])
            if let path: String = row["image_path"] {
                try db.execute(sql: "INSERT OR IGNORE INTO local_image_cleanups (id, profile_id, image_path, attempt_count, created_at, updated_at) VALUES (?, ?, ?, 0, ?, ?)", arguments: [UUID().uuidString, profileID.uuidString, path, now, now])
            }
        }
    }

    private static func accepted(pendingID: UUID, kind: String, id: String, retry: Bool) -> NativePendingConfirmationAccepted {
        NativePendingConfirmationAccepted(pendingId: pendingID.uuidString, recordType: kind,
            recordId: id, recordReference: "\(kind)/\(id)", idempotentRetry: retry)
    }

    private static func record(_ row: Row) throws -> LocalPendingFinancialRecord {
        guard let id = UUID(uuidString: row["id"]), let profileID = UUID(uuidString: row["profile_id"]) else { throw LocalDataError.invalidRecord }
        return LocalPendingFinancialRecord(id: id, profileID: profileID,
            amountMinor: row["amount_minor"], currency: row["currency"], merchantName: row["merchant_name"],
            transactionDate: row["transaction_date"], transactionTime: row["transaction_time"],
            occurredAt: row["occurred_at"], createdAt: row["created_at"], imagePath: row["image_path"], imageHash: row["image_hash"],
            preferredKind: NativePendingEntryKind(rawValue: row["preferred_kind"]) ?? .expense)
    }
}
