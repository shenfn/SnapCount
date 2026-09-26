import Foundation
import XCTest
@testable import SnapCount

final class LocalImageRecognitionTests: XCTestCase {
    func testLOCALP1SPORT001JHighConfidenceCompleteImageBecomesLocalFormalFact() async throws {
        let context = try makeContext()
        defer { cleanup(context) }

        let imageData = Data("j-high-confidence-image".utf8)
        let provider = StubLocalImageRecognitionProvider(candidate: makeCandidate(
            id: "hosted-candidate-high",
            confidence: 0.93,
            payload: [
                "sport_type": AnyCodable("跑步"),
                "duration_minutes": AnyCodable(35)
            ],
            missingFields: []
        ))
        let useCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            provider: provider
        )

        let outcome = try await useCase.ingest(
            imageData: imageData,
            captureKind: "camera",
            filename: "camera.jpg"
        )

        guard case let .archived(recordOutcome) = outcome.result else {
            return XCTFail("高置信度且字段完整的候选必须直接成为正式本地事实")
        }
        XCTAssertEqual(recordOutcome.record.sourceKind, .aiAutoArchive)
        XCTAssertEqual(recordOutcome.record.domainKey, "sport")
        XCTAssertEqual(recordOutcome.record.imageHash, outcome.imageHash)
        XCTAssertTrue(recordOutcome.record.imagePath?.hasPrefix("records/") == true)
        XCTAssertTrue(context.imageStore.contains(path: recordOutcome.record.imagePath))
        let formalRecords = try await context.useCase.records(monthKey: "2026-09")
        let stagingRecords = try await context.useCase.stagingRecords()
        XCTAssertEqual(formalRecords.count, 1)
        XCTAssertTrue(stagingRecords.isEmpty)
    }

    func testLOCALP1SPORT001JLowConfidenceImageBecomesLocalStaging() async throws {
        let context = try makeContext()
        defer { cleanup(context) }

        let provider = StubLocalImageRecognitionProvider(candidate: makeCandidate(
            id: "hosted-candidate-low",
            confidence: 0.62,
            payload: [
                "sport_type": AnyCodable("骑行"),
                "duration_minutes": AnyCodable(40)
            ],
            missingFields: []
        ))
        let useCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            provider: provider
        )

        let outcome = try await useCase.ingest(
            imageData: Data("j-low-confidence-image".utf8),
            captureKind: "photo_library",
            filename: "library.jpg"
        )

        guard case let .staged(stagedOutcome) = outcome.result else {
            return XCTFail("低置信度候选必须进入本地中转站")
        }
        XCTAssertEqual(stagedOutcome.record.status, .pendingReview)
        XCTAssertEqual(stagedOutcome.record.sourceKind, .aiCandidate)
        XCTAssertEqual(stagedOutcome.record.confidence, 0.62)
        XCTAssertEqual(Set(stagedOutcome.record.evidenceFields), Set(["sport_type", "duration_minutes"]))
        XCTAssertTrue(stagedOutcome.record.imagePath?.hasPrefix("staging/") == true)
        let formalRecords = try await context.useCase.records(monthKey: "2026-09")
        XCTAssertTrue(formalRecords.isEmpty)
    }

    func testLOCALP1SPORT001JHighConfidenceMissingKeyFieldStillBecomesLocalStaging() async throws {
        let context = try makeContext()
        defer { cleanup(context) }

        let provider = StubLocalImageRecognitionProvider(candidate: makeCandidate(
            id: "hosted-candidate-incomplete",
            confidence: 0.97,
            payload: ["sport_type": AnyCodable("游泳")],
            missingFields: ["duration_minutes"]
        ))
        let useCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            provider: provider
        )

        let outcome = try await useCase.ingest(
            imageData: Data("j-incomplete-image".utf8),
            captureKind: "camera",
            filename: "camera.jpg"
        )

        guard case let .staged(stagedOutcome) = outcome.result else {
            return XCTFail("关键字段不完整时，即使置信度高也必须进入本地中转站")
        }
        XCTAssertEqual(stagedOutcome.record.missingFields, ["duration_minutes"])
        XCTAssertEqual(stagedOutcome.record.confidence, 0.97)
        let formalRecords = try await context.useCase.records(monthKey: "2026-09")
        XCTAssertTrue(formalRecords.isEmpty)
    }

    func testLOCALP1SPORT001JImageSaveFailureDoesNotCreateDatabaseOnlyHalfRecord() async throws {
        let databaseURL = temporaryDatabaseURL()
        let imageDirectory = temporaryDirectoryURL()
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try Data("not-a-directory".utf8).write(to: imageDirectory.appendingPathComponent("intake"))
        defer {
            try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: imageDirectory)
        }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = try LocalImageStore(rootDirectory: imageDirectory)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database),
            imageStore: store
        )
        let recognition = LocalImageRecognitionUseCase(
            localRecordUseCase: useCase,
            imageStore: store,
            provider: StubLocalImageRecognitionProvider(candidate: makeCandidate())
        )

        do {
            _ = try await recognition.ingest(
                imageData: Data("j-image-save-failure".utf8),
                captureKind: "camera",
                filename: "camera.jpg"
            )
            XCTFail("图片保存失败应在调用识别和写库前失败")
        } catch {
            XCTAssertTrue(error is LocalDataError || error is CocoaError)
        }

        let profile = try LocalProfileStore(database: database).activeProfile()
        let formalRecords = try LocalRecordRepository(database: database).records(profileID: profile.id, monthKey: "2026-09")
        let stagingRecords = try LocalRecordRepository(database: database).stagingRecords(profileID: profile.id)
        XCTAssertTrue(formalRecords.isEmpty)
        XCTAssertTrue(stagingRecords.isEmpty)
    }

    func testLOCALP1SPORT001JProviderFailureCleansTheLocalIntakeImageWithoutDatabaseRow() async throws {
        let context = try makeContext()
        defer { cleanup(context) }

        let recognition = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            provider: StubLocalImageRecognitionProvider(error: StubProviderError.failed)
        )

        do {
            _ = try await recognition.ingest(
                imageData: Data("j-provider-failure-image".utf8),
                captureKind: "camera",
                filename: "camera.jpg"
            )
            XCTFail("识别失败应向调用方返回错误")
        } catch {
            XCTAssertEqual(error as? StubProviderError, .failed)
        }

        let profile = try LocalProfileStore(database: context.database).activeProfile()
        let formalRecords = try await context.useCase.records(monthKey: "2026-09")
        let stagingRecords = try await context.useCase.stagingRecords()
        XCTAssertTrue(formalRecords.isEmpty)
        XCTAssertTrue(stagingRecords.isEmpty)
        XCTAssertFalse(context.imageStore.contains(path: "intake/anything.jpg"))
        let persistedRecords = try LocalRecordRepository(database: context.database).records(profileID: profile.id, monthKey: "2026-09")
        XCTAssertEqual(persistedRecords.count, 0)
    }

    func testLOCALP1SPORT001JRetryingTheSameImageDoesNotCreateDuplicateFormalFacts() async throws {
        let context = try makeContext()
        defer { cleanup(context) }

        let candidate = makeCandidate(
            id: "provider-generated-id-can-change",
            confidence: 0.91,
            payload: [
                "sport_type": AnyCodable("力量训练"),
                "duration_minutes": AnyCodable(50)
            ],
            missingFields: []
        )
        let provider = StubLocalImageRecognitionProvider(candidate: candidate)
        let useCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            provider: provider
        )

        let first = try await useCase.ingest(
            imageData: Data("j-retry-idempotent-image".utf8),
            captureKind: "camera",
            filename: "camera.jpg"
        )
        let second = try await useCase.ingest(
            imageData: Data("j-retry-idempotent-image".utf8),
            captureKind: "camera",
            filename: "camera.jpg"
        )

        guard case let .archived(firstArchived) = first.result,
              case let .archived(secondArchived) = second.result else {
            return XCTFail("同一图片重试应保持高置信度自动归档结果")
        }
        XCTAssertEqual(firstArchived.record.id, secondArchived.record.id)
        let formalRecords = try await context.useCase.records(monthKey: "2026-09")
        let stagingRecords = try await context.useCase.stagingRecords()
        XCTAssertEqual(formalRecords.count, 1)
        XCTAssertTrue(stagingRecords.isEmpty)
    }

    private func makeCandidate(
        id: String = "hosted-candidate",
        confidence: Double = 0.9,
        payload: [String: AnyCodable] = [
            "sport_type": AnyCodable("跑步"),
            "duration_minutes": AnyCodable(30)
        ],
        missingFields: [String] = []
    ) -> LocalRecognitionCandidate {
        LocalRecognitionCandidate(
            id: id,
            domainKey: "sport",
            title: "运动记录",
            summary: "AI 图片识别",
            payload: payload,
            confidence: confidence,
            recordDate: "2026-09-20",
            recordTime: "08:30",
            occurredAt: "2026-09-20T08:30:00+08:00",
            evidenceFields: Array(payload.keys).sorted(),
            missingFields: missingFields,
            imageHash: nil
        )
    }

    private func makeContext() throws -> TestContext {
        let databaseURL = temporaryDatabaseURL()
        let imageDirectory = temporaryDirectoryURL()
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = try LocalImageStore(rootDirectory: imageDirectory)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database),
            imageStore: store
        )
        return TestContext(
            database: database,
            databaseURL: databaseURL,
            imageDirectory: imageDirectory,
            imageStore: store,
            useCase: useCase
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-image-recognition-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jiezi.sqlite")
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-image-recognition-images-\(UUID().uuidString)", isDirectory: true)
    }

    private func cleanup(_ context: TestContext) {
        try? FileManager.default.removeItem(at: context.databaseURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: context.imageDirectory)
    }

    private struct TestContext {
        let database: LocalDatabase
        let databaseURL: URL
        let imageDirectory: URL
        let imageStore: LocalImageStore
        let useCase: LocalRecordUseCase
    }
}

private final class StubLocalImageRecognitionProvider: LocalImageRecognitionProvider {
    let candidate: LocalRecognitionCandidate?
    let failure: Error?

    init(candidate: LocalRecognitionCandidate) {
        self.candidate = candidate
        self.failure = nil
    }

    init(error: Error) {
        self.candidate = nil
        self.failure = error
    }

    func recognize(_ request: LocalImageRecognitionRequest) async throws -> LocalRecognitionCandidate {
        if let failure { throw failure }
        guard let candidate else { throw StubProviderError.missingCandidate }
        return candidate
    }
}

private enum StubProviderError: Error, Equatable {
    case failed
    case missingCandidate
}
