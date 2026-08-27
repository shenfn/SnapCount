import Foundation
import XCTest
@testable import SnapCount

final class SupabaseSyncTransportTests: XCTestCase {
    func testBuildsExpenseBatchRequestAndMapsRemoteProjection() async throws {
        let client = SyncRemoteClientStub()
        client.response = Data("""
        {
          "accepted_operation_ids": ["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"],
          "conflicts": [], "rejected": [],
          "remote_accounts": [{"aggregate_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","version":1,"change_kind":"upsert","name":"现金","type":"cash","currency":"CNY","initial_balance":100,"current_balance":90,"deleted_at":null}],
          "remote_expenses": [{"aggregate_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","version":1,"change_kind":"upsert","amount":12.3,"merchant_name":"早餐","category":"food","payment_method":"现金","transaction_date":"2026-08-26","transaction_time":"08:30:00","account_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","deleted_at":null}],
          "remote_account_entries": [{"source_id":"cccccccc-cccc-cccc-cccc-cccccccccccc","account_id":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","direction":"out","amount":12.3,"entry_type":"expense","is_voided":false,"voided_reason":null}],
          "next_pull_cursor":"c:4"
        }
        """.utf8)
        let transport = SupabaseSyncTransport(remoteClient: client, accessToken: { "token" })
        let upload = LocalOutboxUpload(sequence: 1, operationID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!, profileID: UUID(), aggregateKind: "expense", aggregateID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!, operationKind: "upsert", aggregateVersion: 1, idempotencyKey: "idem-1", payloadJSON: "{\"accountID\":\"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb\",\"amountMinor\":123,\"merchantName\":\"早餐\",\"category\":\"food\",\"paymentMethod\":\"现金\",\"transactionDate\":\"2026-08-26\"}", attemptCount: 0, createdAt: Date())
        let result = try await transport.synchronize(cloudUserID: "cloud", profileID: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!, pullCursor: nil, uploads: [upload])
        XCTAssertEqual(client.rpcName, "sync_expense_batch")
        XCTAssertTrue(client.rpcBody?["p_pull_cursor"]?.value is NSNull)
        XCTAssertEqual(result.nextPullCursor, "c:4")
        XCTAssertEqual(result.remoteSnapshot?.expenses.first?.amountMinor, 1230)
        XCTAssertEqual(result.remoteSnapshot?.accountEntries.count, 1)
    }

    func testDREMOTE014MapsRejectedOperationsWithoutTreatingThemAsAccepted() async throws {
        let client = SyncRemoteClientStub()
        let operationID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
        client.response = Data("""
        {
          "accepted_operation_ids": [],
          "conflicts": [],
          "rejected": [{"operation_id":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","reason":"permission_denied"}],
          "remote_accounts": [], "remote_expenses": [], "remote_account_entries": [],
          "next_pull_cursor":"c:8"
        }
        """.utf8)

        let result = try await SupabaseSyncTransport(
            remoteClient: client,
            accessToken: { "token" }
        ).synchronize(
            cloudUserID: "cloud",
            profileID: UUID(),
            pullCursor: "c:7",
            uploads: []
        )

        XCTAssertEqual(result.acceptedOperationIDs, [])
        XCTAssertEqual(result.rejectedOperations, [
            LocalSyncRejectedOperation(operationID: operationID, reason: "permission_denied")
        ])
    }

    func testDREMOTE015MapsCursorExpiredToRecoverableSyncError() async {
        let client = SyncRemoteClientStub()
        client.response = Data("""
        {
          "accepted_operation_ids": [], "conflicts": [], "rejected": [],
          "remote_accounts": [], "remote_expenses": [], "remote_account_entries": [],
          "error":"cursor_expired"
        }
        """.utf8)

        do {
            _ = try await SupabaseSyncTransport(
                remoteClient: client,
                accessToken: { "token" }
            ).synchronize(cloudUserID: "cloud", profileID: UUID(), pullCursor: "c:1", uploads: [])
            XCTFail("Expected cursor_expired")
        } catch let error as LocalSyncError {
            XCTAssertEqual(error, .cursorExpired)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class SyncRemoteClientStub: SupabaseRemoteClientProtocol {
    var rpcName: String?
    var rpcBody: [String: AnyCodable]?
    var response = Data("{}".utf8)
    func get<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], accessToken: String) async throws -> T { fatalError() }
    func patch(path: String, queryItems: [URLQueryItem], body: [String: AnyCodable], accessToken: String) async throws { fatalError() }
    func delete(path: String, queryItems: [URLQueryItem], accessToken: String) async throws { fatalError() }
    func post<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], body: [String: AnyCodable], accessToken: String) async throws -> T { fatalError() }
    func upsert<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], body: [String: AnyCodable], accessToken: String) async throws -> T { fatalError() }
    func rpc<T: Decodable>(_ type: T.Type, name: String, body: [String: AnyCodable], accessToken: String) async throws -> T {
        rpcName = name; rpcBody = body
        return try JSONDecoder().decode(T.self, from: response)
    }
    func postMultipart(path: String, fields: [String: String], accessToken: String) async throws -> Data { fatalError() }
    func postFunction<T: Decodable>(_ type: T.Type, path: String, body: [String: AnyCodable], accessToken: String) async throws -> T { fatalError() }
}
