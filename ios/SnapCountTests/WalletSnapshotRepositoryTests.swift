import Foundation
import XCTest
@testable import SnapCount

final class WalletSnapshotRepositoryTests: XCTestCase {
    func testA4IOS001CreateUsesCanonicalRPCAndNilAccount() async throws {
        let client = WalletSnapshotRemoteClientStub()
        client.rpcResponse = walletSnapshotResponse(outcome: "created")
        let repository = WalletSnapshotRepository(remoteClient: client)

        let result = try await repository.createAccount(
            from: walletSnapshot(),
            userId: "user-1",
            accessToken: "token"
        )

        XCTAssertEqual(result.outcome, .created)
        XCTAssertEqual(client.rpcName, "apply_wallet_snapshot")
        XCTAssertEqual(client.rpcBody?["p_record_id"]?.value as? String, "record-1")
        XCTAssertTrue(client.rpcBody?["p_account_id"]?.value is NSNull)
    }

    func testA4IOS002LinkUsesTargetAccountOnly() async throws {
        let client = WalletSnapshotRemoteClientStub()
        client.rpcResponse = walletSnapshotResponse(outcome: "linked")
        let repository = WalletSnapshotRepository(remoteClient: client)

        let result = try await repository.link(
            walletSnapshot(),
            to: account(),
            userId: "user-1",
            accessToken: "token"
        )

        XCTAssertEqual(result.outcome, .linked)
        XCTAssertEqual(client.rpcName, "apply_wallet_snapshot")
        XCTAssertEqual(client.rpcBody?["p_record_id"]?.value as? String, "record-1")
        XCTAssertEqual(client.rpcBody?["p_account_id"]?.value as? String, "account-1")
    }

    func testA4IOS004NeedsConfirmationRemainsExplicit() async throws {
        let client = WalletSnapshotRemoteClientStub()
        client.rpcResponse = walletSnapshotResponse(outcome: "needs_confirmation", reviewRequired: true)
        let repository = WalletSnapshotRepository(remoteClient: client)

        let result = try await repository.createAccount(
            from: walletSnapshot(),
            userId: "user-1",
            accessToken: "token"
        )

        XCTAssertEqual(result.outcome, .needsConfirmation)
        XCTAssertTrue(result.reviewRequired)
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.successMessage, "账户已关联，账期/还款需要确认")
    }

    func testA4IOS005MalformedResponseIsRejected() async {
        let client = WalletSnapshotRemoteClientStub()
        client.rpcResponse = Data(#"{"outcome":"created","record_id":"record-1","linked_account_id":"account-1","account":null}"#.utf8)
        let repository = WalletSnapshotRepository(remoteClient: client)

        do {
            _ = try await repository.createAccount(from: walletSnapshot(), userId: "user-1", accessToken: "token")
            XCTFail("malformed response must not be accepted")
        } catch let error as SupabaseRemoteError {
            XCTAssertEqual(error.localizedDescription, "invalid_response")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testA4IOS006StableRPCErrorIsPreserved() async {
        let client = WalletSnapshotRemoteClientStub()
        client.rpcError = SupabaseRemoteError.requestFailed("snapshot_link_conflict: another account")
        let repository = WalletSnapshotRepository(remoteClient: client)

        do {
            _ = try await repository.createAccount(from: walletSnapshot(), userId: "user-1", accessToken: "token")
            XCTFail("RPC error must be thrown")
        } catch let error as SupabaseRemoteError {
            XCTAssertEqual(error.localizedDescription, "snapshot_link_conflict")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func walletSnapshot() -> NativeWalletSnapshot {
        NativeWalletSnapshot(
            id: "record-1",
            title: "微信钱包",
            summary: "余额快照",
            occurredAt: "2026-08-17T02:00:00Z",
            createdAt: "2026-08-17T02:00:00Z",
            payload: ["account_snapshot_kind": AnyCodable("asset"), "snapshot_balance": AnyCodable(320.0)],
            imagePath: nil,
            imageHash: nil,
            linkedAccountId: nil,
            kind: .asset,
            balance: 320,
            snapshotAt: "2026-08-17T02:00:00Z"
        )
    }

    private func account() -> NativeAccount {
        NativeAccount(
            id: "account-1", name: "微信钱包", type: .walletBalance, institution: "微信", last4: "",
            currency: "CNY", initialBalance: 320, currentBalance: 320, snapshotBalance: 320,
            snapshotAt: "2026-08-17T02:00:00Z", sourceRecordTable: "data_records", sourceRecordId: "record-1",
            billDay: nil, paymentDueDay: nil, autoDebitAccountId: nil, autoConfirmRepayment: false,
            gracePeriodDays: 0, lastReconciledAt: nil, isDefaultExpense: false, isDefaultIncome: false,
            isArchived: false, sortOrder: 0
        )
    }
}

private final class WalletSnapshotRemoteClientStub: SupabaseRemoteClientProtocol {
    var rpcName: String?
    var rpcBody: [String: AnyCodable]?
    var rpcResponse = Data("{}".utf8)
    var rpcError: Error?

    func get<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], accessToken: String) async throws -> T { fatalError("unused") }
    func patch(path: String, queryItems: [URLQueryItem], body: [String: AnyCodable], accessToken: String) async throws { fatalError("unused") }
    func delete(path: String, queryItems: [URLQueryItem], accessToken: String) async throws { fatalError("unused") }
    func post<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], body: [String: AnyCodable], accessToken: String) async throws -> T { fatalError("unused") }
    func upsert<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem], body: [String: AnyCodable], accessToken: String) async throws -> T { fatalError("unused") }

    func rpc<T: Decodable>(_ type: T.Type, name: String, body: [String: AnyCodable], accessToken: String) async throws -> T {
        rpcName = name
        rpcBody = body
        if let rpcError { throw rpcError }
        return try JSONDecoder().decode(T.self, from: rpcResponse)
    }

    func postMultipart(path: String, fields: [String: String], accessToken: String) async throws -> Data { fatalError("unused") }
    func postFunction<T: Decodable>(_ type: T.Type, path: String, body: [String: AnyCodable], accessToken: String) async throws -> T { fatalError("unused") }
}

private func walletSnapshotResponse(outcome: String, reviewRequired: Bool = false) -> Data {
    let json = """
    {
      "outcome": "\(outcome)",
      "record_id": "record-1",
      "linked_account_id": "account-1",
      "account": {
        "id": "account-1", "name": "微信钱包", "type": "wallet_balance", "institution": "微信",
        "last4": null, "currency": "CNY", "initial_balance": 320, "current_balance": 320,
        "snapshot_balance": 320, "snapshot_at": "2026-08-17T02:00:00Z",
        "source_record_table": "data_records", "source_record_id": "record-1",
        "bill_day": null, "payment_due_day": null, "auto_debit_account_id": null,
        "auto_confirm_repayment": false, "grace_period_days": 0, "last_reconciled_at": null,
        "is_default_expense": false, "is_default_income": false, "is_archived": false, "sort_order": 0
      },
      "cycle": null, "payment": null, "balance_changed": true, "review_required": \(reviewRequired ? "true" : "false")
    }
    """
    return Data(json.utf8)
}
