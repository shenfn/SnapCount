import Foundation
import CoreFoundation
import GRDB

struct LocalCompanionMemory: Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let memoryKey: String
    let memoryType: String
    let contentJSON: String
    let sourceTable: String?
    let sourceID: String?
    let confidence: Double
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct LocalCompanionMemoryDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let memoryKey: String
    let memoryType: String
    let contentJSON: String
    let sourceTable: String?
    let sourceID: String?
    let confidence: Double
    let createdAt: Date
    let updatedAt: Date
}

/// Local, profile-scoped memory projection for Companion and Planner.
///
/// This repository deliberately has no outbox integration. Memory is a derived
/// local projection and must never become a business-data synchronization unit.
final class LocalCompanionMemoryRepository {
    static let maximumMemoryKeyLength = 128
    static let maximumMemoryTypeLength = 32
    static let maximumContentBytes = 8 * 1024
    static let maximumContextBytes = 8 * 1024
    static let maximumContextItems = 64

    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    @discardableResult
    func upsert(_ draft: LocalCompanionMemoryDraft) throws -> LocalCompanionMemory {
        let draft = Self.normalized(draft)
        try Self.validate(draft)
        return try database.writer.write { db in
            if let existing = try Row.fetchOne(
                db,
                sql: "SELECT id, profile_id, created_at FROM local_companion_memories WHERE profile_id = ? AND memory_key = ?",
                arguments: [draft.profileID.uuidString, draft.memoryKey]
            ) {
                guard let existingProfileID: String = existing["profile_id"],
                      existingProfileID == draft.profileID.uuidString else {
                    throw LocalDataError.invalidIdentifier
                }
                try db.execute(
                    sql: """
                        UPDATE local_companion_memories
                        SET memory_type = ?, content_json = ?, source_table = ?, source_id = ?,
                            confidence = ?, updated_at = ?, deleted_at = NULL
                        WHERE id = ? AND profile_id = ?
                        """,
                    arguments: [
                        draft.memoryType, draft.contentJSON, draft.sourceTable, draft.sourceID,
                        draft.confidence, draft.updatedAt, existing["id"] as String, draft.profileID.uuidString
                    ]
                )
                guard let row = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM local_companion_memories WHERE id = ? AND profile_id = ?",
                    arguments: [existing["id"] as String, draft.profileID.uuidString]
                ) else { throw LocalDataError.recordNotFound }
                return try Self.memory(from: row)
            }

            try db.execute(
                sql: """
                    INSERT INTO local_companion_memories (
                        id, profile_id, memory_key, memory_type, content_json,
                        source_table, source_id, confidence, created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString, draft.profileID.uuidString, draft.memoryKey,
                    draft.memoryType, draft.contentJSON, draft.sourceTable, draft.sourceID,
                    draft.confidence, draft.createdAt, draft.updatedAt
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_companion_memories WHERE id = ? AND profile_id = ?",
                arguments: [draft.id.uuidString, draft.profileID.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            return try Self.memory(from: row)
        }
    }

    func memory(memoryKey: String, profileID: UUID) throws -> LocalCompanionMemory? {
        let key = memoryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= Self.maximumMemoryKeyLength else { return nil }
        return try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM local_companion_memories
                    WHERE profile_id = ? AND memory_key = ? AND deleted_at IS NULL
                    """,
                arguments: [profileID.uuidString, key]
            ) else { return nil }
            return try Self.memory(from: row)
        }
    }

    func memories(profileID: UUID, limit: Int = 64) throws -> [LocalCompanionMemory] {
        let boundedLimit = max(0, min(limit, Self.maximumContextItems))
        guard boundedLimit > 0 else { return [] }
        return try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_companion_memories
                    WHERE profile_id = ? AND deleted_at IS NULL
                    ORDER BY confidence DESC, updated_at DESC, memory_key ASC
                    LIMIT ?
                    """,
                arguments: [profileID.uuidString, boundedLimit]
            ).map(Self.memory(from:))
        }
    }

    /// Soft-delete one memory. A future upsert of the same key reactivates it.
    @discardableResult
    func delete(memoryKey: String, profileID: UUID, at date: Date = Date()) throws -> Bool {
        let key = memoryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= Self.maximumMemoryKeyLength else { return false }
        return try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE local_companion_memories
                    SET deleted_at = ?, updated_at = ?
                    WHERE profile_id = ? AND memory_key = ? AND deleted_at IS NULL
                    """,
                arguments: [date, date, profileID.uuidString, key]
            )
            return db.changesCount > 0
        }
    }

    /// Remove all memories derived from one local source row.
    @discardableResult
    func deleteSource(sourceTable: String, sourceID: String, profileID: UUID, at date: Date = Date()) throws -> Int {
        guard !sourceTable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return try database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE local_companion_memories
                    SET deleted_at = ?, updated_at = ?
                    WHERE profile_id = ? AND source_table = ? AND source_id = ? AND deleted_at IS NULL
                    """,
                arguments: [date, date, profileID.uuidString, sourceTable, sourceID]
            )
            return db.changesCount
        }
    }

    /// Returns the bounded JSON context consumed by local Companion/Planner.
    /// The payload contains no raw prompt, image path, credential or model response.
    func compactContextJSON(profileID: UUID, limit: Int = 64) throws -> String {
        let selected = try memories(profileID: profileID, limit: limit)
        var facts: [[String: Any]] = []
        for memory in selected {
            guard let content = try? Self.object(from: memory.contentJSON) else { continue }
            var fact: [String: Any] = [
                "key": memory.memoryKey,
                "type": memory.memoryType,
                "confidence": memory.confidence
            ]
            if let value = content["value"], !(value is NSNull) {
                fact["value"] = value
            } else {
                fact["content"] = content
            }
            facts.append(fact)
        }

        while !facts.isEmpty {
            let data = try JSONSerialization.data(withJSONObject: ["facts": facts], options: [.sortedKeys])
            if data.count <= Self.maximumContextBytes {
                guard let result = String(data: data, encoding: .utf8) else { throw LocalDataError.invalidRecord }
                return result
            }
            facts.removeLast()
        }
        return "{\"facts\":[]}"
    }

    static func validate(_ draft: LocalCompanionMemoryDraft) throws {
        let key = draft.memoryKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = draft.memoryType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= maximumMemoryKeyLength,
              !type.isEmpty, type.count <= maximumMemoryTypeLength,
              draft.confidence.isFinite, draft.confidence >= 0, draft.confidence <= 1,
              draft.sourceTable.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              (draft.sourceTable == nil) == (draft.sourceID == nil),
              draft.sourceID.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true,
              let data = draft.contentJSON.data(using: .utf8),
              data.count <= maximumContentBytes,
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] else {
            throw LocalDataError.invalidRecord
        }
    }

    private static func normalized(_ draft: LocalCompanionMemoryDraft) -> LocalCompanionMemoryDraft {
        LocalCompanionMemoryDraft(
            id: draft.id,
            profileID: draft.profileID,
            memoryKey: draft.memoryKey.trimmingCharacters(in: .whitespacesAndNewlines),
            memoryType: draft.memoryType.trimmingCharacters(in: .whitespacesAndNewlines),
            contentJSON: draft.contentJSON,
            sourceTable: draft.sourceTable?.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceID: draft.sourceID?.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: draft.confidence,
            createdAt: draft.createdAt,
            updatedAt: draft.updatedAt
        )
    }

    static func validate(_ row: [String: Any]) throws {
        guard let id = row["id"] as? String, UUID(uuidString: id) != nil,
              let profile = row["profile_id"] as? String, UUID(uuidString: profile) != nil,
              let key = row["memory_key"] as? String,
              let type = row["memory_type"] as? String,
              let content = row["content_json"] as? String,
              let confidence = row["confidence"] as? NSNumber,
              CFGetTypeID(confidence) != CFBooleanGetTypeID(),
              let value = Double(confidence.stringValue), value.isFinite,
              let createdAt = row["created_at"] as? String,
              let updatedAt = row["updated_at"] as? String,
              parseDate(createdAt) != nil, parseDate(updatedAt) != nil else {
            throw LocalCompleteBackupError.invalidRows("local_companion_memories")
        }
        let sourceTable = row["source_table"] as? String
        let sourceID = row["source_id"] as? String
        let draft = LocalCompanionMemoryDraft(
            id: UUID(uuidString: id)!, profileID: UUID(uuidString: profile)!,
            memoryKey: key, memoryType: type, contentJSON: content,
            sourceTable: sourceTable, sourceID: sourceID, confidence: value,
            createdAt: parseDate(createdAt)!, updatedAt: parseDate(updatedAt)!
        )
        try validate(draft)
    }

    private static func memory(from row: Row) throws -> LocalCompanionMemory {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]) else {
            throw LocalDataError.invalidRecord
        }
        return LocalCompanionMemory(
            id: id,
            profileID: profileID,
            memoryKey: row["memory_key"],
            memoryType: row["memory_type"],
            contentJSON: row["content_json"],
            sourceTable: row["source_table"],
            sourceID: row["source_id"],
            confidence: row["confidence"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            deletedAt: row["deleted_at"]
        )
    }

    private static func object(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalDataError.invalidRecord
        }
        return object
    }

    private static func parseDate(_ value: String) -> Date? {
        LocalHistorySourceCompatibility.parseTimestamp(value)
    }
}
