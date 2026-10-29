import Foundation

/// The input is diagnostic text, never a source row. Only known fields and hashed IDs are exported.
struct LocalHistoryMigrationIssueReport {
    struct Group: Identifiable {
        let id: String
        let title: String
        let issueCount: Int
        let recordCount: Int
    }
    private struct Issue {
        let field: String
        let title: String
        let record: String?
        var text: String { "\(title)（\(field)）" + (record.map { "，记录 #\($0)。" } ?? "；未提供记录标识。") }
    }
    private let entries: [Issue]
    static let pageSize = 50

    init(blockers: [String]) {
        entries = blockers.map { text in
            let record = text.range(of: "#[0-9a-f]{10}(?![0-9a-f])", options: .regularExpression)
                .map { String(text[$0].dropFirst()) }
            let fields: [(String, String)] = [
                ("data_records.domain_key", "记录类型尚无兼容映射"),
                ("data_records.occurred_at", "历史记录缺少可确认的发生日期"),
                ("data_records.domain_version", "历史记录版本尚无兼容转换"),
                ("data_records.payload_jsonb", "历史记录内容需要兼容转换"),
                ("data_records.snapshot_balance", "钱包记录缺少可确认的金额"),
                ("data_records.account_snapshot_kind", "钱包记录类型需要核对"),
                ("data_records.financial_reference", "待核对记录仍被账务关系引用"),
                ("data_records.created_at", "历史记录缺少有效创建时间"),
                ("data_records.updated_at", "历史记录缺少有效更新时间"),
                ("staging_records.created_at", "历史候选缺少有效创建时间"),
                ("staging_records.updated_at", "历史候选缺少有效更新时间"),
                ("transactions.type", "账单类型尚无兼容映射"),
                ("transactions.status", "账单状态尚无兼容映射"),
                ("staging_records.status", "候选状态尚无兼容映射"),
                ("staging_records.detected_domain_key", "候选尚未确定数据类型"),
                ("staging_records.resolved_domain_key/detected_domain_key", "候选尚未确定数据类型"),
                ("staging_records.extracted_json.record_date", "候选缺少可确认的业务日期"),
                ("staging_records.target_record_id", "已归档候选缺少关联记录")
            ]
            if let match = fields.first(where: { text.contains($0.0) }) {
                return Issue(field: match.0, title: match.1, record: record)
            }
            // 本机必填列没有源值：列名是 schema 信息，可以安全显示；原文仍然不导出。
            if let token = Self.localColumn(in: text) {
                return Issue(field: token, title: "本机必填字段没有源值（\(token)）", record: record)
            }
            // Unknown messages may contain source values. Preserve their count and safe ID only.
            return Issue(field: "other", title: "其他迁移问题（原文未纳入安全清单）", record: record)
        }
    }
    /// 从「local_xxx.yyy 缺少可确认的源字段」里取出列名。只接受本机 schema 形状，不返回原文。
    private static func localColumn(in text: String) -> String? {
        text.range(of: "local_[a-z_]+\\.[a-z_]+", options: .regularExpression).map { String(text[$0]) }
    }
    var issues: [String] { entries.map(\.text) }
    var affectedRecordCount: Int { Set(entries.compactMap(\.record)).count }
    var unidentifiedIssueCount: Int { entries.filter { $0.record == nil }.count }
    var groups: [Group] {
        Dictionary(grouping: entries, by: \.field).map { field, values in
            Group(id: field, title: values[0].title, issueCount: values.count,
                  recordCount: Set(values.compactMap(\.record)).count)
        }.sorted { $0.issueCount == $1.issueCount ? $0.id < $1.id : $0.issueCount > $1.issueCount }
    }
    var summary: String {
        "\(entries.count) 项问题，涉及 \(affectedRecordCount) 条可识别记录" +
            (unidentifiedIssueCount > 0 ? "；另有 \(unidentifiedIssueCount) 项未提供记录标识" : "") + "。本次尚未入账。"
    }
    var pageCount: Int { (entries.count + Self.pageSize - 1) / Self.pageSize }
    func issues(onPage page: Int) -> [String] {
        guard page >= 0, page < pageCount else { return [] }
        return entries.dropFirst(page * Self.pageSize).prefix(Self.pageSize).map(\.text)
    }
    var exportText: String {
        (["芥子历史迁移问题清单（脱敏）", summary,
          "同一记录可能有多项问题；分组记录数不能相加。未识别原文不会导出。"] +
         groups.map { "\($0.title)：\($0.issueCount) 项 / \($0.recordCount) 条可识别记录 [\($0.id)]" } +
         issues.enumerated().map { "\($0.offset + 1). \($0.element)" }).joined(separator: "\n")
    }
}
