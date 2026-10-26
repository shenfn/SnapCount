import Foundation
import GRDB
import XCTest
@testable import SnapCount

final class LocalHistoryUnresolvedRepositoryTests: XCTestCase {
    // LF-039.18 / LF-039.19: preserved originals do not manufacture business dates.
    func testOriginalSurvivesBackupWithoutEnteringStatisticsAndConflictRollsBack() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try LocalDatabase(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let target = try LocalDatabase(databaseURL: directory.appendingPathComponent("target.sqlite"))
        let sourceImages = try LocalImageStore(rootDirectory: directory.appendingPathComponent("source-images"))
        let targetImages = try LocalImageStore(rootDirectory: directory.appendingPathComponent("target-images"))
        let profile = try LocalProfileStore(database: source).activeProfile()
        let targetProfile = try LocalProfileStore(database: target).activeProfile()
        let sourceID = UUID()
        let id = "data_records/\(sourceID.uuidString.lowercased())"
        let owner = UUID()
        let original = "{\"id\":\"\(sourceID.uuidString)\",\"user_id\":\"\(owner.uuidString)\",\"created_at\":\"1970-01-01T00:16:40Z\",\"updated_at\":\"1970-01-01T00:16:40Z\",\"occurred_at\":null,\"summary\":\"合成原文\"}"
        let image = try sourceImages.save(data: Data("synthetic-original".utf8), owner: sourceID.uuidString)
        try source.writer.write { db in
            try db.execute(sql: "INSERT INTO local_history_unresolved_records(id,profile_id,source_table,source_id,source_json,issues_json,image_path,image_hash,created_at,updated_at) VALUES (?,?,'data_records',?,?,?,?,?,?,?)",
                arguments: [id, profile.id.uuidString, sourceID.uuidString, original, "[\"缺少发生日期\"]", image.path, image.hash, Date(timeIntervalSince1970: 1000), Date(timeIntervalSince1970: 1000)])
        }
        let portability = LocalCompleteBackupPortability(database: source, imageStore: sourceImages)
        let restore = LocalCompleteBackupPortability(database: target, imageStore: targetImages)
        let archive = try portability.exportBackup()
        XCTAssertEqual(try portability.preview(archive).tableCounts["local_history_unresolved_records"], 1)
        _ = try restore.importBackup(archive, into: targetProfile.id)
        let repository = LocalHistoryUnresolvedRepository(database: target)
        let record = try XCTUnwrap(repository.records(profileID: targetProfile.id).first)
        XCTAssertEqual(record.sourceJSON, original)
        XCTAssertEqual(record.issues, ["缺少发生日期"])
        XCTAssertEqual(try targetImages.data(at: image.path), Data("synthetic-original".utf8))
        XCTAssertEqual(try repository.count(profileID: UUID()), 0)
        XCTAssertNil(try repository.record(id: id, profileID: UUID()))
        XCTAssertEqual(try repository.record(id: id, profileID: targetProfile.id)?.sourceJSON, original)
        XCTAssertEqual(try restore.importBackup(archive, into: targetProfile.id).insertedRows, 0)
        let factReader = try LocalFactReader(database: target)
        let month = try await factReader.activeMonth(monthKey: "2026-10")
        XCTAssertEqual(month?.facts.count, 0)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        var tables = try XCTUnwrap(object["tables"] as? [String: String])
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(tables["local_history_unresolved_records"]).utf8)) as? [[String: Any]])
        rows[0]["source_json"] = original.replacingOccurrences(of: "合成原文", with: "修改后的原文")
        var additional = rows[0]
        let anotherID = UUID()
        additional["id"] = "data_records/\(anotherID.uuidString.lowercased())"
        additional["source_id"] = anotherID.uuidString
        additional["source_json"] = original.replacingOccurrences(of: sourceID.uuidString, with: anotherID.uuidString)
        rows.append(additional)
        tables["local_history_unresolved_records"] = String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self)
        object["tables"] = tables
        XCTAssertThrowsError(try restore.importBackup(JSONSerialization.data(withJSONObject: object), into: targetProfile.id))
        XCTAssertEqual(try repository.count(profileID: targetProfile.id), 1)
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        object["images"] = []
        XCTAssertThrowsError(try portability.preview(JSONSerialization.data(withJSONObject: object)))
        // Old v24 packages did not contain this table; they still restore without fabricated rows.
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        tables = try XCTUnwrap(object["tables"] as? [String: String])
        tables.removeValue(forKey: "local_history_unresolved_records")
        object["tables"] = tables
        object["schemaVersion"] = 24
        let oldPreview = try portability.preview(JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(oldPreview.tableCounts["local_history_unresolved_records"], 0)
    }

    func testLF03918MalformedOriginalIdentityIssuesAndSourceTimestampsAreRejected() throws {
        let sourceID = UUID()
        let valid: [String: Any] = [
            "id": "staging_records/\(sourceID.uuidString.lowercased())",
            "source_table": "staging_records", "source_id": sourceID.uuidString,
            "source_json": "{\"id\":\"\(sourceID.uuidString)\",\"user_id\":\"\(UUID().uuidString)\",\"created_at\":\"2026-10-25T12:00:00Z\",\"updated_at\":\"2026-10-25T12:00:00Z\",\"status\":\"failed\"}", "issues_json": "[\"缺少日期\"]",
            "created_at": "2026-10-25 12:00:00.000", "updated_at": "2026-10-25T12:00:00Z"
        ]
        XCTAssertNoThrow(try LocalHistoryUnresolvedRepository.validate(valid))
        for (key, value) in [
            ("source_table", "other"), ("source_id", "bad-uuid"), ("source_json", "[]"),
            ("issues_json", "[]"), ("created_at", ""), ("updated_at", "not-a-date"), ("updated_at", "2026-10-26T12:00:00Z"), ("image_path", "records/without-hash.jpg")
        ] {
            var invalid = valid
            invalid[key] = value
            XCTAssertThrowsError(try LocalHistoryUnresolvedRepository.validate(invalid), key)
        }
    }
}
