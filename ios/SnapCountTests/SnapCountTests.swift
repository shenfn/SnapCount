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
}

private struct DashboardRepositoryStub: DashboardRepositoryProtocol {
    let snapshot: DashboardSnapshot

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
        snapshot
    }
}
