import XCTest
@testable import SnapCount

final class SnapCountTests: XCTestCase {
    func testAppTabsHaveTitles() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testDashboardRepositoryProtocolSupportsStubInjection() async throws {
        let expected = DashboardSnapshot(todayCount: 3)
        let repository = DashboardRepositoryStub(snapshot: expected)

        let snapshot = try await repository.fetchDashboard(accessToken: "test-token")

        XCTAssertEqual(snapshot.todayCount, 3)
    }

    func testRecordRepositoryProtocolSupportsStubInjection() async throws {
        let repository: RecordRepositoryProtocol = RecordRepositoryStub()
        try await repository.delete(reference: "expense:record-1", accessToken: "test-token")
    }

    func testInboxRepositoryProtocolSupportsStubInjection() async throws {
        let repository = InboxRepositoryStub()
        let result = try await repository.retry(id: "staging-1", accessToken: "test-token")
        XCTAssertFalse(result.displayText.isEmpty)
    }

    func testInboxArchiveDomainsPreservePWAContract() {
        XCTAssertEqual(
            InboxArchiveDomains.all.map(\.id),
            ["expense", "income", "sport", "sleep", "reading", "food", "wallet"]
        )
        XCTAssertEqual(
            InboxArchiveDomains.all.map(\.systemImage),
            ["creditcard", "arrow.down.circle", "figure.run", "moon", "book", "fork.knife", "wallet.pass"]
        )
    }

    func testDayRecordGroupFiltersByPWAKinds() {
        let records = [
            NativeDayRecord(id: "expense-1", reference: "tx-1", dateKey: "2026-07-12", kind: .expense, domainKey: "expense", title: "早餐", subtitle: "微信 · 餐饮", value: "¥12.00", timeLabel: "08:00", systemImage: "creditcard"),
            NativeDayRecord(id: "sport-1", reference: "data-1", dateKey: "2026-07-12", kind: .sport, domainKey: "sport", title: "骑行", subtitle: "30 分钟", value: "", timeLabel: "07:00", systemImage: "figure.run")
        ]
        let group = NativeDayRecordGroup(dateKey: "2026-07-12", records: records)

        XCTAssertEqual(group.records(for: .expense).map(\.reference), ["tx-1"])
        XCTAssertEqual(group.records(for: .sport).map(\.reference), ["data-1"])
        XCTAssertEqual(group.availableKinds, [.all, .expense, .sport])
    }

    func testDayRecordKindsPreservePWADomainKeys() {
        XCTAssertEqual(
            NativeDayRecordKind.allCases.map(\.rawValue),
            ["all", "expense", "income", "sport", "sleep", "food", "reading", "wallet", "staging"]
        )
    }


}

private struct DashboardRepositoryStub: DashboardRepositoryProtocol {
    let snapshot: DashboardSnapshot

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
        snapshot
    }
}


private struct RecordRepositoryStub: RecordRepositoryProtocol {
    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        "expense:record-1"
    }

    func delete(reference: String, accessToken: String) async throws {}
}

private struct InboxRepositoryStub: InboxRepositoryProtocol {
    func discard(id: String, accessToken: String) async throws {}

    func retry(id: String, accessToken: String) async throws -> ShortcutUploadResult {
        ShortcutUploadResult(displayText: "已重新识别")
    }

    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> String {
        "expense:record-1"
    }

    func resolveImageURL(path: String, accessToken: String) async throws -> URL {
        URL(string: "https://example.com/receipt.jpg")!
    }
}
