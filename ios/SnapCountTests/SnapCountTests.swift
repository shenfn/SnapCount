import XCTest
@testable import SnapCount

final class SnapCountTests: XCTestCase {
    func testAppTabsHaveTitles() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.title.isEmpty })
    }
}
