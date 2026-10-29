import Foundation
import CoreFoundation
import GRDB

enum LocalHistoryMappingError: Error, LocalizedError {
    case unsupported(String)
    case sourceFieldMissing(table: String, field: String, recordID: String)
    case sourceFieldInvalid(table: String, field: String, recordID: String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let reason): return reason
        case .sourceFieldMissing(let table, let field, let recordID):
            let hint = String(LocalImageStore.sha256(Data(recordID.lowercased().utf8)).prefix(10))
            return "\(table).\(field) 缺少可确认的历史值，记录 #\(hint)；未使用创建时间代替，尚未入账。"
        case .sourceFieldInvalid(let table, let field, let recordID):
            let hint = String(LocalImageStore.sha256(Data(recordID.lowercased().utf8)).prefix(10))
            return "\(table).\(field) 不是可确认的历史值，记录 #\(hint)；尚未入账。"
        }
    }
}

/// Produces a recovery archive, never writes into the user's database.
final class LocalHistoryMigrationMapper {
    private let schema: LocalDatabase
    init(schema: LocalDatabase) { self.schema = schema }

    func buildArchive(_ inspection: LocalHistoryMigrationInspection, profileID: UUID, images: [String: Data], at now: Date = Date()) throws -> Data {
        var tables: [String: [[String: Any]]] = [:]
        var imageFiles: [String: [String: Any]] = [:]
        let walletIDs = Set(inspection.rows[.records, default: []].filter { ($0["domain_key"]?.value as? String) == "wallet" }.compactMap { ($0["id"]?.value as? String)?.lowercased() })
        if let blocker = LocalHistoryMigrationUseCase.blockers(inspection.rows).first {
            throw LocalHistoryMappingError.unsupported(blocker)
        }
        try reconcile(inspection)
        for source in LocalHistorySourceTable.allCases {
            let raw = try JSONEncoder().encode(inspection.rows[source, default: []])
            guard let rows = try JSONSerialization.jsonObject(with: raw) as? [[String: Any]] else { throw LocalDataError.invalidRecord }
            for row in rows {
                do {
                let id = try text(row, "id")
                guard UUID(uuidString: id) != nil else { throw LocalDataError.invalidIdentifier }
                guard let owner = row["user_id"] as? String,
                      UUID(uuidString: owner) == UUID(uuidString: inspection.cloudUserID) else { throw LocalHistoryMigrationError.identityMismatch }
                var table: String
                var mapped: [String: Any] = ["id": id.uppercased(), "profile_id": profileID.uuidString]
                func copy(_ source: String, _ target: String? = nil) { if let value = row[source], !(value is NSNull) { mapped[target ?? source] = value } }
                func minor(_ sourceField: String, _ target: String) throws {
                    guard let value = row[sourceField], !(value is NSNull) else { return }
                    do {
                        mapped[target] = try Self.minor(value)
                    } catch {
                        throw LocalHistoryMigrationContextError(
                            table: source.rawValue,
                            field: sourceField,
                            recordID: id,
                            underlying: error
                        )
                    }
                }
                copy("deleted_at")
                let preservationIssues = LocalHistoryMigrationUseCase.preservationIssues(
                    table: source, row: row.mapValues(AnyCodable.init), rows: inspection.rows)
                if !preservationIssues.isEmpty {
                    table = "local_history_unresolved_records"
                    mapped["id"] = source.rawValue + "/" + id.lowercased()
                    mapped["source_table"] = source.rawValue
                    mapped["source_id"] = id
                    mapped["source_json"] = String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self)
                    mapped["issues_json"] = String(decoding: try JSONSerialization.data(withJSONObject: preservationIssues, options: [.sortedKeys]), as: UTF8.self)
                    copy("created_at"); copy("updated_at")
                } else {
                switch source {
                case .accounts:
                    table = "local_accounts"
                    for key in ["name", "currency", "institution", "last4", "bill_day", "payment_due_day", "auto_debit_account_id", "auto_confirm_repayment", "grace_period_days", "is_default_expense", "is_default_income", "is_archived", "last_reconciled_at", "created_at", "updated_at"] { copy(key) }
                    copy("type", "kind"); try minor("initial_balance", "opening_balance_minor"); mapped["origin"] = "remote"
                case .transactions:
                    guard (row["type"] as? String) == "expense" else { throw LocalHistoryMappingError.unsupported("交易 \(id) 类型不是消费，需核对收入转换关系") }
                    let pending = (row["status"] as? String) == "pending"
                    table = pending ? "local_pending_transactions" : "local_expenses"
                    guard pending || (row["status"] as? String) == "done" else { throw LocalDataError.invalidRecord }
                    for key in ["account_id", "merchant_name", "platform", "category", "payment_method", "transaction_date", "transaction_time", "note", "created_at", "updated_at", "occurred_at"] { copy(key) }
                    mapped["currency"] = row["currency"] ?? "CNY"
                    try minor("amount", "amount_minor")
                    if pending { mapped["status"] = "pending" }
                case .incomes:
                    table = "local_income_records"
                    for key in ["account_id", "source_name", "category", "income_date", "occurred_at", "note", "created_at", "updated_at", "source_pending_transaction_id"] { copy(key) }
                    mapped["currency"] = row["currency"] ?? "CNY"; try minor("amount", "amount_minor")
                case .accountEntries:
                    table = "local_account_entries"
                    for key in ["account_id", "direction", "occurred_at"] { copy(key) }
                    copy("entry_type", "entry_kind"); try minor("amount", "amount_minor")
                    let sourceTable = row["source_table"] as? String
                    let kinds = ["transactions": "expense", "income_records": "income", "liability_payments": "liability_payment", "data_records": "wallet_snapshot", "account_repayment_cycles": "repayment_cycle"]
                    mapped["source_kind"] = sourceTable.flatMap { kinds[$0] } ?? "historical_entry"
                    if sourceTable.flatMap({ kinds[$0] }) != nil {
                        mapped["source_id"] = try text(row, "source_id")
                    } else { mapped["source_id"] = id }
                    mapped["is_voided"] = (row["is_voided"] as? Bool) == true ? 1 : 0
                    mapped["source_metadata_json"] = String(decoding: try JSONSerialization.data(withJSONObject: [
                        "source_table": row["source_table"] ?? NSNull(), "source_id": row["source_id"] ?? NSNull()
                    ], options: [.sortedKeys]), as: UTF8.self)
                case .repaymentCycles:
                    table = "local_repayment_cycles"
                    for key in ["account_id", "cycle_month", "statement_start_date", "statement_end_date", "due_date", "status", "auto_debit_account_id", "auto_confirm_repayment", "source", "evidence_record_id", "confidence", "note", "confirmed_at", "created_at", "updated_at"] { copy(key) }
                    for key in ["statement_amount", "paid_amount", "remaining_amount", "carried_over_amount", "original_statement_amount", "min_payment_amount", "refund_applied_amount"] { try minor(key, key + "_minor") }
                    if let evidence = mapped["evidence_record_id"] as? String, walletIDs.contains(evidence.lowercased()) {
                        mapped.removeValue(forKey: "evidence_record_id"); mapped["evidence_wallet_snapshot_id"] = evidence
                    }
                case .payments:
                    table = "local_liability_payments"
                    for key in ["account_id", "statement_id", "debit_account_id", "paid_at", "source", "evidence_record_id", "status", "note", "created_at", "updated_at"] { copy(key) }
                    try minor("amount", "amount_minor"); try minor("overpayment_amount", "overpayment_amount_minor")
                    if let evidence = mapped["evidence_record_id"] as? String, walletIDs.contains(evidence.lowercased()) {
                        mapped.removeValue(forKey: "evidence_record_id")
                        mapped["evidence_wallet_snapshot_id"] = evidence
                    }
                case .records:
                    let domain = try text(row, "domain_key")
                    table = domain == "wallet" ? "local_wallet_snapshots" : "local_records"
                    let payload = row["payload_jsonb"] as? [String: Any] ?? [:]
                    mapped["payload_json"] = String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
                    mapped["domain_key"] = domain
                    for key in ["title", "summary", "occurred_at", "created_at", "updated_at", "linked_account_id", "account_snapshot_kind"] { copy(key) }
                    mapped["title"] = row["title"] as? String ?? "历史记录"
                    mapped["summary"] = row["summary"] as? String ?? ""
                    guard let occurredAt = row["occurred_at"] as? String, !occurredAt.isEmpty else {
                        throw LocalHistoryMappingError.sourceFieldMissing(table: "data_records", field: "occurred_at", recordID: id)
                    }
                    do {
                        mapped["record_date"] = try Self.day(occurredAt)
                    } catch {
                        throw LocalHistoryMappingError.sourceFieldInvalid(table: "data_records", field: "occurred_at", recordID: id)
                    }
                    if domain == "wallet" {
                        guard let balance = LocalHistorySourceCompatibility.walletValue(row, field: "snapshot_balance") else {
                            throw LocalHistoryMappingError.sourceFieldMissing(table: "data_records", field: "snapshot_balance", recordID: id)
                        }
                        mapped["snapshot_balance_minor"] = try Self.minor(balance)
                        for key in ["linked_account_id", "account_snapshot_kind"] {
                            if let value = LocalHistorySourceCompatibility.walletValue(row, field: key) { mapped[key] = value }
                        }
                        mapped["currency"] = payload["currency"] ?? "CNY"
                        if mapped["linked_account_id"] != nil { mapped["linked_action"] = "link" }
                    } else {
                        guard LocalRecordValidation.supportedDomainKeys.contains(domain) else { throw LocalHistoryMappingError.unsupported("不支持的域：\(domain)") }
                        let version = row["domain_version"] as? String ?? "1.0"
                        guard ["1", "1.0"].contains(version) else { throw LocalHistoryMappingError.unsupported("域版本 \(version) 需要显式迁移") }
                        mapped["domain_version"] = 1; mapped["source_kind"] = "imported"
                        let validated = try LocalRecordCodec.normalizedPayload(domainKey: domain,
                            payload: try JSONDecoder().decode([String: AnyCodable].self, from: JSONSerialization.data(withJSONObject: payload)))
                        mapped["payload_json"] = try LocalRecordCodec.encode(validated)
                    }
                case .staging:
                    table = "local_staging_records"
                    let payload = row["extracted_json"] as? [String: Any] ?? [:]
                    let domain = (row["resolved_domain_key"] as? String) ?? (row["detected_domain_key"] as? String) ?? ""
                    let status = try text(row, "status")
                    guard let localStatus = ["unassigned": "pending_review", "pending_review": "pending_review", "assigned": "archived", "confirmed": "archived", "archived": "archived", "discarded": "discarded", "failed": "failed"][status] else {
                        throw LocalHistoryMappingError.unsupported("候选 \(id) 的历史状态 \(status) 需要显式兼容")
                    }
                    guard LocalRecordValidation.supportedStagingDomainKeys.contains(domain)
                            || (localStatus == "archived" && domain == "expense") else { throw LocalHistoryMappingError.unsupported("候选 \(id) 域尚未支持：\(domain)") }
                    let nested = payload["payload_jsonb"] as? [String: Any] ?? [:]
                    let recordDate = (payload["record_date"] as? String) ?? (nested["record_date"] as? String)
                    guard let recordDate, NativeLocalDate.monthKey(from: recordDate) != nil else { throw LocalHistoryMappingError.unsupported("候选 \(id) 缺少真实业务日期") }
                    if localStatus == "archived", row["target_record_id"] as? String == nil {
                        throw LocalHistoryMappingError.unsupported("候选 \(id) 缺少可核对的归档目标")
                    }
                    mapped["domain_key"] = domain; mapped["status"] = localStatus; mapped["record_date"] = recordDate
                    mapped["payload_json"] = String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]), as: UTF8.self)
                    mapped["title"] = row["ai_summary"] as? String ?? "历史候选"
                    mapped["summary"] = row["ai_summary"] as? String ?? ""
                    for key in ["confidence", "created_at", "updated_at", "target_record_id", "resolved_action", "resolved_at"] { copy(key) }
                    mapped["source_kind"] = "imported"
                }
                }
                let imageReference = ["image_url", "source_image_path", "image_path"].compactMap { field -> (String, String)? in
                    guard let path = row[field] as? String, !path.isEmpty else { return nil }
                    return (field, path)
                }.first
                if let (_, imagePath) = imageReference {
                    if let bytes = images[imagePath] {
                        let hash = LocalImageStore.sha256(bytes)
                        let expectedHash = ["image_hash", "source_image_hash"].compactMap { field -> (String, String)? in
                            guard let value = row[field] as? String, !value.isEmpty else { return nil }
                            return (field, value)
                        }.first
                        if let (hashField, expectedValue) = expectedHash, expectedValue.lowercased() != hash {
                            throw LocalHistoryMigrationContextError(
                                table: source.rawValue,
                                field: hashField,
                                recordID: id,
                                underlying: LocalCompleteBackupError.invalidImage("history-image")
                            )
                        }
                        let path = "records/history-\(hash).jpg"
                        mapped["image_path"] = path; mapped["image_hash"] = hash
                        imageFiles[path] = ["path": path, "hash": hash, "data": bytes.base64EncodedString()]
                    }
                }
                if mapped["updated_at"] == nil { mapped["updated_at"] = mapped["created_at"] }
                let completed = try normalized(mapped, table: table)
                tables[table, default: []].append(completed)
                } catch let error as LocalHistoryMappingError {
                    switch error {
                    case .sourceFieldMissing, .sourceFieldInvalid: throw error
                    case .unsupported:
                        throw LocalHistoryMigrationContextError(table: source.rawValue, field: nil, recordID: row["id"] as? String ?? "", underlying: error)
                    }
                } catch let error as LocalHistoryMigrationError {
                    throw error
                } catch let error as LocalHistoryMigrationContextError {
                    throw error
                } catch {
                    throw LocalHistoryMigrationContextError(table: source.rawValue, field: nil, recordID: row["id"] as? String ?? "", underlying: error)
                }
            }
        }
        let allTables = ["local_accounts", "local_wallet_snapshots", "local_records", "local_expenses", "local_income_records", "local_staging_records", "local_repayment_cycles", "local_liability_payments", "local_account_entries", "local_image_intakes", "local_pending_transactions", "local_history_unresolved_records"]
        var encoded: [String: String] = [:]
        for table in allTables {
            encoded[table] = String(decoding: try JSONSerialization.data(withJSONObject: tables[table, default: []], options: [.sortedKeys]), as: UTF8.self)
        }
        return try JSONSerialization.data(withJSONObject: ["format": "jiezi-local-complete-backup", "schemaVersion": LocalCompleteBackupPortability.currentSchemaVersion, "exportedAt": ISO8601DateFormatter().string(from: now), "profileID": profileID.uuidString, "tables": encoded, "images": Array(imageFiles.values)], options: [.sortedKeys])
    }

    private func normalized(_ values: [String: Any], table: String) throws -> [String: Any] {
        try schema.writer.read { db in
            var output: [String: Any] = [:]
            for column in try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))") {
                let name: String = column["name"]
                if ["operation_id", "cloud_user_id", "sync_enabled"].contains(name) { continue }
                if let value = values[name] {
                    if let string = value as? String, let uuid = UUID(uuidString: string) { output[name] = uuid.uuidString }
                    else if name.hasSuffix("_at"), let string = value as? String {
                        guard let date = Self.parseDate(string) else {
                            throw LocalHistoryMigrationContextError(
                                table: table, field: name, recordID: values["id"] as? String ?? "",
                                underlying: LocalDataError.invalidRecord
                            )
                        }
                        let sql = DateFormatter(); sql.locale = Locale(identifier: "en_US_POSIX"); sql.timeZone = TimeZone(secondsFromGMT: 0); sql.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
                        output[name] = sql.string(from: date)
                    } else { output[name] = value }
                    continue
                }
                if let defaultSQL: String = column["dflt_value"] {
                    let json = try String.fetchOne(db, sql: "SELECT json_quote(\(defaultSQL))") ?? "null"
                    output[name] = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])
                } else if (column["notnull"] as Int) == 0 { output[name] = NSNull() }
                else { throw LocalHistoryMappingError.unsupported("\(table).\(name) 缺少可确认的源字段") }
            }
            return output
        }
    }

    private func text(_ row: [String: Any], _ key: String) throws -> String {
        guard let value = row[key] as? String, !value.isEmpty else { throw LocalDataError.invalidRecord }; return value
    }
    private func reconcile(_ inspection: LocalHistoryMigrationInspection) throws {
        for account in inspection.rows[.accounts, default: []] {
            let id = account["id"]?.value as? String ?? ""
            guard !id.isEmpty else {
                throw LocalHistoryMigrationContextError(table: "accounts", field: "id", recordID: "", underlying: LocalDataError.invalidIdentifier)
            }
            guard let opening = account["initial_balance"], !(opening.value is NSNull) else {
                throw LocalHistoryMigrationContextError(table: "accounts", field: "initial_balance", recordID: id, underlying: LocalDataError.invalidRecord)
            }
            guard let current = account["current_balance"], !(current.value is NSNull) else {
                throw LocalHistoryMigrationContextError(table: "accounts", field: "current_balance", recordID: id, underlying: LocalDataError.invalidRecord)
            }
            var balance: Int64
            do { balance = try Self.minor(opening.value) }
            catch { throw LocalHistoryMigrationContextError(table: "accounts", field: "initial_balance", recordID: id, underlying: error) }
            for entry in inspection.rows[.accountEntries, default: []] where (entry["account_id"]?.value as? String)?.lowercased() == id.lowercased() {
                if (entry["is_voided"]?.value as? Bool) == true || (entry["entry_type"]?.value as? String) == "snapshot_initialization" { continue }
                let entryID = entry["id"]?.value as? String ?? ""
                guard let amount = entry["amount"], let direction = entry["direction"]?.value as? String, ["in", "out"].contains(direction) else {
                    throw LocalHistoryMigrationContextError(table: "account_entries", field: "amount/direction", recordID: entryID, underlying: LocalDataError.invalidRecord)
                }
                let delta: Int64
                do { delta = try Self.minor(amount.value) }
                catch { throw LocalHistoryMigrationContextError(table: "account_entries", field: "amount", recordID: entryID, underlying: error) }
                guard delta > 0 else {
                    throw LocalHistoryMigrationContextError(table: "account_entries", field: "amount", recordID: entryID, underlying: LocalDataError.invalidAmount)
                }
                let sum = balance.addingReportingOverflow(direction == "in" ? delta : -delta)
                guard !sum.overflow else {
                    throw LocalHistoryMigrationContextError(table: "account_entries", field: "amount", recordID: entryID, underlying: LocalDataError.invalidAmount)
                }
                balance = sum.partialValue
            }
            let currentBalance: Int64
            do { currentBalance = try Self.minor(current.value) }
            catch { throw LocalHistoryMigrationContextError(table: "accounts", field: "current_balance", recordID: id, underlying: error) }
            guard balance == currentBalance else {
                throw LocalHistoryMigrationContextError(table: "accounts", field: "current_balance", recordID: id,
                    underlying: LocalHistoryMigrationValidationError.accountBalanceMismatch)
            }
        }
    }
    private static func minor(_ value: Any) throws -> Int64 {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            throw LocalDataError.invalidRecord
        }
        guard let decimal = Decimal(string: String(describing: value), locale: Locale(identifier: "en_US_POSIX")) else { throw LocalDataError.invalidRecord }
        let number = NSDecimalNumber(decimal: decimal * 100)
        let result = number.int64Value
        guard number == NSDecimalNumber(value: result) else { throw LocalDataError.invalidRecord }
        return result
    }
    private static func day(_ value: String) throws -> String {
        let date = String(value.prefix(10))
        guard NativeLocalDate.monthKey(from: date) != nil else { throw LocalDataError.invalidRecord }
        guard let parsed = parseDate(value) else { throw LocalDataError.invalidRecord }
        return NativeLocalDate.dateKey(parsed)
    }

    private static func parseDate(_ value: String) -> Date? {
        let normalized = normalizeISO8601(value)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let normalized, let date = fractional.date(from: normalized) { return date }
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let normalized, let date = standard.date(from: normalized) { return date }
        if let date = standard.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX",
            "yyyy-MM-dd HH:mm:ssXXXXX"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }

    private static func normalizeISO8601(_ value: String) -> String? {
        var text = value.replacingOccurrences(of: " ", with: "T")
        guard let dot = text.firstIndex(of: ".") else { return text }
        let fractionStart = text.index(after: dot)
        guard let zone = text[fractionStart...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) else { return nil }
        let fraction = text[fractionStart..<zone]
        guard !fraction.isEmpty, fraction.allSatisfy({ $0.isNumber }) else { return nil }
        let milliseconds = String(fraction.prefix(3))
        text = String(text[..<dot]) + "." + milliseconds + String(text[zone...])
        return text
    }

    private static func recordHint(_ id: String) -> String {
        String(LocalImageStore.sha256(Data(id.lowercased().utf8)).prefix(10))
    }
}
