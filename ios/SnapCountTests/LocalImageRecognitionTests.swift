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
            intakeRepository: context.intakeRepository,
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
        let profile = try context.intakeRepository.activeProfile()
        let intakeID = "\(profile.id.uuidString)-\(outcome.imageHash)"
        let intake = try XCTUnwrap(context.intakeRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertEqual(intake.status, .completed)
        XCTAssertFalse(context.imageStore.contains(path: intake.imagePath))
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
            intakeRepository: context.intakeRepository,
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
            intakeRepository: context.intakeRepository,
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
            intakeRepository: LocalImageIntakeRepository(database: database),
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

    @MainActor
    func testLF03602ProviderFailureKeepsImageAndFailureAcrossDatabaseReopen() async throws {
        let context = try makeContext()
        defer { cleanup(context) }

        let recognition = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            intakeRepository: context.intakeRepository,
            provider: StubLocalImageRecognitionProvider(error: StubProviderError.failed)
        )

        let imageData = Data("j-provider-failure-image".utf8)
        do {
            _ = try await recognition.ingest(
                imageData: imageData,
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
        let intakeID = "\(profile.id.uuidString)-\(LocalImageStore.sha256(imageData))"
        let intake = try XCTUnwrap(context.intakeRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertEqual(intake.status, .failed)
        XCTAssertEqual(intake.attemptCount, 1)
        XCTAssertNotNil(intake.failureMessage)
        XCTAssertEqual(try context.imageStore.data(at: intake.imagePath), imageData)

        let reopenedDatabase = try LocalDatabase(databaseURL: context.databaseURL)
        let reopenedRepository = LocalImageIntakeRepository(database: reopenedDatabase)
        let reopenedIntake = try XCTUnwrap(reopenedRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertEqual(reopenedIntake.status, .failed)
        XCTAssertEqual(try context.imageStore.data(at: reopenedIntake.imagePath), imageData)

        let appState = AppState(
            localRecordUseCase: context.useCase,
            localImageStore: context.imageStore,
            localImageIntakeRepository: reopenedRepository
        )
        await appState.refreshFailedLocalImageIntakes()
        XCTAssertEqual(appState.failedLocalImageIntakes.map(\.id), [intakeID])
    }

    func testLF00701RetryUsesSameIntakeAndStoresRetryCount() async throws {
        let context = try makeContext()
        defer { cleanup(context) }
        let imageData = Data("lf007-retry-stable-image".utf8)
        let firstUseCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            intakeRepository: context.intakeRepository,
            provider: StubLocalImageRecognitionProvider(error: StubProviderError.failed)
        )
        do {
            _ = try await firstUseCase.ingest(imageData: imageData, captureKind: "camera", filename: "retry.jpg")
            XCTFail("首次识别失败应保留为可重试输入")
        } catch {
            XCTAssertEqual(error as? StubProviderError, .failed)
        }

        let profile = try context.intakeRepository.activeProfile()
        let intakeID = "\(profile.id.uuidString)-\(LocalImageStore.sha256(imageData))"
        let retryUseCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            intakeRepository: context.intakeRepository,
            provider: StubLocalImageRecognitionProvider(candidate: makeCandidate())
        )
        let retried = try await retryUseCase.retry(intakeID: intakeID)
        guard case .archived = retried.result else {
            return XCTFail("重试成功应复用稳定记录身份并落本地事实")
        }
        let intake = try XCTUnwrap(context.intakeRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertEqual(intake.status, .completed)
        XCTAssertEqual(intake.retryCount, 1)
        XCTAssertEqual(intake.attemptCount, 2)
        XCTAssertFalse(context.imageStore.contains(path: intake.imagePath))
        let records = try await context.useCase.records(monthKey: "2026-09")
        XCTAssertEqual(records.count, 1)
    }

    func testLF00702ThreeRetriesKeepManualAndDiscardExit() async throws {
        let context = try makeContext()
        defer { cleanup(context) }
        let imageData = Data("lf007-retry-limit-image".utf8)
        let failedUseCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            intakeRepository: context.intakeRepository,
            provider: StubLocalImageRecognitionProvider(error: StubProviderError.failed)
        )
        do {
            _ = try await failedUseCase.ingest(imageData: imageData, captureKind: "camera", filename: "limit.jpg")
            XCTFail("首次识别应失败并创建可重试输入")
        } catch {
            XCTAssertEqual(error as? StubProviderError, .failed)
        }
        let profile = try context.intakeRepository.activeProfile()
        let intakeID = "\(profile.id.uuidString)-\(LocalImageStore.sha256(imageData))"
        for _ in 0..<3 {
            do { _ = try await failedUseCase.retry(intakeID: intakeID) }
            catch { XCTAssertEqual(error as? StubProviderError, .failed) }
        }
        do {
            _ = try await failedUseCase.retry(intakeID: intakeID)
            XCTFail("第四次重试请求应被拒绝")
        } catch {
            XCTAssertEqual(error as? LocalImageRecognitionError, .retryLimitReached)
        }
        let intake = try XCTUnwrap(context.intakeRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertEqual(intake.retryCount, 3)
        XCTAssertTrue(context.imageStore.contains(path: intake.imagePath))
        XCTAssertEqual(try context.imageStore.data(at: intake.imagePath), imageData)
    }

    func testLF03604UnsupportedDomainRemainsLocalAndDoesNotCreateBusinessFact() async throws {
        let context = try makeContext()
        defer { cleanup(context) }
        let imageData = Data("lf036-unsupported-domain".utf8)
        let useCase = LocalImageRecognitionUseCase(
            localRecordUseCase: context.useCase,
            imageStore: context.imageStore,
            intakeRepository: context.intakeRepository,
            provider: StubLocalImageRecognitionProvider(candidate: makeCandidate(domainKey: "wallet"))
        )
        do {
            _ = try await useCase.ingest(imageData: imageData, captureKind: "camera", filename: "wallet.jpg")
            XCTFail("当前本地不支持的候选必须进入失败输入状态")
        } catch {
            XCTAssertEqual(error as? LocalImageRecognitionError, .unsupportedDomain("wallet"))
        }

        let profile = try context.intakeRepository.activeProfile()
        let intakeID = "\(profile.id.uuidString)-\(LocalImageStore.sha256(imageData))"
        let intake = try XCTUnwrap(context.intakeRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertEqual(intake.status, .failed)
        XCTAssertEqual(intake.failureMessage, "本地暂不支持数据域：wallet")
        XCTAssertEqual(try context.imageStore.data(at: intake.imagePath), imageData)
        let records = try await context.useCase.records(monthKey: "2026-09")
        let staging = try await context.useCase.stagingRecords()
        XCTAssertTrue(records.isEmpty)
        XCTAssertTrue(staging.isEmpty)
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
            intakeRepository: context.intakeRepository,
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
        XCTAssertEqual(provider.callCount, 1, "已完成的相同图片应复用本地目标，不再次请求识别")
        let formalRecords = try await context.useCase.records(monthKey: "2026-09")
        let stagingRecords = try await context.useCase.stagingRecords()
        XCTAssertEqual(formalRecords.count, 1)
        XCTAssertTrue(stagingRecords.isEmpty)
    }

    @MainActor
    func testLF00803ImageIntakeClaimIsExclusiveAndInterruptedClaimCanBeRecovered() async throws {
        let context = try makeContext()
        defer { cleanup(context) }
        let profile = try context.intakeRepository.activeProfile()
        let imageData = Data("lf008-exclusive-image".utf8)
        let hash = LocalImageStore.sha256(imageData)
        let intakeID = "\(profile.id.uuidString)-\(hash)"
        let image = try context.imageStore.save(data: imageData, owner: intakeID, bucket: "intake")
        let startedAt = Date()
        let firstOperation = try context.intakeRepository.beginAttempt(
            id: intakeID,
            profileID: profile.id,
            captureKind: "camera",
            filename: "claim.jpg",
            imagePath: image.path,
            imageHash: hash,
            at: startedAt
        )
        let appState = AppState(
            localRecordUseCase: context.useCase,
            localImageStore: context.imageStore,
            localImageIntakeRepository: context.intakeRepository
        )
        await appState.refreshFailedLocalImageIntakes()
        XCTAssertEqual(appState.failedLocalImageIntakes.first?.status, .receiving)

        XCTAssertThrowsError(try context.intakeRepository.beginAttempt(
            id: intakeID,
            profileID: profile.id,
            captureKind: "camera",
            filename: "claim.jpg",
            imagePath: image.path,
            imageHash: hash,
            at: Date()
        )) { XCTAssertEqual($0 as? LocalImageRecognitionError, .alreadyInProgress) }
        XCTAssertEqual(try context.intakeRepository.intake(id: intakeID, profileID: profile.id)?.attemptCount, 1)
        XCTAssertTrue(try context.intakeRepository.isReceiving(
            id: intakeID, profileID: profile.id, operationID: firstOperation
        ))

        try context.database.writer.write { db in
            try db.execute(
                sql: "UPDATE local_image_intakes SET updated_at = ? WHERE id = ?",
                arguments: [Date().addingTimeInterval(-600), intakeID]
            )
        }
        try context.intakeRepository.recoverInterrupted(profileID: profile.id, before: Date().addingTimeInterval(-120))
        XCTAssertEqual(try context.intakeRepository.intake(id: intakeID, profileID: profile.id)?.status, .failed)
        let recoveredOperation = try context.intakeRepository.beginAttempt(
            id: intakeID,
            profileID: profile.id,
            captureKind: "camera",
            filename: "claim.jpg",
            imagePath: image.path,
            imageHash: hash,
            at: Date()
        )
        XCTAssertNotEqual(recoveredOperation, firstOperation)
        XCTAssertFalse(try context.intakeRepository.isReceiving(
            id: intakeID, profileID: profile.id, operationID: firstOperation
        ))
        XCTAssertTrue(try context.intakeRepository.isReceiving(
            id: intakeID, profileID: profile.id, operationID: recoveredOperation
        ))
        XCTAssertEqual(try context.intakeRepository.intake(id: intakeID, profileID: profile.id)?.attemptCount, 2)
    }

    func testLF00804DiscardQueuesAndCleansImageWithoutDroppingFailureStateFirst() throws {
        let context = try makeContext()
        defer { cleanup(context) }
        let profile = try context.intakeRepository.activeProfile()
        let imageData = Data("lf008-discard-image".utf8)
        let hash = LocalImageStore.sha256(imageData)
        let intakeID = "\(profile.id.uuidString)-\(hash)"
        let image = try context.imageStore.save(data: imageData, owner: intakeID, bucket: "intake")
        let operationID = try context.intakeRepository.beginAttempt(
            id: intakeID,
            profileID: profile.id,
            captureKind: "camera",
            filename: "discard.jpg",
            imagePath: image.path,
            imageHash: hash,
            at: Date()
        )
        XCTAssertThrowsError(try context.intakeRepository.discard(id: intakeID, profileID: profile.id))
        XCTAssertTrue(context.imageStore.contains(path: image.path))
        try context.intakeRepository.markFailed(
            id: intakeID,
            profileID: profile.id,
            operationID: operationID,
            message: "synthetic failure",
            at: Date()
        )

        try context.intakeRepository.discard(id: intakeID, profileID: profile.id)
        XCTAssertNil(try context.intakeRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertTrue(context.imageStore.contains(path: image.path))
        XCTAssertEqual(try LocalRecordRepository(database: context.database).pendingImageCleanups(profileID: profile.id).map(\.imagePath), [image.path])

        let pending = try context.useCase.retryPendingImageCleanups()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertFalse(context.imageStore.contains(path: image.path))
    }

    private func makeCandidate(
        id: String = "hosted-candidate",
        domainKey: String = "sport",
        confidence: Double = 0.9,
        payload: [String: AnyCodable] = [
            "sport_type": AnyCodable("跑步"),
            "duration_minutes": AnyCodable(30)
        ],
        missingFields: [String] = []
    ) -> LocalRecognitionCandidate {
        LocalRecognitionCandidate(
            id: id,
            domainKey: domainKey,
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
        let intakeRepository = LocalImageIntakeRepository(database: database)
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
            intakeRepository: intakeRepository,
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
        let intakeRepository: LocalImageIntakeRepository
        let useCase: LocalRecordUseCase
    }
}

private final class StubLocalImageRecognitionProvider: LocalImageRecognitionProvider {
    let candidate: LocalRecognitionCandidate?
    let failure: Error?
    private(set) var callCount = 0

    init(candidate: LocalRecognitionCandidate) {
        self.candidate = candidate
        self.failure = nil
    }

    init(error: Error) {
        self.candidate = nil
        self.failure = error
    }

    func recognize(_ request: LocalImageRecognitionRequest) async throws -> LocalRecognitionCandidate {
        callCount += 1
        if let failure { throw failure }
        guard let candidate else { throw StubProviderError.missingCandidate }
        return candidate
    }
}

private enum StubProviderError: Error, Equatable {
    case failed
    case missingCandidate
}
