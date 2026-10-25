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
    var summary: String {
        let detail = LocalHistorySourceTable.allCases.map { "\($0.rawValue)：\(rows[$0, default: []].count)" }.joined(separator: "、")
        return "只读预检：\(detail)。" + (blockers.isEmpty ? "已读取源数据；尚未写入本机。" : "尚未迁移：" + blockers.joined(separator: "；"))
    }
}

/// Does not bind sync or write facts. A preview cannot mark the checkpoint completed.
final class LocalHistoryMigrationUseCase {
    private let source: LocalHistoryMigrationSource
    init(source: LocalHistoryMigrationSource = LocalHistoryMigrationSource()) { self.source = source }

    func inspect(cloudUserID: String, accessToken: String, isCurrent: () -> Bool) async throws -> LocalHistoryMigrationInspection {
        var rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [:]
        for table in LocalHistorySourceTable.allCases {
            var cursor: String?
            repeat {
                guard isCurrent() else { throw LocalHistoryMigrationError.staleAttempt }
                let page = try await source.page(table: table, cloudUserID: cloudUserID, afterID: cursor, accessToken: accessToken)
                guard isCurrent() else { throw LocalHistoryMigrationError.staleAttempt }
                rows[table, default: []].append(contentsOf: page.rows)
                guard rows.values.reduce(0, { $0 + $1.count }) <= 100_000 else { throw LocalCompleteBackupError.archiveTooLarge }
                cursor = page.nextCursor
            } while cursor != nil
        }
        return LocalHistoryMigrationInspection(cloudUserID: cloudUserID, rows: rows, blockers: Self.blockers(rows))
    }

    private static func blockers(_ rows: [LocalHistorySourceTable: [[String: AnyCodable]]]) -> [String] {
        var result: [String] = []
        for row in rows[.accountEntries, default: []] {
            if (row["is_voided"]?.value as? Bool) == true {
                result.append("流水 \(row["id"]?.value as? String ?? "未知") 缺少可确认的作废时间兼容，尚未写入")
            }
        }
        for row in rows[.records, default: []] {
            let domain = row["domain_key"]?.value as? String ?? ""
            if !Set(["food", "sleep", "sport", "reading", "wallet"]).contains(domain) {
                result.append("记录 \(row["id"]?.value as? String ?? "未知") 的域 \(domain) 不在本地支持范围")
            }
        }
        return result
    }
}
