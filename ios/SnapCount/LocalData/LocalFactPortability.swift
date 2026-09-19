import Foundation
import GRDB

struct LocalFactArchive: Codable, Equatable {
    static let currentFormat = "jiezi-local-fact-archive"
    static let currentSchemaVersion = 1

    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let profileID: UUID
    let facts: [Fact]

    struct Fact: Codable, Equatable {
        let id: UUID
        let profileID: UUID
        let reference: String
        let kind: String
        let domainKey: String
        let sourceKind: String
        let domainVersion: String
        let title: String
        let summary: String
        let payloadJSON: String
        let businessDate: String
        let recordTime: String?
        let occurredAt: String?
        let note: String?
        let imagePath: String?
        let imageHash: String?
        let imageDataBase64: String?
        let localVersion: Int64
        let createdAt: Date
        let updatedAt: Date

        init(
            fact: LocalFact,
            includeFullPayload: Bool,
            imageDataBase64: String?
        ) {
            id = fact.id
            profileID = fact.profileID
            reference = fact.reference
            kind = fact.kind.rawValue
            domainKey = fact.domainKey
            sourceKind = fact.sourceKind
            domainVersion = fact.domainVersion
            title = fact.title
            summary = fact.summary
            payloadJSON = includeFullPayload ? fact.payloadJSON : "{}"
            businessDate = fact.businessDate
            recordTime = fact.recordTime
            occurredAt = fact.occurredAt
            note = fact.note
            imagePath = fact.imagePath
            imageHash = fact.imageHash
            self.imageDataBase64 = imageDataBase64
            localVersion = fact.localVersion
            createdAt = fact.createdAt
            updatedAt = fact.updatedAt
        }
    }
}

final class LocalFactPortability {
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
        let profileID: UUID = try database.writer.read { db in
            guard let profileIDString = try String.fetchOne(
                db,
                sql: "SELECT id FROM local_profiles ORDER BY created_at ASC, id ASC LIMIT 1"
            ), let profileID = UUID(uuidString: profileIDString) else {
                throw LocalDataError.invalidIdentifier
            }
            return profileID
        }
        let dateRange = Self.dateRange(for: request.range, now: exportedAt)
        let reader = try LocalFactReader(database: database)
        let month = try reader.range(
            profileID: profileID,
            from: dateRange.start,
            to: dateRange.end
        )
        let facts = month.facts.map { fact in
            LocalFactArchive.Fact(
                fact: fact,
                includeFullPayload: request.includeFullPayload,
                imageDataBase64: Self.imageData(
                    for: fact,
                    request: request,
                    imageStore: imageStore
                )
            )
        }
        return try Self.encode(
            LocalFactArchive(
                format: LocalFactArchive.currentFormat,
                schemaVersion: LocalFactArchive.currentSchemaVersion,
                exportedAt: exportedAt,
                profileID: profileID,
                facts: facts
            ),
            format: request.format
        )
    }

    private static func imageData(
        for fact: LocalFact,
        request: NativeDataExportRequest,
        imageStore: LocalImageStore?
    ) -> String? {
        guard request.includeImages,
              let imagePath = fact.imagePath,
              let imageStore,
              let data = try? Data(contentsOf: imageStore.url(for: imagePath)) else {
            return nil
        }
        return data.base64EncodedString()
    }

    private static func encode(
        _ archive: LocalFactArchive,
        format: NativeExportFormat
    ) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(archive)
        case .csv:
            var lines = [
                "id,profile_id,reference,kind,domain_key,source_kind,domain_version,title,summary,business_date,record_time,occurred_at,note,image_path,image_hash,image_data_base64,payload_json"
            ]
            for fact in archive.facts {
                lines.append([
                    fact.id.uuidString,
                    fact.profileID.uuidString,
                    fact.reference,
                    fact.kind,
                    fact.domainKey,
                    fact.sourceKind,
                    fact.domainVersion,
                    fact.title,
                    fact.summary,
                    fact.businessDate,
                    fact.recordTime ?? "",
                    fact.occurredAt ?? "",
                    fact.note ?? "",
                    fact.imagePath ?? "",
                    fact.imageHash ?? "",
                    fact.imageDataBase64 ?? "",
                    fact.payloadJSON
                ].map(csvField).joined(separator: ","))
            }
            return Data(lines.joined(separator: "\n").utf8)
        }
    }

    private static func csvField(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func dateRange(
        for range: NativeExportRange,
        now: Date
    ) -> (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let today = NativeLocalDate.dateKey(now)
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) ?? now
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
