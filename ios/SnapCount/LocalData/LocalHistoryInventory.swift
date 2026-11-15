import Foundation
import GRDB

enum LocalHistoryInventoryStatus: Equatable {
    case notRead
    case loading
    case complete
    case incomplete
    case failed
}

struct LocalHistoryInventoryProgress {
    let currentTable: LocalHistorySourceTable?
    let currentTableRowsRead: Int
    let totalRowsRead: Int
    let pagesRead: Int
    let completedTables: Set<LocalHistorySourceTable>
    let counts: [String: Int]
}

struct LocalHistoryInventorySnapshot {
    let profileID: String?
    let sampledAt: Date
    let counts: [String: Int]
    let imageVerificationComplete: Bool
    var scope: String { "本机当前 profile · 全日期" }
}

struct LocalHistoryCloudInventory {
    var status: LocalHistoryInventoryStatus
    var sampledAt: Date?
    var counts: [String: Int]
    var completedTables: Set<LocalHistorySourceTable>
    var currentTable: LocalHistorySourceTable?
    var currentTableRowsRead: Int
    var totalRowsRead: Int
    var pagesRead: Int
    var message: String?

    static var notRead: LocalHistoryCloudInventory {
        LocalHistoryCloudInventory(status: .notRead, sampledAt: nil, counts: [:], completedTables: [],
            currentTable: nil, currentTableRowsRead: 0, totalRowsRead: 0, pagesRead: 0, message: nil)
    }
}

enum LocalHistoryInventoryCatalog {
    struct Row: Identifiable {
        let id: String
        let title: String
        let sourceTable: LocalHistorySourceTable?
        let key: String
    }

    static let rows: [Row] = [
        Row(id: "accounts", title: "账户", sourceTable: .accounts, key: "accounts"),
        Row(id: "accounts-archived", title: "归档账户", sourceTable: .accounts, key: "accounts.archived"),
        Row(id: "expenses", title: "已确认消费", sourceTable: .transactions, key: "expenses"),
        Row(id: "pending", title: "待确认消费", sourceTable: .transactions, key: "pending_expenses"),
        Row(id: "transactions-other", title: "其他历史交易形态", sourceTable: .transactions, key: "transactions.other"),
        Row(id: "transactions-deleted", title: "消费/交易删除态", sourceTable: .transactions, key: "transactions.deleted"),
        Row(id: "incomes", title: "收入", sourceTable: .incomes, key: "incomes"),
        Row(id: "incomes-deleted", title: "收入删除态", sourceTable: .incomes, key: "incomes.deleted"),
        Row(id: "food", title: "饮食记录", sourceTable: .records, key: "records.food"),
        Row(id: "sleep", title: "睡眠记录", sourceTable: .records, key: "records.sleep"),
        Row(id: "sport", title: "运动记录", sourceTable: .records, key: "records.sport"),
        Row(id: "reading", title: "阅读记录", sourceTable: .records, key: "records.reading"),
        Row(id: "records-other", title: "其他/未知域记录", sourceTable: .records, key: "records.other"),
        Row(id: "records-deleted", title: "四域/钱包删除态", sourceTable: .records, key: "records.deleted"),
        Row(id: "wallet", title: "钱包快照", sourceTable: .records, key: "records.wallet"),
        Row(id: "staging", title: "候选（待复核）", sourceTable: .staging, key: "staging.pending_review"),
        Row(id: "staging-archived", title: "候选（已归档/已分配）", sourceTable: .staging, key: "staging.archived"),
        Row(id: "staging-discarded", title: "候选（已丢弃）", sourceTable: .staging, key: "staging.discarded"),
        Row(id: "staging-failed", title: "候选（失败）", sourceTable: .staging, key: "staging.failed"),
        Row(id: "staging-other", title: "候选（其他状态）", sourceTable: .staging, key: "staging.other"),
        Row(id: "entries", title: "账户流水（总数 / 有效）", sourceTable: .accountEntries, key: "account_entries"),
        Row(id: "cycles", title: "还款周期", sourceTable: .repaymentCycles, key: "repayment_cycles"),
        Row(id: "payments", title: "还款记录", sourceTable: .payments, key: "payments"),
        Row(id: "history-unresolved", title: "历史待核对（仅保留）", sourceTable: nil, key: "history.unresolved"),
        Row(id: "images", title: "原图（引用 / 去重文件）", sourceTable: nil, key: "images.references")
    ]

    static func cloudCounts(_ rows: [LocalHistorySourceTable: [[String: AnyCodable]]]) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts["accounts"] = rows[.accounts, default: []].count
        let transactions = rows[.transactions, default: []]
        let activeTransactions = transactions.filter {
            ($0["deleted_at"]?.value as? String) == nil && ($0["status"]?.value as? String) != "deleted"
        }
        counts["transactions.deleted"] = transactions.count - activeTransactions.count
        counts["expenses"] = activeTransactions.filter { ($0["type"]?.value as? String) == "expense" && ($0["status"]?.value as? String) == "done" }.count
        counts["pending_expenses"] = activeTransactions.filter { ($0["type"]?.value as? String) == "expense" && ($0["status"]?.value as? String) == "pending" }.count
        counts["transactions.other"] = activeTransactions.count - counts["expenses", default: 0] - counts["pending_expenses", default: 0]
        let incomes = rows[.incomes, default: []]
        counts["incomes"] = incomes.filter { ($0["deleted_at"]?.value as? String) == nil }.count
        counts["incomes.deleted"] = incomes.count - counts["incomes", default: 0]
        counts["accounts.archived"] = rows[.accounts, default: []].filter { ($0["is_archived"]?.value as? Bool) == true }.count
        let records = rows[.records, default: []]
        let activeRecords = records.filter { ($0["deleted_at"]?.value as? String) == nil }
        counts["records.deleted"] = records.count - activeRecords.count
        for domain in ["food", "sleep", "sport", "reading", "wallet"] {
            counts["records.\(domain)"] = activeRecords.filter { ($0["domain_key"]?.value as? String) == domain }.count
        }
        counts["records.other"] = activeRecords.count - ["food", "sleep", "sport", "reading", "wallet"].reduce(0) { $0 + counts["records.\($1)", default: 0] }
        let candidates = rows[.staging, default: []]
        counts["staging.archived"] = candidates.filter {
            ["archived", "assigned", "confirmed"].contains($0["status"]?.value as? String ?? "")
        }.count
        for status in ["discarded", "failed"] {
            counts["staging.\(status)"] = candidates.filter { ($0["status"]?.value as? String) == status }.count
        }
        counts["staging.pending_review"] = candidates.filter {
            ["unassigned", "pending_review"].contains($0["status"]?.value as? String ?? "")
        }.count
        counts["staging.other"] = candidates.count - ["pending_review", "archived", "discarded", "failed"].reduce(0) { $0 + counts["staging.\($1)", default: 0] }
        counts["account_entries"] = rows[.accountEntries, default: []].count
        counts["account_entries.effective"] = rows[.accountEntries, default: []].filter {
            ($0["is_voided"]?.value as? Bool) != true && ($0["voided_at"]?.value as? String) == nil
        }.count
        counts["repayment_cycles"] = rows[.repaymentCycles, default: []].count
        counts["payments"] = rows[.payments, default: []].count
        let imagePaths = rows.flatMap { table, tableRows in
            tableRows.compactMap { row -> String? in
                if (row["deleted_at"]?.value as? String) != nil
                    || (table == .transactions && (row["status"]?.value as? String) == "deleted") { return nil }
                for key in ["image_url", "source_image_path", "image_path"] {
                    if let path = row[key]?.value as? String, !path.isEmpty { return path }
                }
                return nil
            }
        }
        counts["images.references"] = imagePaths.count
        counts["images.unique"] = Set(imagePaths.map(imageObjectKey)).count
        return counts
    }

    private static func imageObjectKey(_ value: String) -> String {
        guard let url = URL(string: value), url.scheme != nil,
              let objectRange = url.path.range(of: "/storage/v1/object/") else {
            let objectPath = value.split(separator: "?", maxSplits: 1).first.map(String.init) ?? value
            return "receipt-images/\(objectPath)"
        }
        let parts = url.path[objectRange.upperBound...].split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, ["sign", "public", "authenticated"].contains(String(parts[0])) else {
            return url.path
        }
        return "\(parts[1])/\(parts.dropFirst(2).joined(separator: "/"))"
    }
}

/// Performs profile-scoped read-only counts. It never creates a profile or contacts the cloud.
final class LocalHistoryInventoryReader {
    private let database: LocalDatabase
    private let imageStore: LocalImageStore
    private let imageVerificationByteLimit: Int

    init(database: LocalDatabase, imageStore: LocalImageStore, imageVerificationByteLimit: Int = 128 * 1024 * 1024) {
        self.database = database
        self.imageStore = imageStore
        self.imageVerificationByteLimit = imageVerificationByteLimit
    }

    func readLocal(at now: Date = Date()) throws -> LocalHistoryInventorySnapshot {
        let read = try database.writer.read { db -> LocalRead in
            let profileID = try String.fetchOne(db, sql: "SELECT id FROM local_profiles ORDER BY created_at ASC, id ASC LIMIT 1")
            var counts = Self.zeroCounts
            guard let profileID else {
                return LocalRead(profileID: nil, counts: counts, imageRows: [])
            }

            counts["accounts"] = try Self.count(db, "SELECT COUNT(*) FROM local_accounts WHERE profile_id = ?", profileID)
            counts["accounts.archived"] = try Self.count(db, "SELECT COUNT(*) FROM local_accounts WHERE profile_id = ? AND is_archived = 1", profileID)
            counts["expenses"] = try Self.count(db, "SELECT COUNT(*) FROM local_expenses WHERE profile_id = ? AND deleted_at IS NULL", profileID)
            counts["transactions.deleted"] = (try Self.count(db, "SELECT COUNT(*) FROM local_expenses WHERE profile_id = ? AND deleted_at IS NOT NULL", profileID))
                + (try Self.count(db, "SELECT COUNT(*) FROM local_pending_transactions WHERE profile_id = ? AND status = 'deleted'", profileID))
            counts["pending_expenses"] = try Self.count(db, "SELECT COUNT(*) FROM local_pending_transactions WHERE profile_id = ? AND status = 'pending'", profileID)
            counts["transactions.other"] = try Self.count(db, "SELECT COUNT(*) FROM local_pending_transactions WHERE profile_id = ? AND status IN ('done','converted')", profileID)
            counts["incomes"] = try Self.count(db, "SELECT COUNT(*) FROM local_income_records WHERE profile_id = ? AND deleted_at IS NULL", profileID)
            counts["incomes.deleted"] = try Self.count(db, "SELECT COUNT(*) FROM local_income_records WHERE profile_id = ? AND deleted_at IS NOT NULL", profileID)
            for domain in ["food", "sleep", "sport", "reading"] {
                counts["records.\(domain)"] = try Self.count(db, "SELECT COUNT(*) FROM local_records WHERE profile_id = ? AND domain_key = '\(domain)' AND deleted_at IS NULL", profileID)
            }
            counts["records.wallet"] = try Self.count(db, "SELECT COUNT(*) FROM local_wallet_snapshots WHERE profile_id = ? AND deleted_at IS NULL", profileID)
            counts["records.deleted"] = (try Self.count(db, "SELECT COUNT(*) FROM local_records WHERE profile_id = ? AND deleted_at IS NOT NULL", profileID))
                + (try Self.count(db, "SELECT COUNT(*) FROM local_wallet_snapshots WHERE profile_id = ? AND deleted_at IS NOT NULL", profileID))
            counts["records.other"] = try Self.count(db, "SELECT COUNT(*) FROM local_records WHERE profile_id = ? AND domain_key NOT IN ('food','sleep','sport','reading') AND deleted_at IS NULL", profileID)
            for status in ["pending_review", "archived", "discarded", "failed"] {
                counts["staging.\(status)"] = try Self.count(db, "SELECT COUNT(*) FROM local_staging_records WHERE profile_id = ? AND status = '\(status)'", profileID)
            }
            counts["staging.other"] = 0
            counts["account_entries"] = try Self.count(db, "SELECT COUNT(*) FROM local_account_entries WHERE profile_id = ?", profileID)
            counts["account_entries.effective"] = try Self.count(db, "SELECT COUNT(*) FROM local_account_entries WHERE profile_id = ? AND is_voided = 0 AND voided_at IS NULL", profileID)
            counts["repayment_cycles"] = try Self.count(db, "SELECT COUNT(*) FROM local_repayment_cycles WHERE profile_id = ?", profileID)
            counts["payments"] = try Self.count(db, "SELECT COUNT(*) FROM local_liability_payments WHERE profile_id = ?", profileID)
            counts["history.unresolved"] = try Self.count(db, "SELECT COUNT(*) FROM local_history_unresolved_records WHERE profile_id = ?", profileID)
            let imageRows = try Self.imageRows(db, profileID: profileID)
            counts["images.references"] = imageRows.count
            return LocalRead(profileID: profileID, counts: counts, imageRows: imageRows)
        }

        var counts = read.counts
        guard read.profileID != nil else {
            return LocalHistoryInventorySnapshot(profileID: nil, sampledAt: now, counts: counts, imageVerificationComplete: true)
        }
        let grouped = Dictionary(grouping: read.imageRows, by: \.path)
        counts["images.unique"] = grouped.count
        var verified = 0
        var cached = 0
        var missing = 0
        var checkedBytes = 0
        var verificationComplete = true
        for (path, references) in grouped.sorted(by: { $0.key < $1.key }) {
            let url = imageStore.url(for: path)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            guard fileSize >= 0, fileSize <= imageVerificationByteLimit - checkedBytes else {
                verificationComplete = false
                break
            }
            do {
                let bytes = try imageStore.data(at: path)
                guard bytes.count <= imageVerificationByteLimit - checkedBytes else {
                    verificationComplete = false
                    break
                }
                cached += 1
                checkedBytes += bytes.count
                let expected = Set(references.compactMap(\.hash).filter { !$0.isEmpty })
                if expected.count == 1, expected.first == LocalImageStore.sha256(bytes) { verified += 1 }
            } catch {
                missing += 1
            }
        }
        counts["images.cached"] = cached
        counts["images.verified"] = verified
        counts["images.missing"] = missing
        counts["images.unverified"] = max(0, grouped.count - verified - missing)
        return LocalHistoryInventorySnapshot(profileID: read.profileID, sampledAt: now, counts: counts,
            imageVerificationComplete: verificationComplete)
    }

    private static var zeroCounts: [String: Int] {
        ["accounts", "accounts.archived", "expenses", "pending_expenses", "transactions.deleted", "incomes", "incomes.deleted", "records.food", "records.sleep", "records.sport",
         "records.reading", "records.wallet", "staging.pending_review", "staging.archived", "staging.discarded",
         "records.other", "records.deleted", "transactions.other", "staging.failed", "staging.other", "account_entries", "account_entries.effective", "repayment_cycles", "payments",
         "history.unresolved", "images.references", "images.unique", "images.cached", "images.verified", "images.missing", "images.unverified"]
            .reduce(into: [:]) { $0[$1] = 0 }
    }

    private static func count(_ db: Database, _ sql: String, _ profileID: String) throws -> Int {
        try Int.fetchOne(db, sql: sql, arguments: [profileID]) ?? 0
    }

    private static func imageRows(_ db: Database, profileID: String) throws -> [ImageRow] {
        var rows: [ImageRow] = []
        for table in ["local_expenses", "local_income_records", "local_records", "local_wallet_snapshots", "local_staging_records", "local_pending_transactions", "local_history_unresolved_records"] {
            let sql: String
            if table == "local_staging_records" || table == "local_history_unresolved_records" {
                sql = "SELECT image_path,image_hash FROM \(table) WHERE profile_id = ? AND image_path IS NOT NULL"
            } else if table == "local_pending_transactions" {
                sql = "SELECT image_path,image_hash FROM \(table) WHERE profile_id = ? AND status <> 'deleted' AND image_path IS NOT NULL"
            } else {
                sql = "SELECT image_path,image_hash FROM \(table) WHERE profile_id = ? AND deleted_at IS NULL AND image_path IS NOT NULL"
            }
            for row in try Row.fetchAll(db, sql: sql, arguments: [profileID]) {
                if let path: String = row["image_path"], !path.isEmpty {
                    rows.append(ImageRow(path: path, hash: row["image_hash"]))
                }
            }
        }
        return rows
    }

    private struct ImageRow {
        let path: String
        let hash: String?
    }

    private struct LocalRead {
        let profileID: String?
        let counts: [String: Int]
        let imageRows: [ImageRow]
    }
}
