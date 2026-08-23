import Foundation
import GRDB

protocol LocalProfileStoreProtocol {
    func activeProfile() throws -> LocalProfile
}

final class LocalProfileStore: LocalProfileStoreProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    convenience init() throws {
        try self.init(database: LocalDatabase())
    }

    func activeProfile() throws -> LocalProfile {
        try database.writer.write { db in
            if let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, created_at, cloud_user_id, sync_enabled
                    FROM local_profiles
                    ORDER BY created_at ASC, id ASC
                    LIMIT 1
                    """
            ) {
                return try Self.profile(from: row)
            }

            let profile = LocalProfile(
                id: UUID(),
                createdAt: Date(),
                cloudUserID: nil,
                syncEnabled: false
            )
            try db.execute(
                sql: """
                    INSERT INTO local_profiles (id, created_at, cloud_user_id, sync_enabled)
                    VALUES (?, ?, NULL, 0)
                    """,
                arguments: [profile.id.uuidString, profile.createdAt]
            )
            return profile
        }
    }

    private static func profile(from row: Row) throws -> LocalProfile {
        guard let id = UUID(uuidString: row["id"]),
              let createdAt: Date = row["created_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalProfile(
            id: id,
            createdAt: createdAt,
            cloudUserID: row["cloud_user_id"],
            syncEnabled: row["sync_enabled"]
        )
    }
}
