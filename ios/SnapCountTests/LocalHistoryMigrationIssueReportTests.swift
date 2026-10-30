import XCTest
@testable import SnapCount

final class LocalHistoryMigrationIssueReportTests: XCTestCase {
    func testLF03920CompleteReportDoesNotTruncateAndCountsRecordsOnce() {
        let issues = (0..<411).map {
            "data_records.occurred_at 缺少日期，记录 #\(String(format: "%010x", $0 / 3))。"
        }
        let report = LocalHistoryMigrationIssueReport(blockers: issues)
        XCTAssertEqual(report.issues.count, 411)
        XCTAssertEqual(report.affectedRecordCount, 137)
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups.first?.issueCount, 411)
        XCTAssertEqual(report.groups.first?.recordCount, 137)
        XCTAssertTrue(report.exportText.contains("411. "))
        XCTAssertEqual(report.pageCount, 9)
        XCTAssertEqual(report.issues(onPage: 8).count, 11)
        XCTAssertEqual(report.issues(onPage: 9), [])
        XCTAssertEqual(report.issues(onPage: -1), [])
    }

    func testLF03920UnknownIssuesRemainVisibleAndUnidentifiedCountIsExplicit() {
        let report = LocalHistoryMigrationIssueReport(blockers: [
            "staging_records.status 缺失，记录 #0123456789。",
            "staging_records.extracted_json.record_date 缺失，记录 #0123456789。",
            "未来诊断格式，无记录标识"
        ])
        XCTAssertEqual(report.affectedRecordCount, 1)
        XCTAssertEqual(report.unidentifiedIssueCount, 1)
        XCTAssertEqual(report.groups.count, 3)
        XCTAssertFalse(report.exportText.contains("未来诊断格式，无记录标识"))
        XCTAssertTrue(report.summary.contains("1 条可识别记录"))
        XCTAssertTrue(report.summary.contains("1 项未提供记录标识"))
        XCTAssertEqual(LocalHistoryMigrationIssueReport(blockers: []).pageCount, 0)
    }
    func testLF03920ExportNeverIncludesArbitrarySourceTextEvenForKnownFields() {
        let report = LocalHistoryMigrationIssueReport(blockers: [
            "data_records.payload_jsonb user@example.com https://private.invalid/?token=secret 123e4567-e89b-12d3-a456-426614174000，记录 #abcdef0123。",
            "unrecognized user@example.com https://private.invalid/?token=secret"
        ])
        XCTAssertFalse(report.exportText.contains("user@example.com"))
        XCTAssertFalse(report.exportText.contains("private.invalid"))
        XCTAssertFalse(report.exportText.contains("secret"))
        XCTAssertFalse(report.exportText.contains("123e4567"))
        XCTAssertTrue(report.exportText.contains("#abcdef0123"))
        XCTAssertEqual(report.issues.count, 2)
    }

    /// 本机约束未通过时，问题清单必须说出是哪一列，否则只能归到「其他」。
    func testLF03933LocalRequiredColumnGapIsNamedInsteadOfFallingIntoOther() {
        let report = LocalHistoryMigrationIssueReport(blockers: [
            "local_records.created_at 缺少可确认的源字段，记录 #abcdef0123。"
        ])
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups[0].id, "local_records.created_at")
        XCTAssertEqual(report.groups[0].title, "本机导入校验未通过（local_records.created_at）")
        XCTAssertEqual(report.affectedRecordCount, 1)
        XCTAssertEqual(report.unidentifiedIssueCount, 0)
        XCTAssertTrue(report.exportText.contains("local_records.created_at"))
        XCTAssertTrue(report.exportText.contains("#abcdef0123"))
    }

    /// 影子导入拒绝一条流水时，问题清单必须能归到具体表和列，并带上记录标识。
    /// 修好根因之前这条只会显示成「其他迁移问题（原文未纳入安全清单）」。
    func testLF03934ShadowImportRejectionIsNamedByTableAndColumn() {
        let report = LocalHistoryMigrationIssueReport(blockers: [
            "local_account_entries.source_id 指向的 expense 记录不在本次迁移范围内，记录 #0123456789"
        ])
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups[0].id, "local_account_entries.source_id")
        XCTAssertEqual(report.unidentifiedIssueCount, 0)
        XCTAssertEqual(report.affectedRecordCount, 1)
        XCTAssertTrue(report.exportText.contains("local_account_entries.source_id"))
        XCTAssertTrue(report.exportText.contains("#0123456789"))
    }

    /// 同标识内容不同的行级问题必须说出「哪几列不一致」。
    /// 只给到「local_expenses.id」时，用户和我们都无从判断是数据问题还是比较口径问题。
    func testLF03934ConflictingColumnsAreNamedInReport() {
        let report = LocalHistoryMigrationIssueReport(blockers: [
            "local_expenses.id 与本机同标识记录内容不同（amount_minor/category），记录 #abcdef0123"
        ])
        XCTAssertEqual(report.groups.count, 1)
        XCTAssertEqual(report.groups[0].id, "local_expenses.id")
        XCTAssertEqual(report.affectedRecordCount, 1)
        XCTAssertTrue(report.issues[0].contains("amount_minor/category"), report.issues[0])
        XCTAssertFalse(report.issues[0].contains("（local_expenses.id）（local_expenses.id）"),
                       "字段名不应重复：\(report.issues[0])")
    }

    /// 行级阻塞文案必须同时带「源表.字段」和「#记录标识」，否则归类与计数都做不到。
    func testLF03933BlockedRowTextKeepsFieldAndRecordIdentity() {
        let report = LocalHistoryMigrationIssueReport(blockers: [
            "staging_records.detected_domain_key 域 expense 尚无等价映射，记录 #0123456789。",
            "staging_records.extracted_json.record_date 缺少有效业务日期，记录 #fedcba9876。"
        ])
        XCTAssertEqual(report.unidentifiedIssueCount, 0)
        XCTAssertEqual(report.affectedRecordCount, 2)
        XCTAssertEqual(Set(report.groups.map(\.id)),
                       ["staging_records.detected_domain_key", "staging_records.extracted_json.record_date"])
    }
}
