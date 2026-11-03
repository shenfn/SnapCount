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
    var platform: String? = nil
    var category: String? = nil
    var paymentMethod: String? = nil
    var incomeCategory: String? = nil
    var companionMessage: String? = nil
    var aiFeedbackJSON: String? = nil
    var perceptualHash: String? = nil
    /// `possible_duplicate` 时待确认页按「可能已经记过」口径呈现，与 PWA 一致。
    var reviewReason: String? = nil
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
            if let existing = try Row.fetchOne(db, sql: "SELECT profile_id, image_hash, status FROM local_pending_transactions WHERE id = ?", arguments: [record.id.uuidString]) {
                guard (existing["profile_id"] as String) == record.profileID.uuidString,
                      (existing["image_hash"] as String?) == record.imageHash else { throw LocalDataError.invalidRecord }
                // 待补全被删除后重新上传同一张图，按新事实落库，否则这一行会永远停在 deleted。
                let status: String = existing["status"]
                guard status == "deleted" else { return }
                try db.execute(sql: "DELETE FROM local_pending_transactions WHERE id = ?", arguments: [record.id.uuidString])
            }
            try db.execute(sql: """
                INSERT INTO local_pending_transactions
                (id, profile_id, amount_minor, currency, merchant_name, transaction_date,
                 transaction_time, occurred_at, created_at, image_path, image_hash, preferred_kind,
                 platform, category, payment_method, income_category, companion_message, ai_feedback,
                 perceptual_hash, review_reason, status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')
                """, arguments: [record.id.uuidString, record.profileID.uuidString,
                    record.amountMinor, record.currency, record.merchantName,
                    record.transactionDate, record.transactionTime, record.occurredAt,
                    record.createdAt, record.imagePath, record.imageHash, record.preferredKind.rawValue,
                    record.platform, record.category, record.paymentMethod, record.incomeCategory,
                    record.companionMessage, record.aiFeedbackJSON, record.perceptualHash,
                    record.reviewReason])
        }
    }

    /// 高置信度自动归档：与云端 PWA 链路一致，记账四要素齐全时直接落正式账目，
    /// 不进入待补全。待补全表仍写一行非 pending 记录，保证同一张图重复上传时幂等。
    @discardableResult
    func archiveDirectly(_ record: LocalPendingFinancialRecord, at now: Date = Date()) throws -> UUID {
        guard record.amountMinor > 0, record.amountMinor <= 99_999_999,
              NativeLocalDate.monthKey(from: record.transactionDate) != nil else {
            throw LocalDataError.invalidRecord
        }
        return try database.writer.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT profile_id, status, target_id FROM local_pending_transactions WHERE id = ?", arguments: [record.id.uuidString]) {
                guard (row["profile_id"] as String) == record.profileID.uuidString else { throw LocalDataError.invalidRecord }
                let status: String = row["status"]
                switch status {
                case "done", "converted":
                    let existingTarget: String? = row["target_id"]
                    return existingTarget.flatMap(UUID.init(uuidString:)) ?? record.id
                case "deleted":
                    // 已删除的事实按新图重新入账，否则重传会得到"已归档"的假成功。
                    try db.execute(sql: "DELETE FROM local_pending_transactions WHERE id = ?", arguments: [record.id.uuidString])
                default:
                    throw LocalDataError.invalidRecord
                }
            }
            let targetID: UUID
            let targetKind: String
            switch record.preferredKind {
            case .expense:
                guard let platform = record.platform, !platform.isEmpty,
                      let category = record.category, !category.isEmpty,
                      let paymentMethod = record.paymentMethod, !paymentMethod.isEmpty else {
                    throw LocalDataError.invalidRecord
                }
                targetID = record.id
                targetKind = "expense"
                var expense = LocalExpenseDraft(id: targetID, profileID: record.profileID,
                    accountID: nil, amountMinor: record.amountMinor, currency: record.currency,
                    merchantName: record.merchantName, platform: platform, category: category,
                    paymentMethod: paymentMethod, transactionDate: record.transactionDate,
                    transactionTime: record.transactionTime, note: nil,
                    createdAt: record.occurredAt ?? record.createdAt)
                expense.imagePath = record.imagePath
                expense.imageHash = record.imageHash
                expense.perceptualHash = record.perceptualHash
                // 表达层跟着记账一起落库：漏传会让详情页的「AI 陪伴」和点评卡整块消失，
                // 只有停在待确认的账单看得到。
                expense.companionMessage = record.companionMessage
                expense.aiFeedbackJSON = record.aiFeedbackJSON
                _ = try LocalExpenseRepository.insertExpense(expense, operationID: UUID(), database: db)
            case .income:
                targetID = UUID()
                targetKind = "income"
                var income = LocalIncomeDraft(id: targetID, profileID: record.profileID, accountID: nil,
                    amountMinor: record.amountMinor, currency: record.currency,
                    sourceName: record.merchantName,
                    category: record.incomeCategory ?? "other",
                    incomeDate: record.transactionDate, occurredAt: record.occurredAt,
                    note: "截图识别自动归档", createdAt: now)
                income.imagePath = record.imagePath
                income.imageHash = record.imageHash
                income.perceptualHash = record.perceptualHash
                income.companionMessage = record.companionMessage
                income.aiFeedbackJSON = record.aiFeedbackJSON
                _ = try LocalExpenseRepository.insertIncome(income, database: db)
            }
            try db.execute(sql: """
                INSERT INTO local_pending_transactions
                (id, profile_id, amount_minor, currency, merchant_name, transaction_date,
                 transaction_time, occurred_at, created_at, image_path, image_hash, preferred_kind,
                 platform, category, payment_method, income_category, companion_message, ai_feedback,
                 perceptual_hash, review_reason, status, target_kind, target_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [record.id.uuidString, record.profileID.uuidString,
                    record.amountMinor, record.currency, record.merchantName,
                    record.transactionDate, record.transactionTime, record.occurredAt,
                    record.createdAt, record.imagePath, record.imageHash, record.preferredKind.rawValue,
                    record.platform, record.category, record.paymentMethod, record.incomeCategory,
                    record.companionMessage, record.aiFeedbackJSON, record.perceptualHash,
                    record.reviewReason,
                    targetKind == "expense" ? "done" : "converted", targetKind, targetID.uuidString])
            return targetID
        }
    }

    /// 查询一张图对应的处理状态，用于幂等判断：pending 仍需补全，done/converted 已归档，deleted 需重新识别。
    func processedStatus(profileID: UUID, id: UUID) throws -> String? {
        try database.writer.read { db in
            try String.fetchOne(db, sql: "SELECT status FROM local_pending_transactions WHERE id = ? AND profile_id = ?", arguments: [id.uuidString, profileID.uuidString])
        }
    }

    /// 幂等重传要复现首次的通知文案，这里不按 status 过滤。
    func recordIgnoringStatus(profileID: UUID, id: UUID) throws -> LocalPendingFinancialRecord? {
        try database.writer.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_pending_transactions WHERE id = ? AND profile_id = ?",
                arguments: [id.uuidString, profileID.uuidString]
            ).map(Self.record)
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
                targetID = pendingID
                var expense = LocalExpenseDraft(id: targetID, profileID: profileID,
                    accountID: accountID, amountMinor: amount, currency: source.currency,
                    merchantName: draft.merchantOrSourceName, platform: draft.platform,
                    category: draft.category, paymentMethod: draft.paymentMethod,
                    transactionDate: source.transactionDate, transactionTime: source.transactionTime,
                    note: nil, createdAt: source.occurredAt ?? source.createdAt)
                expense.imagePath = source.imagePath
                expense.imageHash = source.imageHash
                expense.perceptualHash = source.perceptualHash
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
                income.perceptualHash = source.perceptualHash
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

    func nativeDetail(profileID: UUID, id: UUID, imageStore: LocalImageStore) throws -> NativeRecordDetail? {
        guard let source = try record(profileID: profileID, id: id) else { return nil }
        let amount = Double(source.amountMinor) / 100
        let feedbackPayload = Self.feedbackPayload(from: source.aiFeedbackJSON)
        return NativeRecordDetail(id: "expense/\(id.uuidString)", rawId: id.uuidString, kind: source.preferredKind.rawValue,
            title: source.merchantName, subtitle: source.transactionDate,
            value: String(format: "¥%.2f", amount), detailRows: [],
            imageURL: source.imagePath.map { imageStore.url(for: $0) }, imageLoadError: false,
            imagePath: source.imagePath, imageHash: source.imageHash, amount: amount,
            merchantName: source.merchantName, platform: source.platform, category: source.category,
            paymentMethod: source.paymentMethod,
            recordDate: source.transactionDate, note: nil, companionMessage: source.companionMessage, accountId: nil,
            systemImage: "creditcard",
            payload: Self.pendingPayload(feedback: feedbackPayload, reviewReason: source.reviewReason),
            occurredAt: source.occurredAt.map { ISO8601DateFormatter().string(from: $0) },
            transactionTime: source.transactionTime, source: "local", status: "pending",
            aiFeedback: NativeAIFeedback(payload: feedbackPayload))
    }

    /// 待补全行里的反馈以 JSON 文本存一列，读回时还原成 payload 字典。
    /// 归档记账的读模型也要解这一列，所以不设 private。
    static func feedbackPayload(from json: String?) -> [String: AnyCodable]? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: AnyCodable].self, from: data)
    }

    /// 待确认详情页从 payload 里读 `review_reason` 判断是否要换「可能已经记过」口径。
    private static func pendingPayload(
        feedback: [String: AnyCodable]?,
        reviewReason: String?
    ) -> [String: AnyCodable]? {
        var payload: [String: AnyCodable] = [:]
        if let feedback {
            payload["ai_feedback"] = AnyCodable(feedback.mapValues(\.value))
        }
        if let reviewReason, !reviewReason.isEmpty {
            payload["review_reason"] = AnyCodable(reviewReason)
        }
        return payload.isEmpty ? nil : payload
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
            preferredKind: NativePendingEntryKind(rawValue: row["preferred_kind"]) ?? .expense,
            platform: row["platform"], category: row["category"],
            paymentMethod: row["payment_method"], incomeCategory: row["income_category"],
            companionMessage: row["companion_message"], aiFeedbackJSON: row["ai_feedback"],
            perceptualHash: row["perceptual_hash"], reviewReason: row["review_reason"])
    }
}
