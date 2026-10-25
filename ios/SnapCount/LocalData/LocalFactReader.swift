import Foundation
import GRDB

enum LocalFactKind: String, Equatable, Hashable, Sendable {
    case expense
    case income
    case record
}

struct LocalFact: Equatable, Identifiable, Sendable {
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

struct LocalFactMonth: Equatable, Sendable {
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
            try Self.readMonth(db, profileID: profileID, from: startDate, to: endDate)
        }
    }

    /// 用 GRDB 自己的队列读取，避免首页在主执行器同步等待 SQLite 和逐条投影。
    /// 当前固定 GRDB 6.29.3 的异步 read 不随页面取消；AppState 仍核对身份和读取版本。
    func activeMonth(monthKey: String) async throws -> LocalFactMonth? {
        try await database.writer.read { db in
            guard let value = try String.fetchOne(db, sql: "SELECT id FROM local_profiles ORDER BY created_at ASC, id ASC LIMIT 1"),
                  let profileID = UUID(uuidString: value) else { return nil }
            return try Self.readMonth(db, profileID: profileID, from: "\(monthKey)-01", to: "\(monthKey)-31")
        }
    }

    func activeRange(from startDate: String, to endDate: String) async throws -> LocalFactMonth? {
        try await database.writer.read { db in
            guard let value = try String.fetchOne(db, sql: "SELECT id FROM local_profiles ORDER BY created_at ASC, id ASC LIMIT 1"),
                  let profileID = UUID(uuidString: value) else { return nil }
            return try Self.readMonth(db, profileID: profileID, from: startDate, to: endDate)
        }
    }

    private static func readMonth(_ db: Database, profileID: UUID, from startDate: String, to endDate: String) throws -> LocalFactMonth {
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
            let incomes = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_income_records
                    WHERE profile_id = ? AND income_date BETWEEN ? AND ? AND deleted_at IS NULL
                    """,
                arguments: [profileID.uuidString, startDate, endDate]
            ).map { try Self.fact(incomeRow: $0) }
            let records = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_records
                    WHERE profile_id = ?
                      AND domain_key IN ('food', 'sleep', 'sport', 'reading')
                      AND (domain_key = 'sleep' OR record_date BETWEEN ? AND ?)
                      AND deleted_at IS NULL
                    """,
                arguments: [profileID.uuidString, startDate, endDate]
            ).map { try Self.fact(recordRow: $0) }.filter { $0.businessDate >= startDate && $0.businessDate <= endDate }

            return LocalFactMonth(
                profileID: profileID,
                facts: (expenses + incomes + records).sorted(by: Self.isNewer)
            )
    }

    private static func fact(expenseRow row: Row) throws -> LocalFact {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let transactionDate: String = row["transaction_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return fact(from: LocalExpense(
            id: id,
            profileID: profileID,
            accountID: (row["account_id"] as String?).flatMap(UUID.init(uuidString:)),
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
            updatedAt: updatedAt, imagePath: row["image_path"], imageHash: row["image_hash"]
        ))
    }

    private static func fact(incomeRow row: Row) throws -> LocalFact {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let incomeDate: String = row["income_date"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else { throw LocalDataError.invalidRecord }
        let accountText: String? = row["account_id"]
        let income = LocalIncome(
            id: id, profileID: profileID,
            accountID: accountText.flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"], currency: row["currency"],
            sourceName: row["source_name"], category: row["category"],
            incomeDate: incomeDate, occurredAt: row["occurred_at"], note: row["note"],
            localVersion: row["local_version"], createdAt: createdAt, updatedAt: updatedAt, imagePath: row["image_path"], imageHash: row["image_hash"]
        )
        return fact(from: income)
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
            accountID: expense.accountID?.uuidString
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
            imagePath: expense.imagePath,
            imageHash: expense.imageHash,
            localVersion: expense.localVersion,
            createdAt: expense.createdAt,
            updatedAt: expense.updatedAt
        )
    }

    private static func fact(from income: LocalIncome) -> LocalFact {
        let payload = IncomeFactPayload(
            amountMinor: income.amountMinor, currency: income.currency,
            sourceName: income.sourceName, category: income.category,
            accountID: income.accountID?.uuidString
        )
        return LocalFact(
            id: income.id, profileID: income.profileID,
            reference: "income/\(income.id.uuidString)", kind: .income,
            domainKey: "income", sourceKind: "manual", domainVersion: "local-v1",
            title: income.sourceName.isEmpty ? "收入记录" : income.sourceName, summary: income.category,
            payloadJSON: (try? encode(payload)) ?? "{}", businessDate: income.incomeDate,
            recordTime: income.occurredAt.map { NativeLocalDate.timeKey($0) },
            occurredAt: income.occurredAt.map { ISO8601DateFormatter().string(from: $0) },
            note: income.note, imagePath: income.imagePath, imageHash: income.imageHash,
            localVersion: income.localVersion, createdAt: income.createdAt, updatedAt: income.updatedAt
        )
    }

    private static func fact(from record: LocalRecord) -> LocalFact {
        let businessDate = NativeSleepFacts.businessDate(
            domainKey: record.domainKey, payload: (try? LocalRecordCodec.decode(record.payloadJSON)) ?? [:], fallback: record.recordDate
        )
        // ponytail: 旧睡眠无需改写历史行，暂在读层按醒来日过滤；数据量增大后迁移并索引规范业务日。
        return LocalFact(
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
            businessDate: businessDate,
            recordTime: record.recordTime,
            occurredAt: NativeLocalDate.financeOccurredAt(
                dateKey: businessDate,
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
    let accountID: String?

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
    let sourceName: String
    let category: String
    let accountID: String?
    enum CodingKeys: String, CodingKey {
        case amountMinor = "amount_minor"
        case currency
        case sourceName = "source_name"
        case category
        case accountID = "account_id"
    }
}
