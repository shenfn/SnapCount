import Foundation
import GRDB

struct LocalHistoryUnresolvedRecord: Equatable {
    let id: String
    let profileID: UUID
    let sourceTable: String
    let sourceID: UUID
    let sourceJSON: String
    let issues: [String]
    let imagePath: String?
    let imageHash: String?
    let createdAt: Date
    let updatedAt: Date
}

/// Read-only historical evidence. These rows never enter business projections or the sync outbox.
final class LocalHistoryUnresolvedRepository {
    private let database: LocalDatabase

    init(database: LocalDatabase) { self.database = database }

    func record(id: String, profileID: UUID) throws -> LocalHistoryUnresolvedRecord? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM local_history_unresolved_records WHERE id = ? AND profile_id = ?", arguments: [id, profileID.uuidString]) else { return nil }
            return try Self.decode(row, profileID: profileID)
        }
    }

    func count(profileID: UUID) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_history_unresolved_records WHERE profile_id = ?", arguments: [profileID.uuidString]) ?? 0
        }
    }

    func records(profileID: UUID) throws -> [LocalHistoryUnresolvedRecord] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM local_history_unresolved_records WHERE profile_id = ? ORDER BY created_at DESC, id", arguments: [profileID.uuidString]).map { try Self.decode($0, profileID: profileID) }
        }
    }

    private static func decode(_ row: Row, profileID: UUID) throws -> LocalHistoryUnresolvedRecord {
        let id: String = row["id"]
        let sourceTable: String = row["source_table"]
        let sourceText: String = row["source_id"]
        let sourceJSON: String = row["source_json"]
        let issuesJSON: String = row["issues_json"]
        guard let sourceID = UUID(uuidString: sourceText),
              let issues = try? JSONDecoder().decode([String].self, from: Data(issuesJSON.utf8)) else {
            throw LocalDataError.invalidRecord
        }
        return LocalHistoryUnresolvedRecord(id: id, profileID: profileID, sourceTable: sourceTable,
            sourceID: sourceID, sourceJSON: sourceJSON, issues: issues,
            imagePath: row["image_path"], imageHash: row["image_hash"],
            createdAt: row["created_at"], updatedAt: row["updated_at"])
    }

    /// Shared by backup validation; never invent timestamps, identifiers or missing facts.
    static func validate(_ row: [String: Any]) throws {
        let table = "local_history_unresolved_records"
        guard let sourceTable = row["source_table"] as? String,
              ["data_records", "staging_records"].contains(sourceTable),
              let sourceText = row["source_id"] as? String, let sourceID = UUID(uuidString: sourceText),
              row["id"] as? String == "\(sourceTable)/\(sourceID.uuidString.lowercased())",
              let json = row["source_json"] as? String,
              let original = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let originalID = original["id"] as? String, UUID(uuidString: originalID) == sourceID,
              let owner = original["user_id"] as? String, UUID(uuidString: owner) != nil,
              let issuesJSON = row["issues_json"] as? String,
              let issues = try? JSONDecoder().decode([String].self, from: Data(issuesJSON.utf8)),
              !issues.isEmpty, issues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              let created = row["created_at"] as? String, let createdDate = parseDate(created),
              let updated = row["updated_at"] as? String, let updatedDate = parseDate(updated),
              let originalCreated = original["created_at"] as? String, let originalCreatedDate = parseDate(originalCreated),
              let originalUpdated = original["updated_at"] as? String, let originalUpdatedDate = parseDate(originalUpdated),
              abs(createdDate.timeIntervalSince(originalCreatedDate)) <= 0.001,
              abs(updatedDate.timeIntervalSince(originalUpdatedDate)) <= 0.001 else {
            throw LocalCompleteBackupError.invalidRows(table)
        }
        let path = row["image_path"] as? String
        let hash = row["image_hash"] as? String
        guard (path == nil && hash == nil) || (path?.isEmpty == false && hash?.count == 64 && hash!.allSatisfy({ $0.isHexDigit })) else {
            throw LocalCompleteBackupError.invalidRows(table)
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        // 与映射侧共用同一份解析：云端 timestamptz 带 6 位微秒，这里若只认 3 位，
        // 就会出现「归档能建出来、导入校验却判它非法」。
        LocalHistorySourceCompatibility.parseTimestamp(text)
    }
}
