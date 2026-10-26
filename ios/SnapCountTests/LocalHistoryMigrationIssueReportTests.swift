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
}
