import Foundation

struct LocalHistoryMigrationInspection {
    let cloudUserID: String
    let rows: [LocalHistorySourceTable: [[String: AnyCodable]]]
    let blockers: [String]
    var counts: [String: Int] { Dictionary(uniqueKeysWithValues: rows.map { ($0.key.rawValue, $0.value.count) }) }
    var sourceImagePaths: Set<String> {
        Set(rows.values.flatMap { $0 }.compactMap { row in
            for key in ["image_url", "source_image_path", "image_path"] {
                if let path = row[key]?.value as? String, !path.isEmpty { return path }
            }
            return nil
        })
    }
    func imageReference(for path: String) -> (table: String, field: String, recordID: String)? {
        for table in LocalHistorySourceTable.allCases {
            for row in rows[table, default: []] {
                for field in ["image_url", "source_image_path", "image_path"] where row[field]?.value as? String == path {
                    return (table.rawValue, field, row["id"]?.value as? String ?? "")
                }
            }
        }
        return nil
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
            if row["snapshot_balance"]?.value == nil || row["snapshot_balance"]?.value is NSNull {
                result.append("data_records.snapshot_balance 缺少钱包金额，记录 #\(hint)。")
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
            if !(Set(["expense", "wallet", "food", "sleep", "sport", "reading"]).contains(domain)
                    || (archived && domain == "expense")) {
                result.append("staging_records.resolved_domain_key/detected_domain_key 缺失或没有当前迁移映射，记录 #\(hint)。")
            }
            let payload = row["extracted_json"]?.value as? [String: Any] ?? [:]
            let nested = payload["payload_jsonb"] as? [String: Any] ?? [:]
            let date = (payload["record_date"] ?? nested["record_date"]) as? String
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
