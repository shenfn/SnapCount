import Foundation
import CoreFoundation
import GRDB

struct LocalCompleteBackupPreview: Equatable {
    let profileID: String
    let formatName: String
    let schemaVersion: Int
    let tableCounts: [String: Int]
    let imageCount: Int
    let imageBytes: Int

    var totalRows: Int { tableCounts.values.reduce(0, +) }

    var confirmationText: String {
        let accounts = tableCounts["local_accounts", default: 0]
        let expenses = tableCounts["local_expenses", default: 0]
        let incomes = tableCounts["local_income_records", default: 0]
        let records = tableCounts["local_records", default: 0]
        let wallets = tableCounts["local_wallet_snapshots", default: 0]
        let candidates = tableCounts["local_staging_records", default: 0]
        let ledger = tableCounts["local_account_entries", default: 0]
            + tableCounts["local_repayment_cycles", default: 0]
            + tableCounts["local_liability_payments", default: 0]
        let imageSize = ByteCountFormatter.string(fromByteCount: Int64(imageBytes), countStyle: .file)
        let scope = [
            "账户 \(accounts)", "消费 \(expenses)", "收入 \(incomes)",
            "其他记录 \(records)", "钱包快照 \(wallets)", "候选 \(candidates)", "账务关系/历史 \(ledger)"
        ].joined(separator: "、")
        return "\(formatName) v\(schemaVersion)。\(scope)。共 \(totalRows) 条，图片 \(imageCount) 张（\(imageSize)）。导入会合并到本机当前数据；冲突时整包回滚。不会恢复登录、同步授权或 API Key。"
    }
}

struct LocalCompleteBackupImportResult: Equatable {
    let insertedRows: Int
    let skippedRows: Int
    let restoredImages: Int
}

enum LocalCompleteBackupError: Error, Equatable, LocalizedError {
    case invalidFormat
    case unsupportedSchemaVersion(Int)
    case archiveTooLarge
    case invalidRows(String)
    case duplicateID(String)
    case conflictingStableID(String)
    case invalidImage(String)
    case missingImage(String)

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "备份格式无效或已损坏。"
        case .unsupportedSchemaVersion(let version): "暂不支持版本 \(version) 的完整备份。"
        case .archiveTooLarge: "备份超过本地导入上限。"
        case .invalidRows(let table): "备份中的 \(table) 记录无效或关系不完整。"
        case .duplicateID(let id): "备份内存在重复稳定标识：\(id)"
        case .conflictingStableID(let id): "本机已存在内容不同的稳定标识：\(id)。本次导入未写入数据。"
        case .invalidImage(let path): "备份图片校验失败：\(path)"
        case .missingImage(let path): "完整备份缺少本地图片：\(path)"
        }
    }
}

/// Full local recovery excludes credentials, cloud binding, sync state and the upload outbox.
final class LocalCompleteBackupPortability {
    static let currentSchemaVersion = 18
    // ponytail: 128 MiB of image bytes keeps JSON/base64 imports bounded; raise with streaming archive support.
    private static let maximumImageBytes = 128 * 1024 * 1024
    private static let maximumArchiveBytes = 180 * 1024 * 1024
    private static let maximumRows = 100_000

    private static let tableNames = [
        "local_accounts",
        "local_records",
        "local_expenses",
        "local_income_records",
        "local_staging_records",
        "local_repayment_cycles",
        "local_liability_payments",
        "local_account_entries",
        "local_image_intakes",
        "local_wallet_snapshots"
    ]

    private let database: LocalDatabase
    private let profileStore: LocalProfileStore
    private let imageStore: LocalImageStore

    init(database: LocalDatabase, imageStore: LocalImageStore) {
        self.database = database
        self.profileStore = LocalProfileStore(database: database)
        self.imageStore = imageStore
    }

    func exportBackup(exportedAt: Date = Date()) throws -> Data {
        let profile = try profileStore.activeProfile()
        let archive = try database.writer.read { db -> Archive in
            var tables: [String: String] = [:]
            for table in Self.tableNames {
                let columns = try Self.columns(in: db, table: table)
                let pairs = columns.map { "'\($0)',\(Self.quote($0))" }.joined(separator: ",")
                let sql = """
                    SELECT COALESCE(json_group_array(json(row_json)), '[]')
                    FROM (
                        SELECT json_object(\(pairs)) AS row_json
                        FROM \(Self.quote(table))
                        WHERE profile_id = ?
                        ORDER BY id
                    )
                    """
                tables[table] = try String.fetchOne(db, sql: sql, arguments: [profile.id.uuidString]) ?? "[]"
            }

            var imageReferences: [String: String] = [:]
            for (table, condition) in [
                ("local_records", "deleted_at IS NULL"),
                ("local_staging_records", "status IN ('pending_review', 'failed')"),
                ("local_image_intakes", "status IN ('failed', 'receiving')"),
                ("local_wallet_snapshots", "1 = 1")
            ] {
                for row in try Row.fetchAll(
                    db,
                    sql: "SELECT image_path, image_hash FROM \(Self.quote(table)) WHERE profile_id = ? AND (\(condition)) AND image_path IS NOT NULL",
                    arguments: [profile.id.uuidString]
                ) {
                    guard let path: String = row["image_path"],
                          let hash: String = row["image_hash"] else { throw LocalCompleteBackupError.invalidRows(table) }
                    if let old = imageReferences[path], old != hash { throw LocalCompleteBackupError.invalidImage(path) }
                    imageReferences[path] = hash
                }
            }
            let images = try imageReferences.keys.sorted().map { path -> ImageFile in
                guard Self.isAllowedImagePath(path),
                      let data = try? imageStore.data(at: path) else {
                    throw LocalCompleteBackupError.missingImage(path)
                }
                let expectedHash = imageReferences[path]!
                guard LocalImageStore.sha256(data) == expectedHash else {
                    throw LocalCompleteBackupError.invalidImage(path)
                }
                return ImageFile(path: path, hash: expectedHash, data: data)
            }
            let imageBytes = images.reduce(0) { $0 + $1.data.count }
            guard imageBytes <= Self.maximumImageBytes else { throw LocalCompleteBackupError.archiveTooLarge }
            let rowCount = try tables.values.reduce(0) { total, json in
                guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
                      let rows = value as? [Any] else { throw LocalCompleteBackupError.invalidFormat }
                return total + rows.count
            }
            guard rowCount <= Self.maximumRows else { throw LocalCompleteBackupError.archiveTooLarge }
            return Archive(
                format: Archive.formatName,
                schemaVersion: Self.currentSchemaVersion,
                exportedAt: ISO8601DateFormatter().string(from: exportedAt),
                profileID: profile.id.uuidString,
                tables: tables,
                images: images
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= Self.maximumArchiveBytes else { throw LocalCompleteBackupError.archiveTooLarge }
        return data
    }

    func preview(_ data: Data) throws -> LocalCompleteBackupPreview {
        guard data.count <= Self.maximumArchiveBytes else { throw LocalCompleteBackupError.archiveTooLarge }
        if Self.isLegacyExpenseArchive(data) {
            let legacy = try LocalExpensePortability(database: database).previewArchive(data)
            return LocalCompleteBackupPreview(
                profileID: legacy.profile.id.uuidString,
                formatName: "旧版消费归档",
                schemaVersion: legacy.schemaVersion,
                tableCounts: [
                    "local_accounts": legacy.accounts.count,
                    "local_expenses": legacy.expenses.count,
                    "local_account_entries": legacy.accountEntries.count
                ],
                imageCount: 0,
                imageBytes: 0
            )
        }
        let decoded = try decode(data)
        return LocalCompleteBackupPreview(
            profileID: decoded.archive.profileID,
            formatName: Archive.formatName,
            schemaVersion: decoded.archive.schemaVersion,
            tableCounts: decoded.rows.mapValues(\.count),
            imageCount: decoded.imageData.count,
            imageBytes: decoded.archive.images.reduce(0) { $0 + $1.data.count }
        )
    }

    func importBackup(_ data: Data, into targetProfileID: UUID) throws -> LocalCompleteBackupImportResult {
        guard data.count <= Self.maximumArchiveBytes else { throw LocalCompleteBackupError.archiveTooLarge }
        if Self.isLegacyExpenseArchive(data) {
            let result = try LocalExpensePortability(database: database).importArchive(
                data,
                enqueueOutbox: false,
                remapProfileID: targetProfileID
            )
            return LocalCompleteBackupImportResult(
                insertedRows: result.insertedAccounts + result.insertedExpenses + result.insertedAccountEntries,
                skippedRows: result.skippedAccounts + result.skippedExpenses + result.skippedAccountEntries,
                restoredImages: 0
            )
        }
        let decoded = try decode(data)
        var createdImagePaths: [String] = []
        do {
            return try database.writer.write { db in
                guard try Int.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM local_profiles WHERE id = ?)",
                    arguments: [targetProfileID.uuidString]
                ) == 1 else { throw LocalDataError.invalidIdentifier }

                var skipped = Set<String>()
                for table in Self.tableNames {
                    let columns = try Self.columns(in: db, table: table)
                    let pairs = columns.map { "'\($0)',\(Self.quote($0))" }.joined(separator: ",")
                    for row in decoded.rows[table] ?? [] {
                        guard let id = row["id"] as? String else { throw LocalCompleteBackupError.invalidRows(table) }
                        let targetID = try Self.mappedID(table: table, row: row, targetProfileID: targetProfileID)
                        if let existing = try String.fetchOne(
                            db,
                            sql: "SELECT json_object(\(pairs)) FROM \(Self.quote(table)) WHERE id = ?",
                            arguments: [targetID]
                        ) {
                            var incoming = try Self.dictionary(from: row)
                            incoming["id"] = targetID
                            incoming["profile_id"] = targetProfileID.uuidString
                            Self.normalizeInterruptedIntake(&incoming)
                            let existingObject = try JSONSerialization.jsonObject(
                                with: Data(existing.utf8),
                                options: [.fragmentsAllowed]
                            )
                            guard try Self.canonicalJSON(existingObject) == Self.canonicalJSON(incoming) else {
                                throw LocalCompleteBackupError.conflictingStableID(id)
                            }
                            skipped.insert("\(table):\(id)")
                        }
                    }
                }

                for image in decoded.archive.images {
                    guard let imageData = decoded.imageData[image.path] else {
                        throw LocalCompleteBackupError.invalidImage(image.path)
                    }
                    if try imageStore.restore(data: imageData, at: image.path, expectedHash: image.hash) {
                        createdImagePaths.append(image.path)
                    }
                }

                var inserted = 0
                for table in Self.tableNames {
                    let columns = try Self.columns(in: db, table: table)
                    for sourceRow in decoded.rows[table] ?? [] {
                        guard let id = sourceRow["id"] as? String,
                              !skipped.contains("\(table):\(id)") else { continue }
                        var row = try Self.dictionary(from: sourceRow)
                        row["id"] = try Self.mappedID(table: table, row: sourceRow, targetProfileID: targetProfileID)
                        row["profile_id"] = targetProfileID.uuidString
                        Self.normalizeInterruptedIntake(&row)
                        let json = try Self.canonicalJSON(row)
                        let names = columns.map(Self.quote).joined(separator: ",")
                        var arguments: [String] = []
                        let values = columns.map { column -> String in
                            if table == "local_accounts", column == "auto_debit_account_id" { return "NULL" }
                            if column == "profile_id" {
                                arguments.append(targetProfileID.uuidString)
                                return "?"
                            }
                            arguments.append(json)
                            return "json_extract(?, '$.\(column)')"
                        }.joined(separator: ",")
                        try db.execute(
                            sql: "INSERT INTO \(Self.quote(table)) (\(names)) VALUES (\(values))",
                            arguments: StatementArguments(arguments)
                        )
                        inserted += 1
                    }
                }

                // Resolve account-to-account references after every account exists.
                for sourceRow in decoded.rows["local_accounts"] ?? [] {
                    guard let id = sourceRow["id"] as? String,
                          !skipped.contains("local_accounts:\(id)") else { continue }
                    let row = try Self.dictionary(from: sourceRow)
                    let json = try Self.canonicalJSON(row)
                    try db.execute(
                        sql: "UPDATE local_accounts SET auto_debit_account_id = json_extract(?, '$.auto_debit_account_id') WHERE id = ? AND profile_id = ?",
                        arguments: [json, id, targetProfileID.uuidString]
                    )
                }
                return LocalCompleteBackupImportResult(
                    insertedRows: inserted,
                    skippedRows: skipped.count,
                    restoredImages: createdImagePaths.count
                )
            }
        } catch {
            for path in createdImagePaths { try? imageStore.remove(path: path) }
            throw error
        }
    }

    func importBackupIntoActiveProfile(_ data: Data) throws -> LocalCompleteBackupImportResult {
        let profile = try profileStore.activeProfile()
        return try importBackup(data, into: profile.id)
    }

    private func decode(_ data: Data) throws -> DecodedArchive {
        guard data.count <= Self.maximumArchiveBytes else { throw LocalCompleteBackupError.archiveTooLarge }
        let archive: Archive
        do { archive = try JSONDecoder().decode(Archive.self, from: data) }
        catch { throw LocalCompleteBackupError.invalidFormat }
        guard archive.format == Archive.formatName else { throw LocalCompleteBackupError.invalidFormat }
        guard [15, 16, 17, Self.currentSchemaVersion].contains(archive.schemaVersion) else {
            throw LocalCompleteBackupError.unsupportedSchemaVersion(archive.schemaVersion)
        }
        var tables = archive.tables
        let archiveTables = Set(tables.keys)
        let legacyTables = Set(Self.tableNames.dropLast())
        let hasCurrentTables = archive.schemaVersion >= 16
            && archiveTables == Set(Self.tableNames)
        let hasLegacyTables = archive.schemaVersion == 15 && archiveTables == legacyTables
        guard UUID(uuidString: archive.profileID) != nil,
              hasCurrentTables || hasLegacyTables else {
            throw LocalCompleteBackupError.invalidFormat
        }
        if hasLegacyTables { tables["local_wallet_snapshots"] = "[]" }

        var rows: [String: [[String: Any]]] = [:]
        var totalRows = 0
        for table in Self.tableNames {
            guard let json = tables[table],
                  let value = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
                  let tableRows = value as? [[String: Any]] else {
                throw LocalCompleteBackupError.invalidRows(table)
            }
            totalRows += tableRows.count
            guard totalRows <= Self.maximumRows else { throw LocalCompleteBackupError.archiveTooLarge }
            var ids = Set<String>()
            for row in tableRows {
                guard let id = row["id"] as? String,
                      let profileID = row["profile_id"] as? String,
                      profileID == archive.profileID else {
                    throw LocalCompleteBackupError.invalidRows(table)
                }
                guard ids.insert(id).inserted else { throw LocalCompleteBackupError.duplicateID(id) }
            }
            rows[table] = tableRows
        }
        if archive.schemaVersion == 16 {
            if var wallets = rows["local_wallet_snapshots"] {
                for index in wallets.indices {
                    if wallets[index]["linked_action"] == nil {
                        wallets[index]["linked_action"] = NSNull()
                    }
                }
                rows["local_wallet_snapshots"] = wallets
            }
        }
        try Self.validateFinancialRows(rows)

        var images: [String: Data] = [:]
        var totalImageBytes = 0
        for image in archive.images {
            guard Self.isAllowedImagePath(image.path),
                  images[image.path] == nil,
                  LocalImageStore.sha256(image.data) == image.hash else {
                throw LocalCompleteBackupError.invalidImage(image.path)
            }
            totalImageBytes += image.data.count
            guard totalImageBytes <= Self.maximumImageBytes else { throw LocalCompleteBackupError.archiveTooLarge }
            images[image.path] = image.data
        }
        try Self.validateImageReferences(rows: rows, images: archive.images, schemaVersion: archive.schemaVersion)
        return DecodedArchive(archive: archive, rows: rows, imageData: images)
    }

    private static func validateFinancialRows(_ rows: [String: [[String: Any]]]) throws {
        let accounts = Set((rows["local_accounts"] ?? []).compactMap { $0["id"] as? String })
        let records = Set((rows["local_records"] ?? []).compactMap { $0["id"] as? String })
        let cycles = Set((rows["local_repayment_cycles"] ?? []).compactMap { $0["id"] as? String })

        let amounts: [String: [(String, Bool)]] = [
            "local_accounts": [("opening_balance_minor", false)],
            "local_expenses": [("amount_minor", true)],
            "local_income_records": [("amount_minor", true)],
            "local_repayment_cycles": [
                ("statement_amount_minor", false), ("paid_amount_minor", false),
                ("remaining_amount_minor", false), ("carried_over_amount_minor", false),
                ("original_statement_amount_minor", false), ("min_payment_amount_minor", false),
                ("refund_applied_amount_minor", false)
            ],
            "local_liability_payments": [("amount_minor", true), ("overpayment_amount_minor", false)],
            "local_account_entries": [("amount_minor", true)],
            "local_wallet_snapshots": [("snapshot_balance_minor", false)]
        ]
        for (table, fields) in amounts {
            for row in rows[table] ?? [] {
                for (field, mustBePositive) in fields {
                    if row[field] is NSNull, !mustBePositive { continue }
                    guard let number = row[field] as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID(),
                          let value = Int64(number.stringValue),
                          mustBePositive ? value > 0 : value >= 0 else {
                        throw LocalCompleteBackupError.invalidRows(table)
                    }
                }
            }
        }

        let references: [(String, String, Set<String>, Bool)] = [
            ("local_accounts", "auto_debit_account_id", accounts, true),
            ("local_expenses", "account_id", accounts, false),
            ("local_income_records", "account_id", accounts, true),
            ("local_repayment_cycles", "account_id", accounts, false),
            ("local_repayment_cycles", "auto_debit_account_id", accounts, true),
            ("local_repayment_cycles", "evidence_record_id", records, true),
            ("local_liability_payments", "account_id", accounts, false),
            ("local_liability_payments", "statement_id", cycles, true),
            ("local_liability_payments", "debit_account_id", accounts, true),
            ("local_liability_payments", "evidence_record_id", records, true),
            ("local_account_entries", "account_id", accounts, false),
            ("local_wallet_snapshots", "linked_account_id", accounts, true)
        ]
        for (table, field, validIDs, optional) in references {
            for row in rows[table] ?? [] {
                if optional && (row[field] == nil || row[field] is NSNull) { continue }
                guard let value = row[field] as? String, validIDs.contains(value) else {
                    throw LocalCompleteBackupError.invalidRows(table)
                }
            }
        }
        for row in rows["local_wallet_snapshots"] ?? [] {
            let linkedAccountID = row["linked_account_id"] as? String
            let linkedAction = row["linked_action"] as? String
            if linkedAccountID == nil {
                guard linkedAction == nil else { throw LocalCompleteBackupError.invalidRows("local_wallet_snapshots") }
            } else {
                guard let linkedAction, ["create", "link"].contains(linkedAction) else {
                    throw LocalCompleteBackupError.invalidRows("local_wallet_snapshots")
                }
            }
        }
    }

    private static func columns(in db: Database, table: String) throws -> [String] {
        try Row.fetchAll(db, sql: "PRAGMA table_info(\(quote(table)))")
            .compactMap { row -> String? in
                let name: String = row["name"]
                return ["operation_id", "cloud_user_id", "sync_enabled"].contains(name) ? nil : name
            }
    }

    private static func validateImageReferences(
        rows: [String: [[String: Any]]],
        images: [ImageFile],
        schemaVersion: Int
    ) throws {
        let imageHashes = Dictionary(uniqueKeysWithValues: images.map { ($0.path, $0.hash) })
        for (table, statusField, activeStatuses) in [
            ("local_records", "deleted_at", Set(["active"])),
            ("local_staging_records", "status", Set(["pending_review", "failed"])),
            ("local_image_intakes", "status", Set(["receiving", "failed"])),
            ("local_wallet_snapshots", "deleted_at", Set<String>())
        ] {
            for row in rows[table] ?? [] {
                let active: Bool
                if table == "local_wallet_snapshots" {
                    active = schemaVersion >= 18 || (row["deleted_at"] is NSNull)
                } else if statusField == "deleted_at" {
                    active = row[statusField] is NSNull
                } else {
                    active = activeStatuses.contains(row[statusField] as? String ?? "")
                }
                guard active, let path = row["image_path"] as? String else { continue }
                guard let hash = row["image_hash"] as? String, imageHashes[path] == hash else {
                    throw LocalCompleteBackupError.missingImage(path)
                }
            }
        }
    }

    private static func normalizeInterruptedIntake(_ row: inout [String: Any]) {
        guard row["status"] as? String == "receiving" else { return }
        row["status"] = "failed"
        row["failure_message"] = "备份导入时识别尚未结束，可手动处理或重试"
    }

    private static func mappedID(table: String, row: [String: Any], targetProfileID: UUID) throws -> String {
        guard table == "local_image_intakes" else {
            guard let id = row["id"] as? String else { throw LocalCompleteBackupError.invalidRows(table) }
            return id
        }
        guard let hash = row["image_hash"] as? String else { throw LocalCompleteBackupError.invalidRows(table) }
        return "\(targetProfileID.uuidString)-\(hash)"
    }

    private static func dictionary(from row: [String: Any]) throws -> [String: Any] {
        var copy = row
        copy.removeValue(forKey: "operation_id")
        guard JSONSerialization.isValidJSONObject(copy) else { throw LocalCompleteBackupError.invalidFormat }
        return copy
    }

    private static func canonicalJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        guard let string = String(data: data, encoding: .utf8) else { throw LocalCompleteBackupError.invalidFormat }
        return string
    }

    private static func isAllowedImagePath(_ path: String) -> Bool {
        ["records/", "staging/", "intake/"].contains(where: { path.hasPrefix($0) })
            && !path.hasPrefix("/") && !path.contains("..")
    }

    private static func isLegacyExpenseArchive(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["format"] as? String == LocalExpenseArchive.currentFormat
    }

    private static func quote(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private struct Archive: Codable {
        static let formatName = "jiezi-local-complete-backup"
        let format: String
        let schemaVersion: Int
        let exportedAt: String
        let profileID: String
        let tables: [String: String]
        let images: [ImageFile]
    }

    private struct ImageFile: Codable {
        let path: String
        let hash: String
        let data: Data
    }

    private struct DecodedArchive {
        let archive: Archive
        let rows: [String: [[String: Any]]]
        let imageData: [String: Data]
    }
}
