import Foundation
import GRDB

enum LocalFactKind: String, Equatable, Hashable {
    case expense
    case record
}

struct LocalFact: Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let reference: String
    let kind: LocalFactKind
    let domainKey: String
    let sourceKind: String
    let domainVersion: String
    let title: String
    let summary: String
    let payloadJSON: String
    let businessDate: String
    let recordTime: String?
    let occurredAt: String?
    let note: String?
    let imagePath: String?
    let imageHash: String?
    let localVersion: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct LocalFactMonth: Equatable {
    let profileID: UUID
    let facts: [LocalFact]
}

/// Read-only projection of local formal facts across all Phase 1 domains.
/// Staging rows and tombstones are intentionally absent from this boundary.
final class LocalFactReader {
    private let database: LocalDatabase

    init(database: LocalDatabase) throws {
        self.database = database
    }

    func activeProfileID() throws -> UUID? {
        try database.writer.read { db in
            guard let value = try String.fetchOne(
                db,
                sql: "SELECT id FROM local_profiles ORDER BY created_at ASC, id ASC LIMIT 1"
            ) else { return nil }
            return UUID(uuidString: value)
        }
    }

    func month(profileID: UUID, monthKey: String) throws -> LocalFactMonth {
        try range(
            profileID: profileID,
            from: "\(monthKey)-01",
            to: "\(monthKey)-31"
        )
    }

    func range(profileID: UUID, from startDate: String, to endDate: String) throws -> LocalFactMonth {
        try database.writer.read { db in
            let expenses = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_expenses
                    WHERE profile_id = ?
                      AND transaction_date BETWEEN ? AND ?
                      AND deleted_at IS NULL
                    """,
                arguments: [profileID.uuidString, startDate, endDate]
            ).map { try Self.fact(expenseRow: $0) }
            let records = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_records
                    WHERE profile_id = ?
                      AND domain_key IN ('food', 'sleep', 'sport', 'reading')
                      AND record_date BETWEEN ? AND ?
                      AND deleted_at IS NULL
                    """,
                arguments: [profileID.uuidString, startDate, endDate]
            ).map { try Self.fact(recordRow: $0) }
            let incomes = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_incomes
                    WHERE profile_id = ?
                      AND income_date BETWEEN ? AND ?
                      AND deleted_at IS NULL
                    """,
                arguments: [profileID.uuidString, startDate, endDate]
            ).map { try Self.fact(incomeRow: $0) }
            let walletSnapshots = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_wallet_snapshots
                    WHERE profile_id = ?
                      AND snapshot_date BETWEEN ? AND ?
                      AND deleted_at IS NULL
                    """,
                arguments: [profileID.uuidString, startDate, endDate]
            ).map { try Self.fact(walletRow: $0) }

            return LocalFactMonth(
                profileID: profileID,
                facts: (expenses + records + incomes + walletSnapshots).sorted(by: Self.isNewer)
            )
        }
    }

    private static func fact(expenseRow row: Row) throws -> LocalFact {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let accountID = UUID(uuidString: row["account_id"]),
              let transactionDate: String = row["transaction_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return fact(from: LocalExpense(
            id: id,
            profileID: profileID,
            accountID: accountID,
            amountMinor: row["amount_minor"],
            currency: row["currency"],
            merchantName: row["merchant_name"],
            platform: row["platform"],
            category: row["category"],
            paymentMethod: row["payment_method"],
            transactionDate: transactionDate,
            transactionTime: row["transaction_time"],
            note: row["note"],
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        ))
    }

    private static func fact(recordRow row: Row) throws -> LocalFact {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let domainKey: String = row["domain_key"],
              let title: String = row["title"],
              let summary: String = row["summary"],
              let payloadJSON: String = row["payload_json"],
              let recordDate: String = row["record_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return fact(from: LocalRecord(
            id: id,
            profileID: profileID,
            domainKey: domainKey,
            title: title,
            summary: summary,
            payloadJSON: payloadJSON,
            recordDate: recordDate,
            recordTime: row["record_time"],
            note: row["note"],
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            sourceKind: LocalRecordSourceKind(rawValue: row["source_kind"]) ?? .manual,
            domainVersion: row["domain_version"],
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        ))
    }

    private static func fact(incomeRow row: Row) throws -> LocalFact {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let currency: String = row["currency"],
              let incomeCategory: String = row["income_category"],
              let incomeDate: String = row["income_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        let accountID: String? = row["account_id"]
        let sourceName: String? = row["source_name"]
        let note: String? = row["note"]
        let incomeTime: String? = row["income_time"]
        let payload = IncomeFactPayload(
            amountMinor: row["amount_minor"],
            currency: currency,
            incomeCategory: incomeCategory,
            sourceName: sourceName,
            incomeDate: incomeDate,
            incomeTime: incomeTime,
            note: note,
            accountID: accountID
        )
        return LocalFact(
            id: id,
            profileID: profileID,
            reference: "income/\(id.uuidString)",
            kind: .record,
            domainKey: "income",
            sourceKind: "manual",
            domainVersion: "local-v1",
            title: sourceName ?? "收入记录",
            summary: incomeCategory,
            payloadJSON: (try? encode(payload)) ?? "{}",
            businessDate: incomeDate,
            recordTime: incomeTime,
            occurredAt: NativeLocalDate.financeOccurredAt(
                dateKey: incomeDate,
                timeKey: incomeTime
            ),
            note: note,
            imagePath: nil,
            imageHash: nil,
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func fact(walletRow row: Row) throws -> LocalFact {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let snapshotKind: String = row["snapshot_kind"],
              let accountName: String = row["account_name"],
              let payloadJSON: String = row["payload_json"],
              let snapshotDate: String = row["snapshot_date"],
              let sourceKind: String = row["source_kind"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalFact(
            id: id,
            profileID: profileID,
            reference: "wallet/\(id.uuidString)",
            kind: .record,
            domainKey: "wallet",
            sourceKind: sourceKind,
            domainVersion: "wallet-v1",
            title: accountName,
            summary: snapshotKind == "liability" ? "负债快照" : "资产快照",
            payloadJSON: payloadJSON,
            businessDate: snapshotDate,
            recordTime: row["snapshot_time"],
            occurredAt: NativeLocalDate.financeOccurredAt(
                dateKey: snapshotDate,
                timeKey: row["snapshot_time"]
            ),
            note: row["note"],
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func fact(from expense: LocalExpense) -> LocalFact {
        let payload = ExpenseFactPayload(
            amountMinor: expense.amountMinor,
            currency: expense.currency,
            merchantName: expense.merchantName,
            platform: expense.platform,
            category: expense.category,
            paymentMethod: expense.paymentMethod,
            transactionDate: expense.transactionDate,
            transactionTime: expense.transactionTime,
            note: expense.note,
            accountID: expense.accountID.uuidString
        )
        let payloadJSON = (try? encode(payload)) ?? "{}"
        return LocalFact(
            id: expense.id,
            profileID: expense.profileID,
            reference: "expense/\(expense.id.uuidString)",
            kind: .expense,
            domainKey: "expense",
            sourceKind: "manual",
            domainVersion: "local-v1",
            title: expense.merchantName,
            summary: expense.category,
            payloadJSON: payloadJSON,
            businessDate: expense.transactionDate,
            recordTime: expense.transactionTime,
            occurredAt: NativeLocalDate.financeOccurredAt(
                dateKey: expense.transactionDate,
                timeKey: expense.transactionTime
            ),
            note: expense.note,
            imagePath: nil,
            imageHash: nil,
            localVersion: expense.localVersion,
            createdAt: expense.createdAt,
            updatedAt: expense.updatedAt
        )
    }

    private static func fact(from record: LocalRecord) -> LocalFact {
        LocalFact(
            id: record.id,
            profileID: record.profileID,
            reference: "data/\(record.id.uuidString)",
            kind: .record,
            domainKey: record.domainKey,
            sourceKind: record.sourceKind.rawValue,
            domainVersion: "local-v\(record.domainVersion)",
            title: record.title,
            summary: record.summary,
            payloadJSON: record.payloadJSON,
            businessDate: record.recordDate,
            recordTime: record.recordTime,
            occurredAt: NativeLocalDate.financeOccurredAt(
                dateKey: record.recordDate,
                timeKey: record.recordTime
            ),
            note: record.note,
            imagePath: record.imagePath,
            imageHash: record.imageHash,
            localVersion: record.localVersion,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
    }

    private static func isNewer(_ lhs: LocalFact, _ rhs: LocalFact) -> Bool {
        if lhs.businessDate != rhs.businessDate {
            return lhs.businessDate > rhs.businessDate
        }
        let lhsTime = lhs.recordTime ?? ""
        let rhsTime = rhs.recordTime ?? ""
        if lhsTime != rhsTime {
            return lhsTime > rhsTime
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

private struct ExpenseFactPayload: Encodable {
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let accountID: String

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case merchantName = "merchant_name"
        case platform
        case category
        case paymentMethod = "payment_method"
        case transactionDate = "transaction_date"
        case transactionTime = "transaction_time"
        case note
        case accountID = "account_id"
    }
}

private struct IncomeFactPayload: Encodable {
    let amountMinor: Int64
    let currency: String
    let incomeCategory: String
    let sourceName: String?
    let incomeDate: String
    let incomeTime: String?
    let note: String?
    let accountID: String?

    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case incomeCategory = "income_category"
        case sourceName = "source_name"
        case incomeDate = "income_date"
        case incomeTime = "income_time"
        case note
        case accountID = "account_id"
    }
}
