import Foundation

protocol FinanceVocabularyRepositoryProtocol {
    func fetch(accessToken: String) async throws -> [NativeFinanceVocabularyEntry]
    func record(
        kind: NativeFinanceVocabularyKind,
        displayName: String,
        primaryCategory: String?,
        linkedAccountId: String?,
        accessToken: String
    ) async throws -> NativeFinanceVocabularyEntry
}

final class FinanceVocabularyRepository: FinanceVocabularyRepositoryProtocol {
    private let remoteClient: SupabaseRemoteClientProtocol

    init(remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()) {
        self.remoteClient = remoteClient
    }

    func fetch(accessToken: String) async throws -> [NativeFinanceVocabularyEntry] {
        try await remoteClient.get(
            [NativeFinanceVocabularyEntry].self,
            path: "rest/v1/user_finance_vocabulary",
            queryItems: [
                URLQueryItem(
                    name: "select",
                    value: "id,kind,display_name,primary_category,linked_account_id,source,status,usage_count,last_used_at"
                ),
                URLQueryItem(name: "status", value: "eq.active"),
                URLQueryItem(name: "order", value: "usage_count.desc,last_used_at.desc"),
                URLQueryItem(name: "limit", value: "200")
            ],
            accessToken: accessToken
        )
    }

    func record(
        kind: NativeFinanceVocabularyKind,
        displayName: String,
        primaryCategory: String?,
        linkedAccountId: String?,
        accessToken: String
    ) async throws -> NativeFinanceVocabularyEntry {
        try await remoteClient.rpc(
            NativeFinanceVocabularyEntry.self,
            name: "record_user_finance_vocabulary",
            body: [
                "p_kind": AnyCodable(kind.rawValue),
                "p_display_name": AnyCodable(displayName),
                "p_primary_category": AnyCodable(primaryCategory.map { $0 as Any } ?? NSNull()),
                "p_linked_account_id": AnyCodable(linkedAccountId.map { $0 as Any } ?? NSNull())
            ],
            accessToken: accessToken
        )
    }
}
