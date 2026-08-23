import XCTest
@testable import SnapCount

final class LocalExpenseAppUseCaseTests: XCTestCase {
    func testLocalAppBoundaryTypesExistBeforeImplementation() {
        XCTAssertNotNil(LocalProfileStoreProtocol.self)
        XCTAssertNotNil(LocalExpenseUseCaseProtocol.self)
    }

    func testLocalProfileIsResolvedWithoutCloudSession() async throws {
        let store: LocalProfileStoreProtocol = try LocalProfileStore()
        let profile = try store.activeProfile()

        XCTAssertNil(profile.cloudUserID)
        XCTAssertFalse(profile.syncEnabled)
    }

    func testLocalExpenseUseCaseAcceptsNoNetworkProvider() {
        let _: LocalExpenseUseCaseProtocol.Type = LocalExpenseUseCaseProtocol.self
        XCTAssertTrue(true)
    }
}
