import Foundation

enum LocalHistorySourceTable: String, CaseIterable, Hashable {
    case accounts, accountEntries = "account_entries", repaymentCycles = "account_repayment_cycles"
    case payments = "liability_payments", transactions, incomes = "income_records"
    case records = "data_records", staging = "staging_records"
}

struct LocalHistorySourcePage {
    let rows: [[String: AnyCodable]]
    let nextCursor: String?
}

/// Raw, read-only history source. Projection, images and reconciliation must succeed before completion.
final class LocalHistoryMigrationSource {
    typealias Fetch = (String, [URLQueryItem], String) async throws -> [[String: AnyCodable]]
    private let fetch: Fetch
    private let pageSize: Int

    init(remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient(), pageSize: Int = 100) {
        self.pageSize = min(max(pageSize, 1), 100)
        self.fetch = { path, query, token in
            try await remoteClient.get([[String: AnyCodable]].self, path: path, queryItems: query, accessToken: token)
        }
    }

    init(pageSize: Int = 100, fetch: @escaping Fetch) {
        self.pageSize = min(max(pageSize, 1), 100)
        self.fetch = fetch
    }

    func page(table: LocalHistorySourceTable, cloudUserID: String, afterID: String?, accessToken: String) async throws -> LocalHistorySourcePage {
        guard let userID = UUID(uuidString: cloudUserID), !accessToken.isEmpty else {
            throw LocalHistoryMigrationError.invalidCloudIdentity
        }
        var query = [URLQueryItem(name: "select", value: "*"),
                     URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString.lowercased())"),
                     URLQueryItem(name: "order", value: "id.asc"),
                     URLQueryItem(name: "limit", value: String(pageSize))]
        if let afterID {
            guard let cursor = UUID(uuidString: afterID) else { throw LocalHistoryMigrationError.invalidCursorScope }
            query.append(URLQueryItem(name: "id", value: "gt.\(cursor.uuidString.lowercased())"))
        }
        let rows = try await fetch("rest/v1/\(table.rawValue)", query, accessToken)
        guard rows.count <= pageSize else { throw LocalDataError.invalidRecord }
        var previous = afterID?.lowercased()
        for row in rows {
            guard let owner = row["user_id"]?.value as? String,
                  UUID(uuidString: owner) == userID,
                  let id = row["id"]?.value as? String,
                  UUID(uuidString: id) != nil else { throw LocalHistoryMigrationError.identityMismatch }
            let normalized = id.lowercased()
            guard previous.map({ normalized > $0 }) ?? true else { throw LocalDataError.invalidRecord }
            previous = normalized
        }
        return LocalHistorySourcePage(rows: rows, nextCursor: rows.count == pageSize ? previous : nil)
    }
}
