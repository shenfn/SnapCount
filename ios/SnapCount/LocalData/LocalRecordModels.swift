import Foundation

enum LocalRecordStatus: String, Equatable {
    case active
    case deleted
}

enum LocalStagingRecordStatus: String, Equatable {
    case pendingReview = "pending_review"
    case archived
    case discarded
    case failed
}

enum LocalRecordSourceKind: String, Codable, Equatable {
    case manual
    case aiAutoArchive = "ai_auto_archive"
    case aiCandidate = "ai_candidate"
    case aiConfirmed = "ai_confirmed"
    case imported
}

struct LocalRecordCommand {
    let id: UUID
    let domainKey: String
    let title: String
    let summary: String
    let payload: [String: AnyCodable]
    let recordDate: String
    let recordTime: String?
    let note: String?
    let imageData: Data?
    let imageReference: LocalImageReference?
    let createdAt: Date

    let sourceKind: LocalRecordSourceKind

    init(
        id: UUID,
        domainKey: String,
        title: String,
        summary: String,
        payload: [String: AnyCodable],
        recordDate: String,
        recordTime: String?,
        note: String?,
        imageData: Data?,
        imageReference: LocalImageReference? = nil,
        createdAt: Date,
        sourceKind: LocalRecordSourceKind = .manual
    ) {
        self.id = id
        self.domainKey = domainKey
        self.title = title
        self.summary = summary
        self.payload = payload
        self.recordDate = recordDate
        self.recordTime = recordTime
        self.note = note
        self.imageData = imageData
        self.imageReference = imageReference
        self.createdAt = createdAt
        self.sourceKind = sourceKind
    }
}

struct LocalRecordDraft: Equatable {
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
    let createdAt: Date

    let sourceKind: LocalRecordSourceKind
    let domainVersion: Int

    init(
        id: UUID,
        profileID: UUID,
        domainKey: String,
        title: String,
        summary: String,
        payloadJSON: String,
        recordDate: String,
        recordTime: String?,
        note: String?,
        imagePath: String?,
        imageHash: String?,
        createdAt: Date,
        sourceKind: LocalRecordSourceKind = .manual,
        domainVersion: Int = 1
    ) {
        self.id = id
        self.profileID = profileID
        self.domainKey = domainKey
        self.title = title
        self.summary = summary
        self.payloadJSON = payloadJSON
        self.recordDate = recordDate
        self.recordTime = recordTime
        self.note = note
        self.imagePath = imagePath
        self.imageHash = imageHash
        self.createdAt = createdAt
        self.sourceKind = sourceKind
        self.domainVersion = domainVersion
    }
}

struct LocalRecordUpdateCommand {
    let id: UUID
    let expectedVersion: Int64
    let title: String
    let summary: String
    let payload: [String: AnyCodable]
    let recordDate: String
    let recordTime: String?
    let note: String?
    let updatedAt: Date
}

struct LocalRecordDeleteCommand {
    let id: UUID
    let expectedVersion: Int64
    let deletedAt: Date
}

struct LocalRecord: Equatable {
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
    let sourceKind: LocalRecordSourceKind
    let domainVersion: Int
    let localVersion: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct LocalRecordTombstone: Equatable {
    let id: UUID
    let profileID: UUID
    let localVersion: Int64
    let deletedAt: Date
    let imagePath: String?
}

struct LocalRecordMonth: Equatable {
    let profileID: UUID
    let records: [LocalRecord]
}

struct LocalStagingRecord: Equatable {
    let id: String
    let profileID: UUID
    let domainKey: String
    let status: LocalStagingRecordStatus
    let confidence: Double?
    let evidenceFields: [String] = []
    let missingFields: [String] = []
    let title: String
    let summary: String
    let payloadJSON: String
    let recordDate: String
    let recordTime: String?
    let imagePath: String?
    let imageHash: String?
    let sourceKind: LocalRecordSourceKind
    let domainVersion: Int
    let targetRecordID: UUID?
    let resolvedAction: String?
    let resolvedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        profileID: UUID,
        domainKey: String,
        status: LocalStagingRecordStatus,
        confidence: Double?,
        evidenceFields: [String] = [],
        missingFields: [String] = [],
        title: String,
        summary: String,
        payloadJSON: String,
        recordDate: String,
        recordTime: String?,
        imagePath: String?,
        imageHash: String?,
        sourceKind: LocalRecordSourceKind,
        domainVersion: Int,
        targetRecordID: UUID?,
        resolvedAction: String?,
        resolvedAt: Date?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.profileID = profileID
        self.domainKey = domainKey
        self.status = status
        self.confidence = confidence
        self.evidenceFields = evidenceFields
        self.missingFields = missingFields
        self.title = title
        self.summary = summary
        self.payloadJSON = payloadJSON
        self.recordDate = recordDate
        self.recordTime = recordTime
        self.imagePath = imagePath
        self.imageHash = imageHash
        self.sourceKind = sourceKind
        self.domainVersion = domainVersion
        self.targetRecordID = targetRecordID
        self.resolvedAction = resolvedAction
        self.resolvedAt = resolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LocalRecordCandidate {
    let id: String
    let domainKey: String
    let title: String
    let summary: String
    let payload: [String: AnyCodable]
    let confidence: Double?
    let recordDate: String
    let recordTime: String?
    let imageData: Data?
    let createdAt: Date
    let imageReference: LocalImageReference? = nil
    let evidenceFields: [String] = []
    let missingFields: [String] = []

    init(
        id: String,
        domainKey: String,
        title: String,
        summary: String,
        payload: [String: AnyCodable],
        confidence: Double?,
        recordDate: String,
        recordTime: String?,
        imageData: Data?,
        createdAt: Date,
        imageReference: LocalImageReference? = nil,
        evidenceFields: [String] = [],
        missingFields: [String] = []
    ) {
        self.id = id
        self.domainKey = domainKey
        self.title = title
        self.summary = summary
        self.payload = payload
        self.confidence = confidence
        self.recordDate = recordDate
        self.recordTime = recordTime
        self.imageData = imageData
        self.createdAt = createdAt
        self.imageReference = imageReference
        self.evidenceFields = evidenceFields
        self.missingFields = missingFields
    }
}

struct LocalStagingDraft: Equatable {
    let id: String
    let profileID: UUID
    let domainKey: String
    let status: LocalStagingRecordStatus
    let confidence: Double?
    let evidenceFields: [String]
    let missingFields: [String]
    let title: String
    let summary: String
    let payloadJSON: String
    let recordDate: String
    let recordTime: String?
    let imagePath: String?
    let imageHash: String?
    let createdAt: Date

    let sourceKind: LocalRecordSourceKind
    let domainVersion: Int

    init(
        id: String,
        profileID: UUID,
        domainKey: String,
        status: LocalStagingRecordStatus,
        confidence: Double?,
        evidenceFields: [String] = [],
        missingFields: [String] = [],
        title: String,
        summary: String,
        payloadJSON: String,
        recordDate: String,
        recordTime: String?,
        imagePath: String?,
        imageHash: String?,
        createdAt: Date,
        sourceKind: LocalRecordSourceKind = .aiCandidate,
        domainVersion: Int = 1
    ) {
        self.id = id
        self.profileID = profileID
        self.domainKey = domainKey
        self.status = status
        self.confidence = confidence
        self.evidenceFields = evidenceFields
        self.missingFields = missingFields
        self.title = title
        self.summary = summary
        self.payloadJSON = payloadJSON
        self.recordDate = recordDate
        self.recordTime = recordTime
        self.imagePath = imagePath
        self.imageHash = imageHash
        self.createdAt = createdAt
        self.sourceKind = sourceKind
        self.domainVersion = domainVersion
    }
}

struct LocalRecordOutcome: Equatable {
    let record: LocalRecord
    let profileID: UUID
}

struct LocalRecordDeleteOutcome: Equatable {
    let tombstone: LocalRecordTombstone
    let profileID: UUID
}

struct LocalStagingOutcome: Equatable {
    let record: LocalStagingRecord
    let profileID: UUID
}

enum LocalRecordIntakeOutcome: Equatable {
    case archived(LocalRecordOutcome)
    case staged(LocalStagingOutcome)
}

enum LocalRecordIntakeRoute: Equatable {
    case autoArchive
    case staging
}

enum LocalRecordIntakeRouter {
    static let fallbackAutoArchiveConfidence = 0.80

    private static let domainThresholds: [String: Double] = [
        "food": 0.80,
        "sleep": 0.75,
        "sport": 0.75,
        "reading": 0.75
    ]

    static func route(confidence: Double?) -> LocalRecordIntakeRoute {
        guard let confidence, confidence >= fallbackAutoArchiveConfidence else { return .staging }
        return .autoArchive
    }

    static func route(
        domainKey: String,
        confidence: Double?,
        payload: [String: AnyCodable]
    ) -> LocalRecordIntakeRoute {
        let threshold = domainThresholds[domainKey] ?? fallbackAutoArchiveConfidence
        guard let confidence, confidence >= threshold else { return .staging }
        guard (try? LocalRecordCodec.normalizedPayload(domainKey: domainKey, payload: payload)) != nil else {
            return .staging
        }
        return .autoArchive
    }
}

enum LocalRecordCodec {
    static func encode(_ payload: [String: AnyCodable]) throws -> String {
        let data = try JSONEncoder().encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw LocalDataError.invalidRecord
        }
        return string
    }

    static func decode(_ json: String) throws -> [String: AnyCodable] {
        guard let data = json.data(using: .utf8) else { throw LocalDataError.invalidRecord }
        return try JSONDecoder().decode([String: AnyCodable].self, from: data)
    }

    static func normalizedPayload(
        domainKey: String,
        payload: [String: AnyCodable],
        requireFacts: Bool = true
    ) throws -> [String: AnyCodable] {
        guard LocalRecordValidation.supportedDomainKeys.contains(domainKey) else {
            throw LocalDataError.invalidRecord
        }

        var normalized = payload
        switch domainKey {
        case "food":
            let mealType = textValue(normalized["meal_type"])
            let calories = numberValue(normalized["total_calorie_kcal"])
            let hasDishes = arrayValue(normalized["dishes"])?.isEmpty == false
            if requireFacts && (mealType == nil || (calories == nil && !hasDishes)) {
                throw LocalDataError.invalidRecord
            }
        case "sleep":
            if let minutes = numberValue(normalized["sleep_minutes"]) {
                normalized["sleep_minutes"] = AnyCodable(Int(minutes.rounded()))
            } else if let hours = numberValue(normalized["sleep_hours"]) {
                normalized["sleep_minutes"] = AnyCodable(Int((hours * 60).rounded()))
            }
            normalized.removeValue(forKey: "sleep_hours")
            if requireFacts && positiveNumber(normalized["sleep_minutes"]) == nil {
                throw LocalDataError.invalidRecord
            }
        case "sport":
            if normalized["duration_minutes"] == nil {
                normalized["duration_minutes"] = normalized["duration_min"] ?? normalized["duration"]
            }
            if requireFacts {
                guard textValue(normalized["sport_type"]) != nil,
                      positiveNumber(normalized["duration_minutes"]) != nil else {
                    throw LocalDataError.invalidRecord
                }
            }
        case "reading":
            if normalized["reading_minutes"] == nil {
                normalized["reading_minutes"] = normalized["duration_min"] ?? normalized["duration"]
            }
            if requireFacts {
                guard textValue(normalized["book_name"]) != nil,
                      positiveNumber(normalized["reading_minutes"]) != nil else {
                    throw LocalDataError.invalidRecord
                }
            }
        default:
            throw LocalDataError.invalidRecord
        }
        return normalized
    }

    private static func textValue(_ value: AnyCodable?) -> String? {
        guard let string = value?.value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func numberValue(_ value: AnyCodable?) -> Double? {
        switch value?.value {
        case let value as Double: return value.isFinite ? value : nil
        case let value as Float: return value.isFinite ? Double(value) : nil
        case let value as Int: return Double(value)
        case let value as Int64: return Double(value)
        case let value as NSNumber: return value.doubleValue.isFinite ? value.doubleValue : nil
        case let value as String: return Double(value)
        default: return nil
        }
    }

    private static func positiveNumber(_ value: AnyCodable?) -> Double? {
        guard let number = numberValue(value), number > 0 else { return nil }
        return number
    }

    private static func arrayValue(_ value: AnyCodable?) -> [Any]? {
        value?.value as? [Any]
    }
}

enum LocalRecordValidation {
    static let supportedDomainKeys: Set<String> = ["food", "sleep", "sport", "reading"]

    static func validate(
        domainKey: String,
        title: String,
        recordDate: String,
        recordTime: String? = nil
    ) throws {
        guard supportedDomainKeys.contains(domainKey) else { throw LocalDataError.invalidRecord }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalDataError.invalidRecord
        }
        guard recordDate.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            throw LocalDataError.invalidRecord
        }
        if let recordTime {
            guard recordTime.range(
                of: #"^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$"#,
                options: .regularExpression
            ) != nil else {
                throw LocalDataError.invalidRecord
            }
        }
    }
}
