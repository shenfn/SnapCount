import Foundation
import GRDB

struct LocalRecordArchive: Codable, Equatable {
    static let currentFormat = "jiezi-local-domain-record-archive"
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let profileID: UUID
    let records: [Record]

    struct Record: Codable, Equatable {
        let id: UUID
        let profileID: UUID
        let domainKey: String
        let title: String
        let summary: String
        let payloadJSON: String
        let recordDate: String
        let recordTime: String?
        let note: String?
        let imagePath: String?
        let imageHash: String?
        let imageDataBase64: String?
        let localVersion: Int64
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?
    }
}

final class LocalRecordPortability {
    private let database: LocalDatabase
    private let imageStore: LocalImageStore?

    init(database: LocalDatabase, imageStore: LocalImageStore? = nil) {
        self.database = database
        self.imageStore = imageStore
    }

    func exportArchive(
        request: NativeDataExportRequest,
        exportedAt: Date = Date()
    ) throws -> Data {
        try database.writer.read { db in
            guard let profileIDString = try String.fetchOne(
                db,
                sql: "SELECT id FROM local_profiles ORDER BY created_at ASC, id ASC LIMIT 1"
            ), let profileID = UUID(uuidString: profileIDString) else {
                throw LocalDataError.invalidIdentifier
            }
            let dateRange = Self.dateRange(for: request.range, now: exportedAt)
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, domain_key, title, summary, payload_json,
                           record_date, record_time, note, image_path, image_hash,
                           local_version, created_at, updated_at, deleted_at
                    FROM local_records
                    WHERE profile_id = ?
                      AND domain_key IN ('food', 'sleep', 'sport', 'reading')
                      AND deleted_at IS NULL
                      AND record_date BETWEEN ? AND ?
                    ORDER BY record_date ASC, record_time ASC, id ASC
                    """,
                arguments: [profileID.uuidString, dateRange.start, dateRange.end]
            )
            let records = rows.map { row in
                let imagePath: String? = row["image_path"]
                let imageDataBase64: String?
                if request.includeImages,
                   let imagePath,
                   let imageStore,
                   let data = try? Data(contentsOf: imageStore.url(for: imagePath)) {
                    imageDataBase64 = data.base64EncodedString()
                } else {
                    imageDataBase64 = nil
                }
                return LocalRecordArchive.Record(
                    id: UUID(uuidString: row["id"])!,
                    profileID: UUID(uuidString: row["profile_id"])!,
                    domainKey: row["domain_key"],
                    title: row["title"],
                    summary: row["summary"],
                    payloadJSON: request.includeFullPayload ? row["payload_json"] : "{}",
                    recordDate: row["record_date"],
                    recordTime: row["record_time"],
                    note: row["note"],
                    imagePath: imagePath,
                    imageHash: row["image_hash"],
                    imageDataBase64: imageDataBase64,
                    localVersion: row["local_version"],
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"],
                    deletedAt: row["deleted_at"]
                )
            }
            return try Self.encode(
                LocalRecordArchive(
                    format: LocalRecordArchive.currentFormat,
                    schemaVersion: LocalRecordArchive.currentSchemaVersion,
                    exportedAt: exportedAt,
                    profileID: profileID,
                    records: records
                ),
                format: request.format
            )
        }
    }

    private static func encode(_ archive: LocalRecordArchive, format: NativeExportFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(archive)
        case .csv:
            var lines = ["id,domain_key,title,summary,record_date,record_time,note,image_path,image_hash,image_data_base64,payload_json"]
            for record in archive.records {
                lines.append([
                    record.id.uuidString,
                    record.domainKey,
                    record.title,
                    record.summary,
                    record.recordDate,
                    record.recordTime ?? "",
                    record.note ?? "",
                    record.imagePath ?? "",
                    record.imageHash ?? "",
                    record.imageDataBase64 ?? "",
                    record.payloadJSON
                ].map(csvField).joined(separator: ","))
            }
            return Data(lines.joined(separator: "\n").utf8)
        }
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func dateRange(for range: NativeExportRange, now: Date) -> (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let today = NativeLocalDate.dateKey(now)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let start: Date
        switch range {
        case .thisMonth:
            start = monthStart
        case .lastMonth:
            start = calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
        case .lastThreeMonths:
            start = calendar.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart
        case .all:
            return ("0000-01-01", today)
        }
        let end: Date
        switch range {
        case .lastMonth:
            end = calendar.date(byAdding: .day, value: -1, to: monthStart) ?? monthStart
        default:
            end = now
        }
        return (NativeLocalDate.dateKey(start), NativeLocalDate.dateKey(end))
    }
}
