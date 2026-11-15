import Foundation
import GRDB

enum LocalLegacySchemaUpgradeError: Error, LocalizedError {
    case unsupported(String)
    case conflict(String)
    var errorDescription: String? {
        switch self {
        case .unsupported(let details): return "旧本地数据库结构无法安全升级：\(details)。原数据已保留。"
        case .conflict(let id): return "旧本地记录稳定ID冲突：\(id)。本次兼容迁移已回滚。"
        }
    }
}

enum LocalLegacySchemaUpgrade {
    private static let walletColumns = Set("id profile_id account_id snapshot_kind amount_minor minimum_payment_minor currency account_name account_type snapshot_date snapshot_time due_date bill_day note payload_json image_path image_hash source_kind local_version created_at updated_at deleted_at".split(separator: " ").map(String.init))
    private static let incomeColumns = Set("id profile_id account_id amount_minor currency income_category source_name income_date income_time note local_version created_at updated_at deleted_at".split(separator: " ").map(String.init))

    static func prepareWalletV16(_ db: Database) throws {
        guard try db.tableExists("local_wallet_snapshots") else { return }
        let columns = try columnNames("local_wallet_snapshots", db)
        if columns != walletColumns {
            let modern = Set("id profile_id title summary payload_json record_date record_time occurred_at snapshot_balance_minor currency account_snapshot_kind linked_account_id image_path image_hash local_version created_at updated_at deleted_at".split(separator: " ").map(String.init))
            let applied = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier='local-v16-wallet-snapshot-facts'") == 1
            if applied, modern.isSubset(of: columns), columns.subtracting(modern).isSubset(of: ["linked_action"]) { return }
            throw try unknown("local_wallet_snapshots", columns, db)
        }
        try validateTypes("local_wallet_snapshots", integerFields: ["amount_minor", "minimum_payment_minor", "bill_day", "local_version"], db)
        guard try !db.tableExists("local_wallet_snapshots_legacy_v9") else { throw LocalLegacySchemaUpgradeError.conflict("local_wallet_snapshots_legacy_v9") }
        try db.execute(sql: "ALTER TABLE local_wallet_snapshots RENAME TO local_wallet_snapshots_legacy_v9")
        try db.execute(sql: "DROP INDEX IF EXISTS local_wallet_snapshots_profile_date_idx; DROP INDEX IF EXISTS local_wallet_snapshots_profile_account_idx")
    }

    static func finishWalletV16(_ db: Database) throws {
        guard try db.tableExists("local_wallet_snapshots_legacy_v9") else { return }
        for row in try Row.fetchAll(db, sql: "SELECT * FROM local_wallet_snapshots_legacy_v9") {
            guard let json: String = row["payload_json"],
                  var payload = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw LocalDataError.invalidRecord }
            var original: [String: Any] = [:]
            for key in walletColumns {
                let value: DatabaseValue = row[key]
                original[key] = value.isNull ? NSNull() : value.storage.jsonValue
            }
            var key = "_legacy_wallet_v9"
            while payload[key] != nil { key += "_" }
            payload[key] = original
            let payloadJSON = String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
            var values = copied(row, keys: ["id", "profile_id", "currency", "image_path", "image_hash", "local_version", "created_at", "updated_at", "deleted_at"])
            values["title"] = row["account_name"]; values["summary"] = (row["note"] as String? ?? "").databaseValue
            values["payload_json"] = payloadJSON.databaseValue
            values["record_date"] = row["snapshot_date"]; values["record_time"] = row["snapshot_time"]
            values["occurred_at"] = try occurredAt(row, date: "snapshot_date", time: "snapshot_time", iso: true)
            values["snapshot_balance_minor"] = row["amount_minor"]; values["account_snapshot_kind"] = row["snapshot_kind"]
            values["linked_account_id"] = row["account_id"]
            try insert(values, table: "local_wallet_snapshots", db)
        }
    }

    static func copyLegacyIncome(_ db: Database) throws {
        guard try db.tableExists("local_incomes") else { return }
        let columns = try columnNames("local_incomes", db)
        guard columns == incomeColumns else { throw try unknown("local_incomes", columns, db) }
        try validateTypes("local_incomes", integerFields: ["amount_minor", "local_version"], db)
        let targetColumns = try columnNames("local_income_records", db)
        for row in try Row.fetchAll(db, sql: "SELECT * FROM local_incomes") {
            var values = copied(row, keys: ["id", "profile_id", "account_id", "amount_minor", "currency", "income_date", "note", "local_version", "created_at", "updated_at", "deleted_at"])
            values["source_name"] = (row["source_name"] as String? ?? "").databaseValue
            values["category"] = row["income_category"]
            values["occurred_at"] = try occurredAt(row, date: "income_date", time: "income_time", iso: false)
            for key in ["image_path", "image_hash", "source_pending_transaction_id"] where targetColumns.contains(key) { values[key] = .null }
            try insert(values, table: "local_income_records", db)
        }
    }

    private static func insert(_ values: [String: DatabaseValue], table: String, _ db: Database) throws {
        let id = values["id"] ?? .null
        if let existing = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id=?", arguments: [id]) {
            guard values.allSatisfy({ (existing[$0.key] as DatabaseValue) == $0.value }) else { throw LocalLegacySchemaUpgradeError.conflict(String(describing: id)) }
            return
        }
        let keys = values.keys.sorted()
        try db.execute(sql: "INSERT INTO \(table) (\(keys.joined(separator: ","))) VALUES (\(keys.map { _ in "?" }.joined(separator: ",")))", arguments: StatementArguments(keys.map { values[$0]! }))
    }
    private static func copied(_ row: Row, keys: [String]) -> [String: DatabaseValue] {
        Dictionary(uniqueKeysWithValues: keys.map { ($0, row[$0] as DatabaseValue) })
    }
    private static func columnNames(_ table: String, _ db: Database) throws -> Set<String> {
        Set(try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { $0["name"] as String })
    }
    private static func validateTypes(_ table: String, integerFields: Set<String>, _ db: Database) throws {
        for row in try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))") {
            let name: String = row["name"], type: String = row["type"]
            let expected = integerFields.contains(name) ? "INTEGER" : ["created_at", "updated_at", "deleted_at"].contains(name) ? "DATETIME" : "TEXT"
            guard type.uppercased() == expected else { throw LocalLegacySchemaUpgradeError.unsupported("\(table).\(name) type=\(type), expected=\(expected)") }
        }
    }
    private static func unknown(_ table: String, _ columns: Set<String>, _ db: Database) throws -> LocalLegacySchemaUpgradeError {
        let ids = try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        return .unsupported("\(table) columns=\(columns.sorted()) migrations=\(ids)")
    }
    private static func occurredAt(_ row: Row, date: String, time: String, iso: Bool) throws -> DatabaseValue {
        guard let clock: String = row[time] else { return .null }
        let day: String = row[date]
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"; formatter.isLenient = false
        let text = day + " " + (clock.count == 5 ? clock + ":00" : clock)
        guard let value = formatter.date(from: text), formatter.string(from: value) == text else { throw LocalDataError.invalidRecord }
        return iso ? ISO8601DateFormatter().string(from: value).databaseValue : value.databaseValue
    }
}

private extension DatabaseValue.Storage {
    var jsonValue: Any {
        switch self {
        case .null: return NSNull()
        case .int64(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        case .blob(let value): return value.base64EncodedString()
        }
    }
}
