import Foundation

enum LocalImageRecognitionError: Error, Equatable, LocalizedError {
    case invalidCandidate
    case unsupportedDomain(String)
    case missingUploadCredential

    var errorDescription: String? {
        switch self {
        case .invalidCandidate:
            return "AI 返回的图片识别候选无效"
        case .unsupportedDomain(let domainKey):
            return "本地首片暂不支持数据域：\(domainKey)"
        case .missingUploadCredential:
            return "当前没有可用的 Hosted AI 凭据"
        }
    }
}

struct LocalImageRecognitionRequest {
    let imageData: Data
    let captureKind: String
    let filename: String
    let uploadToken: String?
}

struct LocalRecognitionCandidate {
    let id: String
    let domainKey: String
    let title: String
    let summary: String
    let payload: [String: AnyCodable]
    let confidence: Double?
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let evidenceFields: [String]
    let missingFields: [String]
    let imageHash: String?
}

protocol LocalImageRecognitionProvider {
    func recognize(_ request: LocalImageRecognitionRequest) async throws -> LocalRecognitionCandidate
}

struct LocalImageIntakeOutcome: Equatable {
    let result: LocalRecordIntakeOutcome
    let imageHash: String
}

final class LocalImageRecognitionUseCase {
    private let localRecordUseCase: LocalRecordUseCaseProtocol
    private let imageStore: LocalImageStore
    private let provider: LocalImageRecognitionProvider

    init(
        localRecordUseCase: LocalRecordUseCaseProtocol,
        imageStore: LocalImageStore,
        provider: LocalImageRecognitionProvider
    ) {
        self.localRecordUseCase = localRecordUseCase
        self.imageStore = imageStore
        self.provider = provider
    }

    static func makeDefault(provider: LocalImageRecognitionProvider) throws -> LocalImageRecognitionUseCase {
        let database = try LocalDatabase()
        let imageStore = try LocalImageStore()
        let repository = try LocalRecordRepository(database: database)
        let recordUseCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: repository,
            imageStore: imageStore
        )
        return LocalImageRecognitionUseCase(
            localRecordUseCase: recordUseCase,
            imageStore: imageStore,
            provider: provider
        )
    }

    func ingest(
        imageData: Data,
        captureKind: String,
        filename: String,
        uploadToken: String? = nil,
        createdAt: Date = Date()
    ) async throws -> LocalImageIntakeOutcome {
        let imageHash = LocalImageStore.sha256(imageData)
        let intakeReference = try imageStore.save(
            data: imageData,
            owner: "recognition-\(imageHash)",
            bucket: "intake"
        )
        defer { try? imageStore.remove(path: intakeReference.path) }

        let recognized = try await provider.recognize(LocalImageRecognitionRequest(
            imageData: imageData,
            captureKind: captureKind,
            filename: filename,
            uploadToken: uploadToken
        ))
        guard !recognized.domainKey.isEmpty,
              !recognized.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !recognized.recordDate.isEmpty,
              LocalRecordValidation.supportedDomainKeys.contains(recognized.domainKey) else {
            throw LocalImageRecognitionError.unsupportedDomain(recognized.domainKey)
        }

        let candidate = LocalRecordCandidate(
            id: "local-ai-\(imageHash)",
            domainKey: recognized.domainKey,
            title: recognized.title,
            summary: recognized.summary,
            payload: recognized.payload,
            confidence: recognized.confidence,
            recordDate: recognized.recordDate,
            recordTime: recognized.recordTime,
            imageData: nil,
            createdAt: createdAt,
            imageReference: intakeReference,
            evidenceFields: recognized.evidenceFields,
            missingFields: recognized.missingFields
        )
        let recordID = Self.uuidFromHash(imageHash)
        let result = try await localRecordUseCase.ingest(candidate, recordID: recordID)
        return LocalImageIntakeOutcome(result: result, imageHash: imageHash)
    }

    private static func uuidFromHash(_ hash: String) -> UUID {
        let hex = Array(hash.prefix(32))
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<min(16, hex.count / 2) {
            let start = index * 2
            bytes[index] = UInt8(String(hex[start...(start + 1)]), radix: 16) ?? 0
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

final class HostedAIImageRecognitionProvider: LocalImageRecognitionProvider {
    private let uploadService: SnapCountUploadService
    private let decoder = JSONDecoder()

    init(uploadService: SnapCountUploadService = SnapCountUploadService()) {
        self.uploadService = uploadService
    }

    func recognize(_ request: LocalImageRecognitionRequest) async throws -> LocalRecognitionCandidate {
        let responseData = try await uploadService.recognizeNativeImage(
            data: request.imageData,
            uploadToken: request.uploadToken,
            captureKind: request.captureKind,
            filename: request.filename,
            mimeType: "image/jpeg"
        )
        let envelope = try decoder.decode(HostedAIRecognitionEnvelope.self, from: responseData)
        guard envelope.operation == "recognize_only", envelope.schemaVersion == "local-recognition-candidate-v1",
              let candidate = envelope.candidate,
              let domainKey = candidate.domainKey,
              let title = candidate.title,
              let summary = candidate.summary,
              let recordDate = candidate.recordDate else {
            throw LocalImageRecognitionError.invalidCandidate
        }
        return LocalRecognitionCandidate(
            id: candidate.id ?? UUID().uuidString,
            domainKey: domainKey,
            title: title,
            summary: summary,
            payload: candidate.payload ?? [:],
            confidence: candidate.confidence,
            recordDate: recordDate,
            recordTime: candidate.recordTime,
            occurredAt: candidate.occurredAt,
            evidenceFields: candidate.evidenceFields ?? [],
            missingFields: candidate.missingFields ?? [],
            imageHash: candidate.imageHash
        )
    }
}

private struct HostedAIRecognitionEnvelope: Decodable {
    let schemaVersion: String?
    let operation: String?
    let candidate: HostedAIRecognitionCandidate?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case operation
        case candidate
    }
}

private struct HostedAIRecognitionCandidate: Decodable {
    let id: String?
    let domainKey: String?
    let title: String?
    let summary: String?
    let payload: [String: AnyCodable]?
    let confidence: Double?
    let recordDate: String?
    let recordTime: String?
    let occurredAt: String?
    let evidenceFields: [String]?
    let missingFields: [String]?
    let imageHash: String?

    enum CodingKeys: String, CodingKey {
        case id
        case domainKey = "domain_key"
        case title
        case summary
        case payload
        case confidence
        case recordDate = "record_date"
        case recordTime = "record_time"
        case occurredAt = "occurred_at"
        case evidenceFields = "evidence_fields"
        case missingFields = "missing_fields"
        case imageHash = "image_hash"
    }
}
