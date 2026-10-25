import XCTest
@testable import SnapCount

final class LocalHistoryMigrationSourceTests: XCTestCase {
    func testLF03902SourceRetainsRawRelationsAndScopesEveryPage() async throws {
        let user = UUID()
        let first = "00000000-0000-0000-0000-000000000001"
        let source = LocalHistoryMigrationSource(pageSize: 1) { path, query, token in
            XCTAssertEqual(path, "rest/v1/account_entries")
            XCTAssertEqual(token, "synthetic-token")
            XCTAssertTrue(query.contains(URLQueryItem(name: "user_id", value: "eq.\(user.uuidString.lowercased())")))
            XCTAssertTrue(query.contains(URLQueryItem(name: "select", value: "*")))
            return [["id": AnyCodable(first), "user_id": AnyCodable(user.uuidString), "source_table": AnyCodable("liability_payments"), "is_voided": AnyCodable(true)]]
        }
        let page = try await source.page(table: .accountEntries, cloudUserID: user.uuidString, afterID: nil, accessToken: "synthetic-token")
        XCTAssertEqual(page.nextCursor, first)
        XCTAssertEqual(page.rows.first?["is_voided"]?.value as? Bool, true)
    }

    func testLF03908SourceRejectsCrossIdentityRows() async throws {
        let source = LocalHistoryMigrationSource { _, _, _ in
            [["id": AnyCodable(UUID().uuidString), "user_id": AnyCodable(UUID().uuidString)]]
        }
        do {
            _ = try await source.page(table: .accounts, cloudUserID: UUID().uuidString, afterID: nil, accessToken: "synthetic-token")
            XCTFail("cross-identity data must not reach the mapper")
        } catch { XCTAssertEqual(error as? LocalHistoryMigrationError, .identityMismatch) }
    }
}
