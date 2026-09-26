import Foundation
import XCTest
@testable import SnapCount

final class LocalSportRecordTests: XCTestCase {
    func testLOCALP1SPORT001GLocalCaptureDraftRetainsImageForLocalSave() {
        let imageData = Data("captured-image".utf8)
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "sport")

        draft.imageData = imageData

        XCTAssertEqual(draft.imageData, imageData)
        XCTAssertEqual(draft.domainKey, "sport")
        XCTAssertEqual(draft.kind, .universal)
    }

    func testLOCALP1SPORT001HLocalStagingProjectsToInboxWithLocalImageRoute() async throws {
        let databaseURL = temporaryDatabaseURL()
        let imageDirectory = temporaryDirectoryURL()
        defer {
            removeDatabase(at: databaseURL)
            removeImageDirectory(at: imageDirectory)
        }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = try LocalImageStore(rootDirectory: imageDirectory)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database),
            imageStore: store
        )
        let staged = try await useCase.stage(LocalRecordCandidate(
            id: "candidate-local-inbox",
            domainKey: "sport",
            title: "待确认运动",
            summary: "本地候选",
            payload: [
                "sport_type": AnyCodable("跑步"),
                "duration_minutes": AnyCodable(30)
            ],
            confidence: 0.62,
            recordDate: "2026-09-19",
            recordTime: "18:00",
            imageData: Data("local-staging-image".utf8),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let inboxRecord = LocalStagingReadModel.native(
            from: staged.record,
            imageStore: store,
            domainName: "运动"
        )

        XCTAssertEqual(inboxRecord.id, "local-staging/candidate-local-inbox")
        XCTAssertEqual(
            LocalStagingReadModel.localID(from: inboxRecord.id),
            staged.record.id
        )
        XCTAssertEqual(inboxRecord.domainKey, "sport")
        XCTAssertEqual(inboxRecord.confidencePercent, 62)
        XCTAssertEqual(inboxRecord.status, "pending_review")
        XCTAssertEqual(inboxRecord.domainName, "运动")
        XCTAssertEqual(inboxRecord.imageURL, store.url(for: staged.record.imagePath!))
    }

    func testLOCALP1SPORT001IConfirmedCandidateBecomesFormalFactWithImageAndSource() async throws {
        let databaseURL = temporaryDatabaseURL()
        let imageDirectory = temporaryDirectoryURL()
        defer {
            removeDatabase(at: databaseURL)
            removeImageDirectory(at: imageDirectory)
        }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let store = try LocalImageStore(rootDirectory: imageDirectory)
        let useCase = LocalRecordUseCase(
            profileStore: profileStore,
            repository: try LocalRecordRepository(database: database),
            imageStore: store
        )
        let recordID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let staged = try await useCase.stage(LocalRecordCandidate(
            id: "candidate-formal-fact",
            domainKey: "sport",
            title: "已确认运动",
            summary: "确认后成为正式事实",
            payload: [
                "sport_type": AnyCodable("跑步"),
                "duration_minutes": AnyCodable(45)
            ],
            confidence: 0.62,
            recordDate: "2026-09-19",
            recordTime: "18:00",
            imageData: Data("confirmed-local-image".utf8),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let stagedImagePath = try XCTUnwrap(staged.record.imagePath)
        let archived = try await useCase.confirmStaging(
            id: staged.record.id,
            recordID: recordID
        )

        XCTAssertEqual(archived.record.id, recordID)
        XCTAssertEqual(archived.record.sourceKind, .aiConfirmed)
        XCTAssertEqual(archived.record.imagePath, stagedImagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: stagedImagePath).path))

        let resolvedStaging = try await useCase.staging(id: staged.record.id)
        XCTAssertEqual(resolvedStaging?.status, .archived)
        XCTAssertNil(resolvedStaging?.imagePath)

        let reader = try LocalFactReader(database: database)
        let profile = try profileStore.activeProfile()
        let month = try reader.month(profileID: profile.id, monthKey: "2026-09")
        let fact = try XCTUnwrap(month.facts.first { $0.id == recordID })
        XCTAssertEqual(fact.reference, "data/\(recordID.uuidString)")
        XCTAssertEqual(fact.sourceKind, LocalRecordSourceKind.aiConfirmed.rawValue)
        XCTAssertEqual(fact.imagePath, stagedImagePath)

        let detail = LocalRecordReadModel.detail(from: archived.record, imageStore: store)
        XCTAssertEqual(detail.source, LocalRecordSourceKind.aiConfirmed.rawValue)
        XCTAssertEqual(detail.domainVersion, "local-v1")
        XCTAssertEqual(detail.imageURL, store.url(for: stagedImagePath))
    }

    func testLOCALP1SPORT001ARecordSurvivesDatabaseReopenAndProjectsToNativeRecord() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let firstDatabase = try LocalDatabase(databaseURL: databaseURL)
        let firstStore = LocalProfileStore(database: firstDatabase)
        let firstRepository = try LocalRecordRepository(database: firstDatabase)
        let firstUseCase = LocalRecordUseCase(profileStore: firstStore, repository: firstRepository)
        let profile = try firstStore.activeProfile()

        let recordID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let created = try await firstUseCase.create(LocalRecordCommand(
            id: recordID,
            domainKey: "sport",
            title: "晨跑",
            summary: "公园慢跑",
            payload: [
                "sport_type": AnyCodable("跑步"),
                "duration_minutes": AnyCodable(35),
                "calories": AnyCodable(240)
            ],
            recordDate: "2026-09-19",
            recordTime: "07:20",
            note: "本地首片",
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        XCTAssertEqual(created.record.id, recordID)
        XCTAssertEqual(created.record.profileID, profile.id)
        XCTAssertEqual(created.record.domainKey, "sport")

        let reopenedDatabase = try LocalDatabase(databaseURL: databaseURL)
        let reopenedStore = LocalProfileStore(database: reopenedDatabase)
        let reopenedRepository = try LocalRecordRepository(database: reopenedDatabase)
        let reopenedUseCase = LocalRecordUseCase(profileStore: reopenedStore, repository: reopenedRepository)
        let month = try await reopenedUseCase.month("2026-09")
        let groups = LocalRecordReadModel.groups(from: month)

        XCTAssertEqual(groups.first?.records.first?.reference, "local-data/\(recordID.uuidString)")
        XCTAssertEqual(groups.first?.records.first?.domainKey, "sport")
        let reopenedRecord = try await reopenedUseCase.record(id: recordID)
        XCTAssertEqual(reopenedRecord?.localVersion, 1)
    }

    func testLOCALP1SPORT001BEditAndDeleteUseExpectedVersionAndLeaveTombstone() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = LocalProfileStore(database: database)
        let repository = try LocalRecordRepository(database: database)
        let useCase = LocalRecordUseCase(profileStore: store, repository: repository)
        let recordID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        _ = try await useCase.create(LocalRecordCommand(
            id: recordID,
            domainKey: "sport",
            title: "骑行",
            summary: "河边骑行",
            payload: ["sport_type": AnyCodable("骑行"), "duration_minutes": AnyCodable(40)],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date()
        ))

        let updated = try await useCase.update(LocalRecordUpdateCommand(
            id: recordID,
            expectedVersion: 1,
            title: "夜间骑行",
            summary: "河边骑行",
            payload: ["sport_type": AnyCodable("骑行"), "duration_minutes": AnyCodable(55)],
            recordDate: "2026-09-19",
            recordTime: "20:10",
            note: "已编辑",
            updatedAt: Date()
        ))
        XCTAssertEqual(updated.record.localVersion, 2)
        let updatedRecord = try await useCase.record(id: recordID)
        XCTAssertEqual(updatedRecord?.title, "夜间骑行")

        let deleted = try await useCase.delete(LocalRecordDeleteCommand(
            id: recordID,
            expectedVersion: 2,
            deletedAt: Date()
        ))
        XCTAssertEqual(deleted.tombstone.localVersion, 3)
        let deletedRecord = try await useCase.record(id: recordID)
        XCTAssertNil(deletedRecord)
        let tombstone = try await useCase.tombstone(id: recordID)
        XCTAssertEqual(tombstone?.localVersion, 3)
    }

    func testLOCALP1SPORT001CConfidenceBoundaryRoutesPerSportDomainThreshold() {
        let payload: [String: AnyCodable] = [
            "sport_type": AnyCodable("跑步"),
            "duration_minutes": AnyCodable(20)
        ]
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(domainKey: "sport", confidence: 0.75, payload: payload),
            .autoArchive,
            "sport 分域阈值 0.75：达到边界应自动归档"
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(domainKey: "sport", confidence: 0.74, payload: payload),
            .staging
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(domainKey: "sport", confidence: nil, payload: payload),
            .staging,
            "无置信度应保留在本地 Inbox"
        )
    }

    func testLOCALP1SPORT001CUseCasePersistsAutoArchiveAndStagingRoute() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = LocalProfileStore(database: database)
        let useCase = LocalRecordUseCase(
            profileStore: store,
            repository: try LocalRecordRepository(database: database)
        )
        let highConfidence = LocalRecordCandidate(
            id: "candidate-high",
            domainKey: "sport",
            title: "自动归档运动",
            summary: "高置信度结果",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(20)],
            confidence: 0.80,
            recordDate: "2026-09-19",
            recordTime: "07:00",
            imageData: nil,
            createdAt: Date()
        )
        let lowConfidence = LocalRecordCandidate(
            id: "candidate-low",
            domainKey: "sport",
            title: "待确认运动",
            summary: "低置信度结果",
            payload: ["sport_type": AnyCodable("游泳"), "duration_minutes": AnyCodable(30)],
            confidence: 0.74,
            recordDate: "2026-09-19",
            recordTime: "18:00",
            imageData: nil,
            createdAt: Date()
        )

        let highOutcome = try await useCase.ingest(highConfidence, recordID: UUID())
        guard case .archived(let archived) = highOutcome else {
            return XCTFail("高置信度候选没有自动归档")
        }
        let lowOutcome = try await useCase.ingest(lowConfidence, recordID: nil)
        guard case .staged(let staged) = lowOutcome else {
            return XCTFail("低置信度候选没有进入中转站")
        }
        XCTAssertEqual(archived.record.domainKey, "sport")
        XCTAssertEqual(staged.record.status, .pendingReview)
        let records = try await useCase.records(monthKey: "2026-09")
        XCTAssertEqual(records.count, 1)
    }

    func testLOCALP1SPORT001DStagingDoesNotBecomeFormalRecordBeforeConfirmation() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = LocalProfileStore(database: database)
        let repository = try LocalRecordRepository(database: database)
        let useCase = LocalRecordUseCase(profileStore: store, repository: repository)
        let staging = try await useCase.stage(LocalRecordCandidate(
            id: "staging-sport-1",
            domainKey: "sport",
            title: "待确认运动",
            summary: "识别到了运动截图",
            payload: ["sport_type": AnyCodable("游泳"), "duration_minutes": AnyCodable(30)],
            confidence: 0.62,
            recordDate: "2026-09-19",
            recordTime: "18:00",
            imageData: nil,
            createdAt: Date()
        ))

        XCTAssertEqual(staging.record.status, .pendingReview)
        let recordsBeforeConfirmation = try await useCase.records(monthKey: "2026-09")
        XCTAssertTrue(recordsBeforeConfirmation.isEmpty)

        let archived = try await useCase.confirmStaging(
            id: staging.record.id,
            recordID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )
        XCTAssertEqual(archived.record.domainKey, "sport")
        let recordsAfterConfirmation = try await useCase.records(monthKey: "2026-09")
        XCTAssertEqual(recordsAfterConfirmation.count, 1)
        let confirmedStaging = try await useCase.staging(id: staging.record.id)
        XCTAssertEqual(confirmedStaging?.status, .archived)
    }

    func testLOCALP1SPORT001EImageIsLocalAndRemovedWithRecord() async throws {
        let databaseURL = temporaryDatabaseURL()
        let imageDirectory = temporaryDirectoryURL()
        defer {
            removeDatabase(at: databaseURL)
            removeImageDirectory(at: imageDirectory)
        }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = LocalProfileStore(database: database)
        let repository = try LocalRecordRepository(database: database)
        let imageStore = try LocalImageStore(rootDirectory: imageDirectory)
        let useCase = LocalRecordUseCase(profileStore: store, repository: repository, imageStore: imageStore)
        let imageData = Data("fake-jpeg".utf8)
        let recordID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        let created = try await useCase.create(LocalRecordCommand(
            id: recordID,
            domainKey: "sport",
            title: "带图片的运动",
            summary: "本地图片",
            payload: ["sport_type": AnyCodable("徒步"), "duration_minutes": AnyCodable(60)],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: imageData,
            createdAt: Date()
        ))

        let imagePath = try XCTUnwrap(created.record.imagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageStore.url(for: imagePath).path))
        XCTAssertEqual(try Data(contentsOf: imageStore.url(for: imagePath)), imageData)

        _ = try await useCase.delete(LocalRecordDeleteCommand(
            id: recordID,
            expectedVersion: created.record.localVersion,
            deletedAt: Date()
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageStore.url(for: imagePath).path))
    }

    func testLOCALP1SPORT001FExportCanIncludeCurrentLocalImage() async throws {
        let databaseURL = temporaryDatabaseURL()
        let imageDirectory = temporaryDirectoryURL()
        defer {
            removeDatabase(at: databaseURL)
            removeImageDirectory(at: imageDirectory)
        }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = LocalProfileStore(database: database)
        let repository = try LocalRecordRepository(database: database)
        let imageStore = try LocalImageStore(rootDirectory: imageDirectory)
        let useCase = LocalRecordUseCase(profileStore: store, repository: repository, imageStore: imageStore)
        _ = try await useCase.create(LocalRecordCommand(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            domainKey: "sport",
            title: "导出运动",
            summary: "带本地图片",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(20)],
            recordDate: "2026-09-19",
            recordTime: "07:00",
            note: nil,
            imageData: Data("export-image".utf8),
            createdAt: Date()
        ))

        let data = try LocalRecordPortability(database: database, imageStore: imageStore).exportArchive(
            request: NativeDataExportRequest(
                content: .universal,
                range: .all,
                format: .json,
                includeFullPayload: true,
                includeImages: true
            )
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LocalRecordArchive.self, from: data)
        XCTAssertEqual(archive.records.count, 1)
        let exportedImage = try XCTUnwrap(
            Data(base64Encoded: try XCTUnwrap(archive.records.first?.imageDataBase64))
        )
        XCTAssertEqual(exportedImage, Data("export-image".utf8))
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-sport-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jiezi.sqlite")
    }

    private func temporaryDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-sport-images-\(UUID().uuidString)", isDirectory: true)
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: url)
    }

    private func removeImageDirectory(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
