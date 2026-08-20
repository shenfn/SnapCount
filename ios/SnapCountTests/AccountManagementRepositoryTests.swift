import Foundation
import XCTest
@testable import SnapCount

final class AccountManagementRepositoryTests: XCTestCase {
    func testA4IOS004BSaveUsesCanonicalRPCWithoutClientUserId() async throws {
        let client = AccountManagementRemoteClientStub()
        client.rpcResponse = accountResponse()
        let repository = AccountRepository(remoteClient: client)

        let account = try await repository.saveAccount(saveCommand(), accessToken: "token")

        XCTAssertEqual(account.id, "account-1")
        XCTAssertEqual(client.rpcName, "save_account")
        XCTAssertEqual(client.rpcBody?["p_name"]?.value as? String, "微信钱包")
        XCTAssertEqual(client.rpcBody?["p_type"]?.value as? String, "wallet_balance")
        XCTAssertNil(client.rpcBody?["user_id"])
        XCTAssertNil(client.rpcBody?["p_user_id"])
    }

    func testA4IOS004BArchiveUsesCanonicalRPC() async throws {
        let client = AccountManagementRemoteClientStub()
        client.rpcResponse = accountResponse(archived: true)
        let repository = AccountRepository(remoteClient: client)

        let account = try await repository.setAccountArchived(
            accountId: "account-1",
            archived: true,
            accessToken: "token"
        )

        XCTAssertTrue(account.isArchived)
        XCTAssertEqual(client.rpcName, "set_account_archived")
        XCTAssertEqual(client.rpcBody?["p_account_id"]?.value as? String, "account-1")
        XCTAssertEqual(client.rpcBody?["p_archived"]?.value as? Bool, true)
    }

    func testA4IOS004HMapsMalformedRPCResponseAndPreservesStableError() async {
        let malformed = AccountManagementRemoteClientStub()
        malformed.rpcResponse = Data("{}".utf8)
        let repository = AccountRepository(remoteClient: malformed)

        do {
            _ = try await repository.setAccountArchived(accountId: "account-1", archived: true, accessToken: "token")
            XCTFail("malformed response must not be accepted")
        } catch let error as SupabaseRemoteError {
            XCTAssertEqual(error.localizedDescription, "invalid_response")
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let blocked = AccountManagementRemoteClientStub()
        blocked.rpcError = SupabaseRemoteError.requestFailed("account_type_transition_blocked")
        let blockedRepository = AccountRepository(remoteClient: blocked)
        do {
            _ = try await blockedRepository.saveAccount(saveCommand(), accessToken: "token")
            XCTFail("stable database error must be preserved")
        } catch let error as SupabaseRemoteError {
            XCTAssertEqual(error.localizedDescription, "account_type_transition_blocked")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    private func saveCommand() -> AccountManagementSaveCommand {
        AccountManagementSaveCommand(
            accountId: nil,
            name: "微信钱包",
            type: .walletBalance,
            institution: "微信",
            last4: "",
            initialBalance: 320,
            billDay: nil,
            paymentDueDay: nil,
            autoDebitAccountId: nil,
            autoConfirmRepayment: false,
            isDefaultExpense: true,
            isDefaultIncome: false
        )
    }
}

private final class AccountManagementRemoteClientStub: SupabaseRemoteClientProtocol {
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

private func accountResponse(archived: Bool = false) -> Data {
    let json = """
    {
      "id": "account-1", "name": "微信钱包", "type": "wallet_balance", "institution": "微信",
      "last4": null, "currency": "CNY", "initial_balance": 320, "current_balance": 320,
      "snapshot_balance": null, "snapshot_at": null, "source_record_table": null, "source_record_id": null,
      "bill_day": null, "payment_due_day": null, "auto_debit_account_id": null,
      "auto_confirm_repayment": false, "grace_period_days": 0, "last_reconciled_at": null,
      "is_default_expense": true, "is_default_income": false, "is_archived": \(archived ? "true" : "false"), "sort_order": 0
    }
    """
    return Data(json.utf8)
}
