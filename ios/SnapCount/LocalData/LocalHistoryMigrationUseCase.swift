import Foundation

struct LocalHistoryMigrationImageReference: Hashable {
    let path: String
    let table: String
    let field: String
    let recordID: String

    fileprivate init(path: String, table: String, field: String, recordID: String) {
        self.path = path
        self.table = table
        self.field = field
        self.recordID = recordID
    }
}

struct LocalHistoryMigrationInspection {
    let cloudUserID: String
    let rows: [LocalHistorySourceTable: [[String: AnyCodable]]]
    let blockers: [String]
    var counts: [String: Int] { Dictionary(uniqueKeysWithValues: rows.map { ($0.key.rawValue, $0.value.count) }) }
    var sourceImagePaths: Set<String> {
        guard let cloudOwnerID = UUID(uuidString: cloudUserID) else { return [] }
        return Set(LocalHistorySourceTable.allCases.flatMap { table in
            rows[table, default: []].compactMap { row in
                guard let owner = row["user_id"]?.value as? String,
                      UUID(uuidString: owner) == cloudOwnerID,
                      let id = row["id"]?.value as? String, UUID(uuidString: id) != nil,
                      let image = Self.selectedImageReference(in: row) else { return nil }
                return image.path
            }
        })
    }
    func imageReference(for path: String) -> LocalHistoryMigrationImageReference? {
        guard let ownerID = UUID(uuidString: cloudUserID) else { return nil }
        for table in LocalHistorySourceTable.allCases {
            for row in rows[table, default: []] {
                guard let owner = row["user_id"]?.value as? String, UUID(uuidString: owner) == ownerID,
                      let recordID = row["id"]?.value as? String, UUID(uuidString: recordID) != nil,
                      let image = Self.selectedImageReference(in: row), image.path == path else { continue }
                return LocalHistoryMigrationImageReference(path: path, table: table.rawValue,
                    field: image.field, recordID: recordID)
            }
        }
        return nil
    }
    func authorizesImage(_ reference: LocalHistoryMigrationImageReference, cloudUserID: String) -> Bool {
        guard blockers.isEmpty,
              UUID(uuidString: cloudUserID) == UUID(uuidString: self.cloudUserID),
              let sourceReference = imageReference(for: reference.path) else { return false }
        return sourceReference == reference
    }
    func expectedImageHashes(for path: String) -> Set<String> {
        guard let ownerID = UUID(uuidString: cloudUserID) else { return [] }
        var hashes = Set<String>()
        for table in LocalHistorySourceTable.allCases {
            for row in rows[table, default: []] {
                guard let owner = row["user_id"]?.value as? String, UUID(uuidString: owner) == ownerID,
                      let recordID = row["id"]?.value as? String, UUID(uuidString: recordID) != nil,
                      let image = Self.selectedImageReference(in: row), image.path == path,
                      let hash = ["image_hash", "source_image_hash"].compactMap({ row[$0]?.value as? String })
                          .first(where: { !$0.isEmpty }) else { continue }
                hashes.insert(hash.lowercased())
            }
        }
        return hashes
    }
    func expectedImageHash(for path: String) throws -> String? {
        let hashes = expectedImageHashes(for: path)
        guard hashes.count <= 1 else { throw LocalHistoryImageDownloadError.hashMismatch }
        return hashes.first
    }
    private static func selectedImageReference(in row: [String: AnyCodable]) -> (field: String, path: String)? {
        ["image_url", "source_image_path", "image_path"].compactMap { field in
            guard let path = row[field]?.value as? String, !path.isEmpty else { return nil }
            return (field, path)
        }.first
    }
    var summary: String {
        let detail = LocalHistorySourceTable.allCases.map { "\($0.rawValue)：\(rows[$0, default: []].count)" }.joined(separator: "、")
        guard !blockers.isEmpty else { return "源数据预检：\(detail)。已读取源数据；尚未入账。" }
        let samples = blockers.prefix(5).joined(separator: "；")
        let remaining = blockers.count - min(blockers.count, 5)
        let suffix = remaining > 0 ? "；另有 \(remaining) 项，请展开问题列表查看" : ""
        return "源数据预检：\(detail)。有 \(blockers.count) 项待核对，尚未入账：\(samples)\(suffix)"
    }
}

/// Does not bind sync or write facts. A preview cannot mark the checkpoint completed.
final class LocalHistoryMigrationUseCase {
    private let source: LocalHistoryMigrationSource
    init(source: LocalHistoryMigrationSource = LocalHistoryMigrationSource()) { self.source = source }

    func inspect(
        cloudUserID: String,
        accessToken: String,
        isCurrent: () -> Bool,
        onProgress: (@MainActor (LocalHistoryInventoryProgress) -> Void)? = nil
    ) async throws -> LocalHistoryMigrationInspection {
        var rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [:]
        var completedTables = Set<LocalHistorySourceTable>()
        var totalRowsRead = 0
        var pagesRead = 0
        for table in LocalHistorySourceTable.allCases {
            var cursor: String?
            var tableRowsRead = 0
            repeat {
                guard !Task.isCancelled else { throw CancellationError() }
                guard isCurrent() else { throw LocalHistoryMigrationError.staleAttempt }
                await onProgress?(LocalHistoryInventoryProgress(
                    currentTable: table, currentTableRowsRead: tableRowsRead, totalRowsRead: totalRowsRead,
                    pagesRead: pagesRead, completedTables: completedTables,
                    counts: LocalHistoryInventoryCatalog.cloudCounts(rows)
                ))
                let page: LocalHistorySourcePage
                do {
                    page = try await source.page(table: table, cloudUserID: cloudUserID, afterID: cursor, accessToken: accessToken)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LocalHistoryMigrationContextError {
                    throw error
                } catch {
                    throw LocalHistoryMigrationContextError(table: table.rawValue, field: nil, recordID: "", underlying: error)
                }
                guard !Task.isCancelled else { throw CancellationError() }
                guard isCurrent() else { throw LocalHistoryMigrationError.staleAttempt }
                rows[table, default: []].append(contentsOf: page.rows)
                tableRowsRead += page.rows.count
                totalRowsRead += page.rows.count
                pagesRead += 1
                guard rows.values.reduce(0, { $0 + $1.count }) <= 100_000 else { throw LocalCompleteBackupError.archiveTooLarge }
                cursor = page.nextCursor
                if cursor == nil { completedTables.insert(table) }
                await onProgress?(LocalHistoryInventoryProgress(
                    currentTable: cursor == nil ? nil : table,
                    currentTableRowsRead: cursor == nil ? 0 : tableRowsRead,
                    totalRowsRead: totalRowsRead,
                    pagesRead: pagesRead,
                    completedTables: completedTables,
                    counts: LocalHistoryInventoryCatalog.cloudCounts(rows)
                ))
            } while cursor != nil
        }
        return LocalHistoryMigrationInspection(cloudUserID: cloudUserID, rows: rows, blockers: Self.blockers(rows))
    }

    static func blockers(_ rows: [LocalHistorySourceTable: [[String: AnyCodable]]]) -> [String] {
        var result = mappingIssues(rows).filter { $0.hasPrefix("transactions.") }
        let preservedRecordIDs = Set(rows[.records, default: []].filter {
            !preservationIssues(table: .records, row: $0, rows: rows).isEmpty
        }.compactMap { ($0["id"]?.value as? String)?.lowercased() })
        for table in [LocalHistorySourceTable.records, .staging] {
            for row in rows[table, default: []] where !preservationIssues(table: table, row: row, rows: rows).isEmpty {
                let hint = recordHint(row["id"]?.value as? String ?? "")
                guard let created = row["created_at"]?.value as? String, isValidOccurredAt(created) else {
                    result.append("\(table.rawValue).created_at 缺少可确认的源记录时间，记录 #\(hint)；不能完成原文保留。")
                    continue
                }
                if let updated = row["updated_at"]?.value as? String, isValidOccurredAt(updated) {
                    // Raw evidence retains both source timestamps without substitution.
                } else {
                    result.append("\(table.rawValue).updated_at 缺少有效源记录时间，记录 #\(hint)。")
                }
            }
        }
        for entry in rows[.accountEntries, default: []] {
            if entry["source_table"]?.value as? String == "data_records",
               let sourceID = entry["source_id"]?.value as? String,
               preservedRecordIDs.contains(sourceID.lowercased()) {
                result.append("data_records.financial_reference 待核对记录仍被账户流水引用，不能只保留原文后完成账务迁移，记录 #\(recordHint(sourceID))。")
            }
        }
        for table in [LocalHistorySourceTable.repaymentCycles, .payments] {
            for row in rows[table, default: []] {
                if let evidenceID = row["evidence_record_id"]?.value as? String,
                   preservedRecordIDs.contains(evidenceID.lowercased()) {
                    result.append("data_records.financial_reference 待核对记录仍被还款关系引用，记录 #\(recordHint(evidenceID))。")
                }
            }
        }
        return result
    }

    /// 候选能否原样落到本地候选表。预检（决定「原文保留」）与映射（决定是否抛错）必须共用这一份判定，
    /// 否则会出现「预检说没问题、映射说不行」的单行阻塞。
    static func stagingDomainMappable(_ domain: String, status: String) -> Bool {
        let archived = ["assigned", "confirmed", "archived"].contains(status)
        return LocalRecordValidation.supportedStagingDomainKeys.contains(domain)
            || (archived && domain == "expense")
    }

    static func preservationIssues(table: LocalHistorySourceTable, row: [String: AnyCodable],
                                   rows: [LocalHistorySourceTable: [[String: AnyCodable]]]) -> [String] {
        guard table == .records || table == .staging else { return [] }
        var result = mappingIssues([table: [row]])
        if table == .staging, let target = row["target_record_id"]?.value as? String {
            if !hasSourceTarget(target, row: row, rows: rows) {
                // 目标记录已在云端被删除。若继续写 target_record_id，整包会在最后一步
                // 因引用完整性被拒绝；这里按「历史待核对」保留原文，不影响其余记录入账。
                result.append("staging_records.target_record_id 指向的记录不在源数据中，候选按原文保留，记录 #\(recordHint(row["id"]?.value as? String ?? ""))。")
            }
            if rows[.records, default: []].contains(where: {
                ($0["id"]?.value as? String)?.lowercased() == target.lowercased()
                    && !mappingIssues([.records: [$0]]).isEmpty
            }) {
                result.append("staging_records.target_record_id 关联记录需要原文保留，候选一并保留，记录 #\(recordHint(row["id"]?.value as? String ?? ""))。")
            }
        }
        return result
    }

    /// 与本机导入的目标表判定保持一致：负债还款 → 周期，钱包 → 钱包快照，消费 → 交易，其余 → 记录。
    private static func hasSourceTarget(_ target: String, row: [String: AnyCodable],
                                        rows: [LocalHistorySourceTable: [[String: AnyCodable]]]) -> Bool {
        let domain = (row["resolved_domain_key"]?.value as? String)
            ?? (row["detected_domain_key"]?.value as? String) ?? ""
        let table: LocalHistorySourceTable
        let requiredDomain: String?
        if (row["resolved_action"]?.value as? String) == "liability_repayment_confirmed" {
            table = .repaymentCycles; requiredDomain = nil
        } else if domain == "wallet" {
            table = .records; requiredDomain = "wallet"
        } else if domain == "expense" {
            table = .transactions; requiredDomain = nil
        } else {
            table = .records; requiredDomain = nil
        }
        return rows[table, default: []].contains { candidate in
            guard (candidate["id"]?.value as? String)?.lowercased() == target.lowercased() else { return false }
            if let requiredDomain { return (candidate["domain_key"]?.value as? String) == requiredDomain }
            if domain == "expense" {
                // 待处理交易会落到 local_pending_transactions，不是消费目标。
                return (candidate["status"]?.value as? String) != "pending"
            }
            return true
        }
    }

    private static func mappingIssues(_ rows: [LocalHistorySourceTable: [[String: AnyCodable]]]) -> [String] {
        var result: [String] = []
        for row in rows[.records, default: []] {
            let id = row["id"]?.value as? String ?? ""
            let hint = recordHint(id)
            let domain = row["domain_key"]?.value as? String ?? ""
            if !Set(["food", "sleep", "sport", "reading", "wallet"]).contains(domain) {
                result.append("data_records.domain_key 缺失或超出当前本地支持范围，记录 #\(hint)；不会跳过或入账。")
                continue
            }
            guard let occurredAt = row["occurred_at"]?.value as? String,
                  Self.isValidOccurredAt(occurredAt) else {
                result.append("data_records.occurred_at 缺少可确认的真实日期，记录 #\(hint)；不会用 created_at 代替。")
                continue
            }
            guard domain == "wallet" else {
                let version = row["domain_version"]?.value as? String ?? "1.0"
                guard ["1", "1.0"].contains(version) else {
                    result.append("data_records.domain_version 尚无等价转换，记录 #\(hint)。")
                    continue
                }
                let payload = row["payload_jsonb"]?.value as? [String: Any] ?? [:]
                do {
                    let wrapped = payload.mapValues(AnyCodable.init)
                    _ = try LocalRecordCodec.normalizedPayload(domainKey: domain, payload: wrapped)
                } catch {
                    result.append("data_records.payload_jsonb 不符合当前 \(domain) 事实合同，记录 #\(hint)；请核对历史字段后再迁移。")
                }
                continue
            }
            let sourceValues = row.mapValues(\.value)
            if let balance = LocalHistorySourceCompatibility.walletValue(sourceValues, field: "snapshot_balance"),
               LocalHistorySourceCompatibility.validWalletBalance(balance) {
                // Preserve the confirmed source amount; never substitute zero.
            } else {
                result.append("data_records.snapshot_balance 缺少可确认的钱包金额或金额格式无效，记录 #\(hint)。")
            }
            if let kind = LocalHistorySourceCompatibility.walletValue(sourceValues, field: "account_snapshot_kind") as? String,
               ["asset", "liability"].contains(kind) {
                // Source kind is explicit.
            } else {
                result.append("data_records.account_snapshot_kind 缺少可确认的钱包类型，记录 #\(hint)。")
            }
        }
        for row in rows[.transactions, default: []] {
            let id = row["id"]?.value as? String ?? ""
            let hint = recordHint(id)
            let type = row["type"]?.value as? String ?? ""
            if type != "expense" {
                result.append("transactions.type 没有已证明的无重复映射，记录 #\(hint)。")
            } else {
                let status = row["status"]?.value as? String ?? ""
                if !["done", "pending"].contains(status) {
                    result.append("transactions.status 没有当前迁移映射，记录 #\(hint)。")
                }
            }
        }
        for row in rows[.staging, default: []] {
            let id = row["id"]?.value as? String ?? ""
            let hint = recordHint(id)
            let status = row["status"]?.value as? String ?? ""
            if !["unassigned", "pending_review", "assigned", "confirmed", "archived", "discarded", "failed"].contains(status) {
                result.append("staging_records.status 缺失或没有当前迁移映射，记录 #\(hint)。")
            }
            let domain = (row["resolved_domain_key"]?.value as? String) ?? (row["detected_domain_key"]?.value as? String) ?? ""
            let archived = ["assigned", "confirmed", "archived"].contains(status)
            if !stagingDomainMappable(domain, status: status) {
                result.append("staging_records.resolved_domain_key/detected_domain_key 缺失或没有当前迁移映射，记录 #\(hint)。")
            }
            let payload = row["extracted_json"]?.value as? [String: Any] ?? [:]
            let nested = payload["payload_jsonb"] as? [String: Any] ?? [:]
            let date = (payload["record_date"] as? String) ?? (nested["record_date"] as? String)
            if let date, NativeLocalDate.monthKey(from: date) != nil {
                // Keep a valid historical business date as-is.
            } else {
                result.append("staging_records.extracted_json.record_date 缺少或不是有效业务日期，记录 #\(hint)。")
            }
            if archived && (row["target_record_id"]?.value as? String) == nil {
                result.append("已归档候选缺少 staging_records.target_record_id，记录 #\(hint)。")
            }
        }
        return result
    }

    private static func recordHint(_ id: String) -> String {
        guard !id.isEmpty else { return "unknown" }
        return String(LocalImageStore.sha256(Data(id.lowercased().utf8)).prefix(10))
    }

    private static func isValidOccurredAt(_ value: String) -> Bool {
        guard NativeLocalDate.monthKey(from: String(value.prefix(10))) != nil else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil || ISO8601DateFormatter().date(from: value) != nil
    }
}
