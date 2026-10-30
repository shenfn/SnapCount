import Foundation
import GRDB

enum LocalHistoryMappingError: Error, LocalizedError {
    case unsupported(String)
    case sourceFieldMissing(table: String, field: String, recordID: String)
    case sourceFieldInvalid(table: String, field: String, recordID: String)
    /// 逐行收集到的全部不兼容项。一次报全，避免「修一条又冒一条」。
    case rows([String])

    var errorDescription: String? {
        switch self {
        case .unsupported(let reason): return reason
        case .rows(let issues):
            let samples = issues.prefix(10).map { "· \($0)" }.joined(separator: "\n")
            let remaining = issues.count - min(issues.count, 10)
            return "历史数据有 \(issues.count) 项无法等价转换，本次未入账：\n\(samples)"
                + (remaining > 0 ? "\n另有 \(remaining) 项。" : "")
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
        // 行级不兼容只记录、不中断：跑完全部行后一次性抛出，用户不必「修一条重启一次」。
        var issues: [String] = []
        let walletIDs = Set(inspection.rows[.records, default: []].filter { ($0["domain_key"]?.value as? String) == "wallet" }.compactMap { ($0["id"]?.value as? String)?.lowercased() })
        if let blocker = LocalHistoryMigrationUseCase.blockers(inspection.rows).first {
            throw LocalHistoryMappingError.unsupported(blocker)
        }
        try reconcile(inspection)
        for source in LocalHistorySourceTable.allCases {
            // Keep the decoded values as-is. Re-encoding through JSONEncoder and
            // JSONSerialization would turn every number into an NSNumber, whose
            // decimal text is not the shortest round-trip form and cannot be
            // reconciled as money.
            let rows = inspection.rows[source, default: []].map { $0.mapValues(\.value) }
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
                        mapped[target] = try LocalHistorySourceCompatibility.minorValue(value)
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
                    guard (row["type"] as? String) == "expense" else {
                        throw LocalHistoryMappingError.unsupported(
                            Self.blocked("transactions", "type", "类型不是消费，需核对收入转换关系", id: id))
                    }
                    let pending = (row["status"] as? String) == "pending"
                    table = pending ? "local_pending_transactions" : "local_expenses"
                    guard pending || (row["status"] as? String) == "done" else { throw LocalDataError.invalidRecord }
                    for key in ["account_id", "merchant_name", "platform", "category", "payment_method", "transaction_date", "transaction_time", "note", "created_at", "updated_at", "occurred_at"] { copy(key) }
                    // 云端这几列允许为空，本机是 NOT NULL。空串表示「未填写」，展示层已有
                    // 「待补全消费」兜底；不编造商户名，也不把空值当迁移失败。
                    for key in ["merchant_name", "platform", "category", "payment_method"] {
                        mapped[key] = row[key] as? String ?? ""
                    }
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
                        mapped["snapshot_balance_minor"] = try LocalHistorySourceCompatibility.minorValue(balance)
                        for key in ["linked_account_id", "account_snapshot_kind"] {
                            if let value = LocalHistorySourceCompatibility.walletValue(row, field: key) { mapped[key] = value }
                        }
                        mapped["currency"] = payload["currency"] ?? "CNY"
                        if mapped["linked_account_id"] != nil { mapped["linked_action"] = "link" }
                    } else {
                        guard LocalRecordValidation.supportedDomainKeys.contains(domain) else {
                            throw LocalHistoryMappingError.unsupported(
                                Self.blocked("data_records", "domain_key", "域 \(domain) 尚无等价映射", id: id))
                        }
                        let version = row["domain_version"] as? String ?? "1.0"
                        guard ["1", "1.0"].contains(version) else {
                            throw LocalHistoryMappingError.unsupported(
                                Self.blocked("data_records", "domain_version", "版本 \(version) 尚无等价映射", id: id))
                        }
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
                        throw LocalHistoryMappingError.unsupported(
                            Self.blocked("staging_records", "status", "状态 \(status) 尚无等价映射", id: id))
                    }
                    // 与预检共用同一条可写判定：预检判定为「待核对」的候选在这里根本走不到，
                    // 这条守卫只在两处定义不一致时才会触发。
                    guard LocalHistoryMigrationUseCase.stagingDomainMappable(domain, status: status) else {
                        throw LocalHistoryMappingError.unsupported(
                            Self.blocked("staging_records", "detected_domain_key", "域 \(domain) 尚无等价映射", id: id))
                    }
                    let nested = payload["payload_jsonb"] as? [String: Any] ?? [:]
                    let recordDate = (payload["record_date"] as? String) ?? (nested["record_date"] as? String)
                    guard let recordDate, NativeLocalDate.monthKey(from: recordDate) != nil else {
                        throw LocalHistoryMappingError.unsupported(
                            Self.blocked("staging_records", "extracted_json.record_date", "缺少有效业务日期", id: id))
                    }
                    if localStatus == "archived", row["target_record_id"] as? String == nil {
                        throw LocalHistoryMappingError.unsupported(
                            Self.blocked("staging_records", "target_record_id", "已归档候选缺少可核对的目标", id: id))
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
                // 本机主键与外键统一是大写 UUID（UUID.uuidString），云端给的是小写文本。
                // 只把主键转大写会让外键对不上账户行：记录在界面上会找不到所属账户，
                // 与本机已有同一条记录比较时也会因为大小写不同被判成内容不同。
                if table != "local_history_unresolved_records" {
                    for key in ["account_id", "source_id", "evidence_record_id", "evidence_wallet_snapshot_id",
                                "linked_account_id", "statement_id", "debit_account_id", "target_record_id"] {
                        if let value = mapped[key] as? String, UUID(uuidString: value) != nil {
                            mapped[key] = value.uppercased()
                        }
                    }
                }
                if mapped["updated_at"] == nil { mapped["updated_at"] = mapped["created_at"] }
                let completed = try normalized(mapped, table: table)
                tables[table, default: []].append(completed)
                } catch let error as LocalHistoryMigrationError {
                    // 归属/范围不一致是致命错误，必须立即停止，不能继续读其他行。
                    throw error
                } catch {
                    issues.append(Self.issueText(source: source, row: row, error: error))
                }
            }
        }
        guard issues.isEmpty else { throw LocalHistoryMappingError.rows(issues) }
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
                else {
                    // 本机必填列没有源值：固定给出「本机表.列 + 记录 #hash」，
                    // 否则问题清单只能归到「其他」，用户和我们都看不到是哪一列。
                    throw LocalHistoryMappingError.unsupported(
                        "\(table).\(name) 缺少可确认的源字段，记录 #\(Self.recordHint(values["id"] as? String ?? ""))。")
                }
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
            do { balance = try LocalHistorySourceCompatibility.minorValue(opening.value) }
            catch { throw LocalHistoryMigrationContextError(table: "accounts", field: "initial_balance", recordID: id, underlying: error) }
            for entry in inspection.rows[.accountEntries, default: []] where (entry["account_id"]?.value as? String)?.lowercased() == id.lowercased() {
                if (entry["is_voided"]?.value as? Bool) == true || (entry["entry_type"]?.value as? String) == "snapshot_initialization" { continue }
                let entryID = entry["id"]?.value as? String ?? ""
                guard let amount = entry["amount"], let direction = entry["direction"]?.value as? String, ["in", "out"].contains(direction) else {
                    throw LocalHistoryMigrationContextError(table: "account_entries", field: "amount/direction", recordID: entryID, underlying: LocalDataError.invalidRecord)
                }
                let delta: Int64
                do { delta = try LocalHistorySourceCompatibility.minorValue(amount.value) }
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
            do { currentBalance = try LocalHistorySourceCompatibility.minorValue(current.value) }
            catch { throw LocalHistoryMigrationContextError(table: "accounts", field: "current_balance", recordID: id, underlying: error) }
            guard balance == currentBalance else {
                throw LocalHistoryMigrationContextError(table: "accounts", field: "current_balance", recordID: id,
                    underlying: LocalHistoryMigrationValidationError.accountBalanceMismatch)
            }
        }
    }
    private static func day(_ value: String) throws -> String {
        let date = String(value.prefix(10))
        guard NativeLocalDate.monthKey(from: date) != nil else { throw LocalDataError.invalidRecord }
        guard let parsed = parseDate(value) else { throw LocalDataError.invalidRecord }
        return NativeLocalDate.dateKey(parsed)
    }

    private static func parseDate(_ value: String) -> Date? {
        // 与导入校验共用同一份解析（含微秒截断），否则会出现「映射能建、校验拒收」。
        LocalHistorySourceCompatibility.parseTimestamp(value)
    }

    private static func recordHint(_ id: String) -> String {
        String(LocalImageStore.sha256(Data(id.lowercased().utf8)).prefix(10))
    }

    /// 行级阻塞文案的固定形状：`源表.字段 说明，记录 #hash。`
    /// 问题清单靠「表.字段」归类、靠 `#hash` 统计涉及记录；缺任一项就只能归到「其他」并且不显示原文。
    private static func blocked(_ table: String, _ field: String, _ detail: String, id: String) -> String {
        "\(table).\(field) \(detail)，记录 #\(recordHint(id))。"
    }

    /// 把行级错误压成一句可读、可核对、不含原始业务内容的问题描述。
    private static func issueText(source: LocalHistorySourceTable, row: [String: Any], error: Error) -> String {
        let rowID = row["id"] as? String ?? ""
        if let error = error as? LocalHistoryMappingError { return error.localizedDescription }
        if let context = error as? LocalHistoryMigrationContextError {
            if let inner = context.underlying as? LocalHistoryMappingError { return inner.localizedDescription }
            let field = context.field.map { ".\($0)" } ?? ""
            return "\(context.table)\(field) 无法等价映射，记录 #\(recordHint(context.recordID.isEmpty ? rowID : context.recordID))；尚未入账。"
        }
        return "\(source.rawValue) 记录 #\(recordHint(rowID)) 不符合本机事实合同；尚未入账。"
    }
}
