import Foundation
import GRDB

enum LocalWalletSnapshotKind: String, Codable, Equatable {
    case asset
    case liability
}

struct LocalWalletSnapshot: Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let title: String
    let summary: String
    let payloadJSON: String
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let balanceMinor: Int64
    let currency: String
    let kind: LocalWalletSnapshotKind
    let linkedAccountID: UUID?
    let linkedAction: String?
    let imagePath: String?
    let imageHash: String?
    let localVersion: Int64
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    var balance: Double { Double(balanceMinor) / 100 }
}

struct LocalWalletSnapshotCommand {
    let id: UUID
    let title: String
    let summary: String
    let payload: [String: AnyCodable]
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let balanceMinor: Int64
    let currency: String
    let kind: LocalWalletSnapshotKind
    let imageData: Data?
    let createdAt: Date
}

struct LocalWalletSnapshotDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let title: String
    let summary: String
    let payloadJSON: String
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let balanceMinor: Int64
    let currency: String
    let kind: LocalWalletSnapshotKind
    let imagePath: String?
    let imageHash: String?
    let createdAt: Date
}

struct LocalWalletSnapshotUpdateDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let expectedVersion: Int64
    let title: String
    let summary: String
    let payloadJSON: String
    let balanceMinor: Int64
    let updatedAt: Date
}

enum LocalWalletSnapshotActionKind: String, Equatable {
    case created
    case linked
    case replayed
}

struct LocalWalletSnapshotActionResult: Equatable {
    let kind: LocalWalletSnapshotActionKind
    let account: LocalAccount
    let reviewRequired: Bool

    init(kind: LocalWalletSnapshotActionKind, account: LocalAccount, reviewRequired: Bool = false) {
        self.kind = kind
        self.account = account
        self.reviewRequired = reviewRequired
    }
}

enum LocalWalletSnapshotActionError: Error, Equatable, LocalizedError {
    case conflict
    case incompatibleAccount
    case futureEvidence

    var errorDescription: String? {
        switch self {
        case .conflict: return "这条快照已经执行过另一种关联操作。"
        case .incompatibleAccount: return "快照类型与账户类型不匹配，无法关联。"
        case .futureEvidence: return "未来日期的快照不能作为当前账户证据。"
        }
    }
}

protocol LocalWalletSnapshotRepositoryProtocol {
    func create(_ draft: LocalWalletSnapshotDraft) throws -> LocalWalletSnapshot
    func unlinked(profileID: UUID) throws -> [LocalWalletSnapshot]
    func history(profileID: UUID) throws -> [LocalWalletSnapshot]
    func update(_ draft: LocalWalletSnapshotUpdateDraft) throws -> LocalWalletSnapshot
    func delete(id: UUID, profileID: UUID, expectedVersion: Int64, deletedAt: Date) throws -> LocalWalletSnapshot
    func createAccountFromSnapshot(
        _ snapshot: LocalWalletSnapshot,
        account: LocalAccountDraft
    ) throws -> LocalWalletSnapshotActionResult
    func link(_ snapshot: LocalWalletSnapshot, to accountID: UUID) throws -> LocalWalletSnapshotActionResult
}

final class LocalWalletSnapshotRepository: LocalWalletSnapshotRepositoryProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func create(_ draft: LocalWalletSnapshotDraft) throws -> LocalWalletSnapshot {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              draft.balanceMinor >= 0,
              draft.currency == "CNY",
              NativeLocalDate.monthKey(from: draft.recordDate) != nil,
              (draft.recordTime == nil || draft.occurredAt != nil),
              draft.occurredAt.map({ Self.matchesOccurredAt($0, recordDate: draft.recordDate, recordTime: draft.recordTime) }) ?? true,
              (draft.imagePath == nil) == (draft.imageHash == nil) else {
            throw LocalDataError.invalidRecord
        }

        return try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_wallet_snapshots (
                        id, profile_id, title, summary, payload_json, record_date, record_time,
                        occurred_at, snapshot_balance_minor, currency, account_snapshot_kind,
                        linked_account_id, image_path, image_hash, local_version, created_at,
                        updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString, draft.profileID.uuidString, title, draft.summary,
                    draft.payloadJSON, draft.recordDate, draft.recordTime, draft.occurredAt,
                    draft.balanceMinor, draft.currency, draft.kind.rawValue,
                    draft.imagePath, draft.imageHash, draft.createdAt, draft.createdAt
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ? AND profile_id = ?",
                arguments: [draft.id.uuidString, draft.profileID.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            return try Self.snapshot(from: row)
        }
    }

    func unlinked(profileID: UUID) throws -> [LocalWalletSnapshot] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_wallet_snapshots
                    WHERE profile_id = ? AND linked_account_id IS NULL AND deleted_at IS NULL
                    ORDER BY record_date DESC, record_time DESC, created_at DESC, id
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.snapshot(from:))
        }
    }

    func history(profileID: UUID) throws -> [LocalWalletSnapshot] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_wallet_snapshots
                    WHERE profile_id = ?
                    ORDER BY record_date DESC, record_time DESC, created_at DESC, id
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.snapshot(from:))
        }
    }

    func update(_ draft: LocalWalletSnapshotUpdateDraft) throws -> LocalWalletSnapshot {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, draft.balanceMinor >= 0,
              (try? JSONSerialization.jsonObject(with: Data(draft.payloadJSON.utf8))) is [String: Any] else {
            throw LocalDataError.invalidRecord
        }
        return try database.writer.write { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ?",
                arguments: [draft.id.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            let storedProfileID: String = current["profile_id"]
            guard storedProfileID == draft.profileID.uuidString else { throw LocalDataError.invalidIdentifier }
            let deletedAt: Date? = current["deleted_at"]
            guard deletedAt == nil else { throw LocalDataError.recordNotFound }
            let actualVersion: Int64 = current["local_version"]
            guard actualVersion == draft.expectedVersion else {
                throw LocalDataError.versionConflict(expected: draft.expectedVersion, actual: actualVersion)
            }
            try db.execute(sql: """
                UPDATE local_wallet_snapshots
                SET title = ?, summary = ?, payload_json = ?, snapshot_balance_minor = ?,
                    local_version = local_version + 1, updated_at = ?
                WHERE id = ? AND profile_id = ? AND local_version = ? AND deleted_at IS NULL
                """, arguments: [
                    title, draft.summary, draft.payloadJSON, draft.balanceMinor, draft.updatedAt,
                    draft.id.uuidString, draft.profileID.uuidString, draft.expectedVersion
                ])
            guard db.changesCount == 1,
                  let row = try Row.fetchOne(db, sql: "SELECT * FROM local_wallet_snapshots WHERE id = ?", arguments: [draft.id.uuidString]) else {
                throw LocalDataError.versionConflict(expected: draft.expectedVersion, actual: actualVersion)
            }
            return try Self.snapshot(from: row)
        }
    }

    func delete(id: UUID, profileID: UUID, expectedVersion: Int64, deletedAt: Date) throws -> LocalWalletSnapshot {
        try database.writer.write { db in
            guard let current = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ?",
                arguments: [id.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            let storedProfileID: String = current["profile_id"]
            guard storedProfileID == profileID.uuidString else { throw LocalDataError.invalidIdentifier }
            let alreadyDeleted: Date? = current["deleted_at"]
            guard alreadyDeleted == nil else { throw LocalDataError.recordNotFound }
            let actualVersion: Int64 = current["local_version"]
            guard actualVersion == expectedVersion else {
                throw LocalDataError.versionConflict(expected: expectedVersion, actual: actualVersion)
            }
            try db.execute(sql: """
                UPDATE local_wallet_snapshots
                SET deleted_at = ?, updated_at = ?, local_version = local_version + 1
                WHERE id = ? AND profile_id = ? AND local_version = ? AND deleted_at IS NULL
                """, arguments: [deletedAt, deletedAt, id.uuidString, profileID.uuidString, expectedVersion])
            guard db.changesCount == 1,
                  let row = try Row.fetchOne(db, sql: "SELECT * FROM local_wallet_snapshots WHERE id = ?", arguments: [id.uuidString]) else {
                throw LocalDataError.versionConflict(expected: expectedVersion, actual: actualVersion)
            }
            return try Self.snapshot(from: row)
        }
    }

    func createAccountFromSnapshot(
        _ snapshot: LocalWalletSnapshot,
        account draft: LocalAccountDraft
    ) throws -> LocalWalletSnapshotActionResult {
        guard draft.profileID == snapshot.profileID else { throw LocalDataError.invalidIdentifier }
        let result = try database.writer.write { db -> (LocalWalletSnapshotActionKind, UUID, Bool) in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ? AND profile_id = ?",
                arguments: [snapshot.id.uuidString, snapshot.profileID.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            let storedSnapshot = try Self.snapshot(from: row)
            let deletedAt: Date? = row["deleted_at"]
            guard deletedAt == nil else { throw LocalDataError.recordNotFound }
            guard !Self.isFutureEvidence(storedSnapshot, now: Date()) else {
                throw LocalWalletSnapshotActionError.futureEvidence
            }
            let linkedID: String? = row["linked_account_id"]
            let linkedAction: String? = row["linked_action"]
            if let linkedID {
                guard linkedAction == "create",
                      let accountID = UUID(uuidString: linkedID),
                      try Self.accountExists(accountID, profileID: snapshot.profileID, database: db) else {
                    throw LocalWalletSnapshotActionError.conflict
                }
                return (.replayed, accountID, try Self.snapshotNeedsConfirmation(storedSnapshot, accountID: accountID, database: db))
            }
            guard linkedAction == nil else { throw LocalWalletSnapshotActionError.conflict }
            guard draft.openingBalanceMinor == storedSnapshot.balanceMinor,
                  Self.isCompatible(snapshotKind: storedSnapshot.kind, accountKind: draft.kind) else {
                throw LocalWalletSnapshotActionError.incompatibleAccount
            }
            let account = try LocalExpenseRepository.insertAccount(draft, database: db)
            try Self.insertInitializationEntry(
                snapshot: storedSnapshot,
                accountID: account.id,
                profileID: storedSnapshot.profileID,
                database: db
            )
            let reviewRequired = try Self.applyLiabilitySnapshotCycle(storedSnapshot, accountID: account.id, database: db)
            try Self.markLinked(snapshotID: storedSnapshot.id, profileID: storedSnapshot.profileID, accountID: account.id, action: "create", database: db)
            return (.created, account.id, reviewRequired)
        }
        guard let account = try LocalExpenseRepository(database: database).accounts(profileID: snapshot.profileID)
            .first(where: { $0.id == result.1 }) else { throw LocalDataError.recordNotFound }
        return LocalWalletSnapshotActionResult(kind: result.0, account: account, reviewRequired: result.2)
    }

    func link(_ snapshot: LocalWalletSnapshot, to accountID: UUID) throws -> LocalWalletSnapshotActionResult {
        let result = try database.writer.write { db -> (LocalWalletSnapshotActionKind, UUID, Bool) in
            guard let snapshotRow = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ? AND profile_id = ?",
                arguments: [snapshot.id.uuidString, snapshot.profileID.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            let storedSnapshot = try Self.snapshot(from: snapshotRow)
            let deletedAt: Date? = snapshotRow["deleted_at"]
            guard deletedAt == nil else { throw LocalDataError.recordNotFound }
            guard !Self.isFutureEvidence(storedSnapshot, now: Date()) else {
                throw LocalWalletSnapshotActionError.futureEvidence
            }
            let linkedID: String? = snapshotRow["linked_account_id"]
            let linkedAction: String? = snapshotRow["linked_action"]
            if let linkedID {
                guard linkedAction == "link", linkedID == accountID.uuidString,
                      try Self.accountExists(accountID, profileID: snapshot.profileID, database: db) else {
                    throw LocalWalletSnapshotActionError.conflict
                }
                return (.replayed, accountID, try Self.snapshotNeedsConfirmation(storedSnapshot, accountID: accountID, database: db))
            }
            guard linkedAction == nil,
                  let accountRow = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM local_accounts WHERE id = ? AND profile_id = ? AND is_archived = 0",
                    arguments: [accountID.uuidString, snapshot.profileID.uuidString]
                  ) else { throw LocalDataError.invalidIdentifier }
            let accountKind: String = accountRow["kind"]
            guard Self.isCompatible(snapshotKind: storedSnapshot.kind, accountKind: accountKind) else {
                throw LocalWalletSnapshotActionError.incompatibleAccount
            }
            let balance = try Self.accountBalanceMinor(accountID: accountID, database: db)
            let openingBalance: Int64 = accountRow["opening_balance_minor"]
            let activeEntryCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM local_account_entries
                WHERE profile_id = ? AND account_id = ? AND voided_at IS NULL AND is_voided = 0
                  AND entry_kind != 'snapshot_initialization'
                """, arguments: [snapshot.profileID.uuidString, accountID.uuidString]) ?? 0
            let snapshotBalance = storedSnapshot.balanceMinor
            if openingBalance == 0, balance == 0, activeEntryCount == 0, snapshotBalance > 0 {
                try db.execute(sql: "UPDATE local_accounts SET opening_balance_minor = ?, local_version = local_version + 1 WHERE id = ? AND profile_id = ?",
                               arguments: [snapshotBalance, accountID.uuidString, snapshot.profileID.uuidString])
                try Self.insertInitializationEntry(snapshot: storedSnapshot, accountID: accountID, profileID: snapshot.profileID, database: db)
            }
            let reviewRequired = try Self.applyLiabilitySnapshotCycle(storedSnapshot, accountID: accountID, database: db)
            try Self.markLinked(snapshotID: snapshot.id, profileID: snapshot.profileID, accountID: accountID, action: "link", database: db)
            return (.linked, accountID, reviewRequired)
        }
        guard let account = try LocalExpenseRepository(database: database).accounts(profileID: snapshot.profileID)
            .first(where: { $0.id == result.1 }) else { throw LocalDataError.recordNotFound }
        return LocalWalletSnapshotActionResult(kind: result.0, account: account, reviewRequired: result.2)
    }

    private static func applyLiabilitySnapshotCycle(
        _ snapshot: LocalWalletSnapshot,
        accountID: UUID,
        database: Database
    ) throws -> Bool {
        guard snapshot.kind == .liability else { return false }
        let payload = try LocalRecordCodec.decode(snapshot.payloadJSON)
        guard payload.string("status") != "paid",
              let cycleMonth = screenshotCycleMonth(payload) else { return true }
        let statementStart = validDateKey(payload.string("statement_start_date"))
        let statementEnd = validDateKey(payload.string("statement_end_date"))
        if let statementStart, let statementEnd, statementStart > statementEnd { return true }
        guard let account = try Row.fetchOne(
            database,
            sql: "SELECT payment_due_day, auto_debit_account_id, auto_confirm_repayment FROM local_accounts WHERE id = ? AND profile_id = ?",
            arguments: [accountID.uuidString, snapshot.profileID.uuidString]
        ) else { throw LocalDataError.recordNotFound }

        let dueDate = validDateKey(payload.string("due_date"))
            ?? derivedDueDate(cycleMonth: cycleMonth, paymentDueDay: account["payment_due_day"] as Int?)
        let today = NativeLocalDate.dateKey(Date())
        let cycleStatus = dueDate.map { $0 == today ? "due_today" : ($0 < today ? "overdue_unconfirmed" : "pending") }
            ?? "pending"
        let confidence = payload.double("confidence").flatMap { $0.isFinite && $0 >= 0 ? min($0, 1) : nil }
        let now = Date()

        if let existing = try Row.fetchOne(database, sql: """
            SELECT cycle.*,
                (SELECT COUNT(*) FROM local_liability_payments payment
                 WHERE payment.statement_id = cycle.id AND payment.status != 'voided') AS active_payment_count
            FROM local_repayment_cycles cycle
            WHERE cycle.account_id = ? AND cycle.cycle_month = ?
            """, arguments: [accountID.uuidString, cycleMonth]) {
            let source: String = existing["source"]
            let evidenceID: String? = existing["evidence_wallet_snapshot_id"]
            let paidAmount: Int64 = existing["paid_amount_minor"]
            let status: String = existing["status"]
            let activePayments: Int = existing["active_payment_count"]
            let eligibleStatuses = ["draft_estimated", "pending", "due_today", "overdue_unconfirmed"]
            if source == "screenshot", evidenceID == snapshot.id.uuidString,
               paidAmount == 0, activePayments == 0, eligibleStatuses.contains(status) {
                return false
            }
            guard source == "system", paidAmount == 0, activePayments == 0,
                  eligibleStatuses.contains(status) else { return true }
            try database.execute(sql: """
                UPDATE local_repayment_cycles SET statement_start_date = COALESCE(?, statement_start_date),
                    statement_end_date = COALESCE(?, statement_end_date), due_date = COALESCE(?, due_date),
                    statement_amount_minor = ?, original_statement_amount_minor = ?, remaining_amount_minor = ?,
                    source = 'screenshot', evidence_record_id = NULL, evidence_wallet_snapshot_id = ?,
                    confidence = ?, status = ?,
                    note = '依据负债钱包截图补全', local_version = local_version + 1, updated_at = ?
                WHERE id = ? AND profile_id = ?
                """, arguments: [statementStart, statementEnd, dueDate, snapshot.balanceMinor,
                                  snapshot.balanceMinor, snapshot.balanceMinor, snapshot.id.uuidString,
                                  confidence, cycleStatus, now, existing["id"] as String, snapshot.profileID.uuidString])
            return false
        }

        let accountDueDebitID: String? = account["auto_debit_account_id"]
        let accountAutoConfirm: Bool = account["auto_confirm_repayment"]
        try database.execute(sql: """
            INSERT INTO local_repayment_cycles (
                id, profile_id, account_id, cycle_month, statement_start_date, statement_end_date, due_date,
                statement_amount_minor, paid_amount_minor, remaining_amount_minor, original_statement_amount_minor,
                status, auto_debit_account_id, auto_confirm_repayment, source, evidence_record_id,
                evidence_wallet_snapshot_id, confidence,
                note, local_version, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, 'screenshot', NULL, ?, ?, '依据负债钱包截图补全', 1, ?, ?)
            """, arguments: [UUID().uuidString, snapshot.profileID.uuidString, accountID.uuidString, cycleMonth,
                              statementStart, statementEnd, dueDate, snapshot.balanceMinor, snapshot.balanceMinor,
                              snapshot.balanceMinor, cycleStatus, accountDueDebitID, accountAutoConfirm,
                              snapshot.id.uuidString, confidence, now, now])
        return false
    }

    private static func snapshotNeedsConfirmation(
        _ snapshot: LocalWalletSnapshot,
        accountID: UUID,
        database: Database
    ) throws -> Bool {
        guard snapshot.kind == .liability else { return false }
        let payload = try LocalRecordCodec.decode(snapshot.payloadJSON)
        guard let cycleMonth = screenshotCycleMonth(payload),
              let cycle = try Row.fetchOne(database, sql: """
                SELECT evidence_wallet_snapshot_id FROM local_repayment_cycles
                WHERE account_id = ? AND cycle_month = ?
                """, arguments: [accountID.uuidString, cycleMonth]) else { return true }
        let evidenceID: String? = cycle["evidence_wallet_snapshot_id"]
        return evidenceID != snapshot.id.uuidString
    }

    private static func screenshotCycleMonth(_ payload: [String: AnyCodable]) -> String? {
        for key in ["cycle_month", "statement_month", "bill_month"] {
            if let value = payload.string(key), validMonthKey(value) { return value }
        }
        guard let dueDate = validDateKey(payload.string("due_date")) else { return nil }
        return String(dueDate.prefix(7))
    }

    private static func validMonthKey(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil
            && validDateKey(value + "-01") != nil
    }

    private static func validDateKey(_ value: String?) -> String? {
        guard let value,
              value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return value
    }

    private static func derivedDueDate(cycleMonth: String, paymentDueDay: Int?) -> String? {
        guard let paymentDueDay, (1...31).contains(paymentDueDay),
              let firstDay = validDateKey(cycleMonth + "-01").flatMap({ key in
                  var calendar = Calendar(identifier: .gregorian)
                  calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
                  let formatter = DateFormatter()
                  formatter.locale = Locale(identifier: "en_US_POSIX")
                  formatter.calendar = calendar
                  formatter.timeZone = calendar.timeZone
                  formatter.dateFormat = "yyyy-MM-dd"
                  return formatter.date(from: key)
              }) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        guard let dayRange = calendar.range(of: .day, in: .month, for: firstDay),
              let monthDay = calendar.date(byAdding: .day, value: min(paymentDueDay, dayRange.count) - 1, to: firstDay) else {
            return nil
        }
        return NativeLocalDate.dateKey(monthDay)
    }

    private static func matchesOccurredAt(_ occurredAt: String, recordDate: String, recordTime: String?) -> Bool {
        let parts = recordTime?.split(separator: ":").compactMap { Int($0) } ?? []
        guard let recordTime,
              recordTime.range(of: #"^\d{2}:\d{2}(?::\d{2})?$"#, options: .regularExpression) != nil,
              parts.count == 2 || parts.count == 3,
              (0...23).contains(parts[0]), (0...59).contains(parts[1]),
              parts.count == 2 || (0...59).contains(parts[2]),
              NativeLocalDate.financeDateKey(occurredAt: occurredAt, legacyDate: nil) == recordDate,
              let occurredTime = NativeLocalDate.financeTimeKey(occurredAt: occurredAt) else {
            return false
        }
        return occurredTime == String(recordTime.prefix(5))
    }

    private static func isFutureEvidence(_ snapshot: LocalWalletSnapshot, now: Date) -> Bool {
        guard snapshot.recordDate <= NativeLocalDate.dateKey(now) else { return true }
        guard let occurredAt = snapshot.occurredAt else { return false }
        let formatter = ISO8601DateFormatter()
        if let occurredAtDate = formatter.date(from: occurredAt) { return occurredAtDate > now }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: occurredAt).map { $0 > now } ?? false
    }

    private static func snapshot(from row: Row) throws -> LocalWalletSnapshot {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let kind = LocalWalletSnapshotKind(rawValue: row["account_snapshot_kind"]),
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        let linkedAccountText: String? = row["linked_account_id"]
        return LocalWalletSnapshot(
            id: id,
            profileID: profileID,
            title: row["title"],
            summary: row["summary"],
            payloadJSON: row["payload_json"],
            recordDate: row["record_date"],
            recordTime: row["record_time"],
            occurredAt: row["occurred_at"],
            balanceMinor: row["snapshot_balance_minor"],
            currency: row["currency"],
            kind: kind,
            linkedAccountID: linkedAccountText.flatMap(UUID.init(uuidString:)),
            linkedAction: row["linked_action"],
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: row["deleted_at"]
        )
    }

    private static func isCompatible(snapshotKind: LocalWalletSnapshotKind, accountKind: String) -> Bool {
        switch snapshotKind {
        case .asset: return !["credit_card", "credit_line"].contains(accountKind)
        case .liability: return ["credit_card", "credit_line"].contains(accountKind)
        }
    }

    private static func accountExists(_ id: UUID, profileID: UUID, database: Database) throws -> Bool {
        try Int.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM local_accounts WHERE id = ? AND profile_id = ?)",
                         arguments: [id.uuidString, profileID.uuidString]) == 1
    }

    private static func accountBalanceMinor(accountID: UUID, database: Database) throws -> Int64 {
        guard let row = try Row.fetchOne(database, sql: """
            SELECT account.opening_balance_minor AS opening_balance_minor,
                   COALESCE(SUM(CASE entry.direction WHEN 'in' THEN entry.amount_minor WHEN 'out' THEN -entry.amount_minor END), 0) AS delta
            FROM local_accounts account LEFT JOIN local_account_entries entry
              ON entry.account_id = account.id AND entry.voided_at IS NULL AND entry.is_voided = 0
             AND entry.entry_kind != 'snapshot_initialization'
            WHERE account.id = ? AND account.is_archived = 0 GROUP BY account.id
            """, arguments: [accountID.uuidString]) else { throw LocalDataError.invalidIdentifier }
        let opening: Int64 = row["opening_balance_minor"]
        let delta: Int64 = row["delta"]
        return opening + delta
    }

    private static func insertInitializationEntry(
        snapshot: LocalWalletSnapshot,
        accountID: UUID,
        profileID: UUID,
        database: Database
    ) throws {
        guard snapshot.balanceMinor > 0 else { return }
        let occurredAt = snapshot.occurredAt
            .flatMap { ISO8601DateFormatter().date(from: $0) }
            ?? snapshot.createdAt
        try database.execute(sql: """
            INSERT INTO local_account_entries (
                id, profile_id, account_id, direction, amount_minor, entry_kind,
                source_kind, source_id, occurred_at, voided_at
            ) VALUES (?, ?, ?, 'in', ?, 'snapshot_initialization', 'wallet_snapshot', ?, ?, NULL)
            """, arguments: [UUID().uuidString, profileID.uuidString, accountID.uuidString,
                              snapshot.balanceMinor, snapshot.id.uuidString, occurredAt])
    }

    private static func markLinked(
        snapshotID: UUID,
        profileID: UUID,
        accountID: UUID,
        action: String,
        database: Database
    ) throws {
        try database.execute(sql: """
            UPDATE local_wallet_snapshots
            SET linked_account_id = ?, linked_action = ?, local_version = local_version + 1, updated_at = ?
            WHERE id = ? AND profile_id = ? AND linked_account_id IS NULL AND deleted_at IS NULL
            """, arguments: [accountID.uuidString, action, Date(), snapshotID.uuidString, profileID.uuidString])
        guard database.changesCount == 1 else { throw LocalWalletSnapshotActionError.conflict }
    }
}

protocol LocalWalletSnapshotUseCaseProtocol {
    func create(_ command: LocalWalletSnapshotCommand) async throws -> LocalWalletSnapshot
    func unlinked() async throws -> [LocalWalletSnapshot]
    func history() async throws -> [LocalWalletSnapshot]
    func update(_ snapshot: LocalWalletSnapshot, title: String, summary: String, balanceMinor: Int64) async throws -> LocalWalletSnapshot
    func delete(_ snapshot: LocalWalletSnapshot) async throws -> LocalWalletSnapshot
    func createAccount(from snapshot: LocalWalletSnapshot) async throws -> LocalWalletSnapshotActionResult
    func link(_ snapshot: LocalWalletSnapshot, to accountID: UUID) async throws -> LocalWalletSnapshotActionResult
}

final class LocalWalletSnapshotUseCase: LocalWalletSnapshotUseCaseProtocol {
    private let profileStore: LocalProfileStoreProtocol
    private let repository: LocalWalletSnapshotRepositoryProtocol
    private let imageStore: LocalImageStore?

    init(
        profileStore: LocalProfileStoreProtocol,
        repository: LocalWalletSnapshotRepositoryProtocol,
        imageStore: LocalImageStore? = nil
    ) {
        self.profileStore = profileStore
        self.repository = repository
        self.imageStore = imageStore
    }

    func create(_ command: LocalWalletSnapshotCommand) async throws -> LocalWalletSnapshot {
        let profile = try profileStore.activeProfile()
        let payloadJSON = try LocalRecordCodec.encode(command.payload)
        let imageReference: LocalImageReference?
        if let imageData = command.imageData {
            guard let imageStore else { throw LocalDataError.invalidRecord }
            imageReference = try imageStore.save(
                data: imageData,
                owner: "wallet-snapshot-\(command.id.uuidString)-\(UUID().uuidString)"
            )
        } else {
            imageReference = nil
        }
        do {
            return try repository.create(LocalWalletSnapshotDraft(
                id: command.id,
                profileID: profile.id,
                title: command.title,
                summary: command.summary,
                payloadJSON: payloadJSON,
                recordDate: command.recordDate,
                recordTime: command.recordTime,
                occurredAt: command.occurredAt,
                balanceMinor: command.balanceMinor,
                currency: command.currency,
                kind: command.kind,
                imagePath: imageReference?.path,
                imageHash: imageReference?.hash,
                createdAt: command.createdAt
            ))
        } catch {
            if let path = imageReference?.path { try? imageStore?.remove(path: path) }
            throw error
        }
    }

    func unlinked() async throws -> [LocalWalletSnapshot] {
        let profile = try profileStore.activeProfile()
        return try repository.unlinked(profileID: profile.id)
    }

    func history() async throws -> [LocalWalletSnapshot] {
        let profile = try profileStore.activeProfile()
        return try repository.history(profileID: profile.id)
    }

    func update(
        _ snapshot: LocalWalletSnapshot,
        title: String,
        summary: String,
        balanceMinor: Int64
    ) async throws -> LocalWalletSnapshot {
        let profile = try profileStore.activeProfile()
        guard profile.id == snapshot.profileID else { throw LocalDataError.invalidIdentifier }
        var payload = try LocalRecordCodec.decode(snapshot.payloadJSON)
        payload["snapshot_balance"] = AnyCodable(Double(balanceMinor) / 100)
        return try repository.update(LocalWalletSnapshotUpdateDraft(
            id: snapshot.id,
            profileID: profile.id,
            expectedVersion: snapshot.localVersion,
            title: title,
            summary: summary,
            payloadJSON: try LocalRecordCodec.encode(payload),
            balanceMinor: balanceMinor,
            updatedAt: Date()
        ))
    }

    func delete(_ snapshot: LocalWalletSnapshot) async throws -> LocalWalletSnapshot {
        let profile = try profileStore.activeProfile()
        guard profile.id == snapshot.profileID else { throw LocalDataError.invalidIdentifier }
        return try repository.delete(
            id: snapshot.id,
            profileID: profile.id,
            expectedVersion: snapshot.localVersion,
            deletedAt: Date()
        )
    }

    func createAccount(from snapshot: LocalWalletSnapshot) async throws -> LocalWalletSnapshotActionResult {
        let profile = try profileStore.activeProfile()
        guard profile.id == snapshot.profileID else { throw LocalDataError.invalidIdentifier }
        let payload = try LocalRecordCodec.decode(snapshot.payloadJSON)
        let accountKind: String
        switch (snapshot.kind, payload.string("account_type") ?? "other") {
        case (.asset, "cash"): accountKind = "cash"
        case (.asset, "wechat"), (.asset, "alipay"): accountKind = "wallet_balance"
        case (.asset, "bank_card"): accountKind = "debit_card"
        case (.asset, "other"): accountKind = "other"
        case (.liability, "credit_card"): accountKind = "credit_card"
        case (.liability, "credit_line"): accountKind = "credit_line"
        default: throw LocalWalletSnapshotActionError.incompatibleAccount
        }
        let payloadAccountName = payload.string("account_name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let accountName = payloadAccountName.isEmpty ? snapshot.title : payloadAccountName
        let account = LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: accountName,
            kind: accountKind,
            currency: snapshot.currency,
            openingBalanceMinor: snapshot.balanceMinor,
            createdAt: Date(),
            billDay: payload.double("bill_day").flatMap { Int(exactly: $0) }
                .flatMap { (1...31).contains($0) ? $0 : nil },
            paymentDueDay: Self.paymentDueDay(payload.string("due_date"))
        )
        return try repository.createAccountFromSnapshot(snapshot, account: account)
    }

    func link(_ snapshot: LocalWalletSnapshot, to accountID: UUID) async throws -> LocalWalletSnapshotActionResult {
        let profile = try profileStore.activeProfile()
        guard profile.id == snapshot.profileID else { throw LocalDataError.invalidIdentifier }
        return try repository.link(snapshot, to: accountID)
    }

    private static func paymentDueDay(_ value: String?) -> Int? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        formatter.calendar?.timeZone = timeZone
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return formatter.calendar.component(.day, from: date)
    }
}
