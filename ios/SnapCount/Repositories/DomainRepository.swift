import Foundation

protocol DomainRepositoryProtocol {
    func fetchDefinitions(accessToken: String) async throws -> [NativeDomainDefinition]
}

final class DomainRepository: DomainRepositoryProtocol {
    private let remoteClient: SupabaseRemoteClientProtocol

    init(remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()) { self.remoteClient = remoteClient }

    func fetchDefinitions(accessToken: String) async throws -> [NativeDomainDefinition] {
        let rows = try await remoteClient.get(
            [DomainDefinitionRow].self,
            path: "rest/v1/data_domains",
            queryItems: [
                URLQueryItem(name: "select", value: "key,name,description,icon,is_system,schema_json,display_json"),
                URLQueryItem(name: "status", value: "eq.active"),
                URLQueryItem(name: "order", value: "created_at.asc")
            ],
            accessToken: accessToken
        )
        return rows.map { row in NativeDomainDefinition(id: row.key, name: row.name, description: row.description ?? "", icon: row.icon ?? "", isSystem: row.isSystem ?? false, schema: row.schema ?? [:], display: row.display ?? [:], recordCount: 0) }
    }
}

private struct DomainDefinitionRow: Decodable {
    let key: String
    let name: String
    let description: String?
    let icon: String?
    let isSystem: Bool?
    let schema: [String: AnyCodable]?
    let display: [String: AnyCodable]?
    enum CodingKeys: String, CodingKey { case key, name, description, icon; case isSystem = "is_system"; case schema = "schema_json"; case display = "display_json" }
}
