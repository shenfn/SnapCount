import Foundation
import XCTest
@testable import SnapCount

final class LocalPhase1DataModelTests: XCTestCase {
    func testLOCALP1DM001GenericRepositoryRejectsExpenseDomain() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalRecordRepository(database: database)

        XCTAssertThrowsError(try repository.createRecord(LocalRecordDraft(
            id: UUID(),
            profileID: profile.id,
            domainKey: "expense",
            title: "不应进入通用记录",
            summary: "消费必须走 local_expenses",
            payloadJSON: "{}",
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date()
        ))) { error in
            XCTAssertEqual(error as? LocalDataError, .invalidRecord)
        }
    }

    func testLOCALP1DM003DomainThresholdsRequireDomainFactsAndNormalizeSleepMinutes() throws {
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "sport",
                confidence: 0.75,
                payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)]
            ),
            .autoArchive
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "sport",
                confidence: 0.74,
                payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)]
            ),
            .staging
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "food",
                confidence: 0.79,
                payload: ["meal_type": AnyCodable("lunch"), "total_calorie_kcal": AnyCodable(520)]
            ),
            .staging
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "sport",
                confidence: 0.99,
                payload: ["sport_type": AnyCodable("跑步")]
            ),
            .staging
        )

        let normalized = try LocalRecordCodec.normalizedPayload(
            domainKey: "sleep",
            payload: [
                "sleep_hours": AnyCodable(6.5),
                "quality_level": AnyCodable("良好")
            ]
        )
        XCTAssertEqual(normalized["sleep_minutes"]?.value as? Int, 390)
        XCTAssertNil(normalized["sleep_hours"])
    }

    func testLOCALP1DM009MalformedTimeFailsAndMissingTimeRemainsMissing() async throws {
        XCTAssertThrowsError(try LocalRecordValidation.validate(
            domainKey: "reading",
            title: "阅读",
            recordDate: "2026-09-19",
            recordTime: "上传时刻"
        )) { error in
            XCTAssertEqual(error as? LocalDataError, .invalidRecord)
        }

        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )

        let result = try await useCase.create(LocalRecordCommand(
            id: UUID(),
            domainKey: "reading",
            title: "阅读",
            summary: "没有完整发生时间",
            payload: [
                "book_name": AnyCodable("原则"),
                "reading_minutes": AnyCodable(25)
            ],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date()
        ))
        XCTAssertNil(result.record.recordTime)
    }

    func testLOCALP1DM006ConfirmingStagingTwiceReturnsSameFormalRecord() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )
        let staging = try await useCase.stage(LocalRecordCandidate(
            id: "staging-idempotent-1",
            domainKey: "sport",
            title: "待确认运动",
            summary: "用户确认后归档",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)],
            confidence: 0.62,
            recordDate: "2026-09-19",
            recordTime: nil,
            imageData: nil,
            createdAt: Date()
        ))

        let recordID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let first = try await useCase.confirmStaging(id: staging.record.id, recordID: recordID)
        let retry = try await useCase.confirmStaging(
            id: staging.record.id,
            recordID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        )

        XCTAssertEqual(first.record.id, recordID)
        XCTAssertEqual(retry.record.id, recordID)
        XCTAssertEqual(try await useCase.records(monthKey: "2026-09").map(\.id), [recordID])
    }

    func testLOCALP1DM008StaleVersionCannotOverwriteFormalFact() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )
        let recordID = UUID()
        _ = try await useCase.create(LocalRecordCommand(
            id: recordID,
            domainKey: "sport",
            title: "原始运动",
            summary: "原始摘要",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date()
        ))
        _ = try await useCase.update(LocalRecordUpdateCommand(
            id: recordID,
            expectedVersion: 1,
            title: "第一次编辑",
            summary: "已保存",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(35)],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            updatedAt: Date()
        ))

        do {
            _ = try await useCase.update(LocalRecordUpdateCommand(
                id: recordID,
                expectedVersion: 1,
                title: "旧版本覆盖",
                summary: "不应保存",
                payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(99)],
                recordDate: "2026-09-19",
                recordTime: nil,
                note: nil,
                updatedAt: Date()
            ))
            XCTFail("旧版本更新不应成功")
        } catch let error as LocalDataError {
            XCTAssertEqual(error, .versionConflict(expected: 1, actual: 2))
        }
        XCTAssertEqual(try await useCase.record(id: recordID)?.title, "第一次编辑")
    }

    func testLOCALP1DM011FactReaderMergesFormalDomainsAndExcludesStagingAndTombstones() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()

        let expenseRepository = try LocalExpenseRepository(database: database)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        let expenseID = UUID()
        _ = try expenseRepository.createExpense(LocalExpenseDraft(
            id: expenseID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 1_980,
            currency: "CNY",
            merchantName: "本地咖啡店",
            platform: "线下",
            category: "餐饮",
            paymentMethod: "现金",
            transactionDate: "2026-09-19",
            transactionTime: "08:30",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_100)
        ), operationID: UUID())

        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )
        let activeSportID = UUID()
        _ = try await useCase.create(LocalRecordCommand(
            id: activeSportID,
            domainKey: "sport",
            title: "晨跑",
            summary: "30 分钟",
            payload: [
                "sport_type": AnyCodable("跑步"),
                "duration_minutes": AnyCodable(30)
            ],
            recordDate: "2026-09-19",
            recordTime: "10:30",
            note: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_200)
        ))

        let deletedReadingID = UUID()
        _ = try await useCase.create(LocalRecordCommand(
            id: deletedReadingID,
            domainKey: "reading",
            title: "已删除阅读",
            summary: "不应出现在正式事实层",
            payload: [
                "book_name": AnyCodable("原则"),
                "reading_minutes": AnyCodable(20)
            ],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_300)
        ))
        _ = try await useCase.delete(LocalRecordDeleteCommand(
            id: deletedReadingID,
            expectedVersion: 1,
            deletedAt: Date(timeIntervalSince1970: 1_400)
        ))

        _ = try await useCase.stage(LocalRecordCandidate(
            id: "staging-not-a-fact",
            domainKey: "food",
            title: "待确认餐食",
            summary: "中转站内容",
            payload: ["meal_type": AnyCodable("lunch")],
            confidence: 0.50,
            recordDate: "2026-09-19",
            recordTime: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_500)
        ))

        let reader = try LocalFactReader(database: database)
        let month = try reader.month(profileID: profile.id, monthKey: "2026-09")

        XCTAssertEqual(month.facts.map(\.reference), [
            "data/\(activeSportID.uuidString)",
            "expense/\(expenseID.uuidString)"
        ])
        XCTAssertEqual(month.facts.map(\.domainKey), ["sport", "expense"])
        XCTAssertEqual(month.facts.map(\.kind), [.record, .expense])
        XCTAssertEqual(month.facts.last?.payloadJSON.contains("amount_minor"), true)
        XCTAssertFalse(month.facts.contains { $0.id == deletedReadingID })
        XCTAssertEqual(try await useCase.stagingRecords().count, 1)
    }

    func testLOCALP1DM011FactReadModelProjectsSeparateTodayAndRecordsGroups() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))
        let expenseID = UUID()
        _ = try expenseRepository.createExpense(LocalExpenseDraft(
            id: expenseID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 680,
            currency: "CNY",
            merchantName: "早餐店",
            platform: "线下",
            category: "餐饮",
            paymentMethod: "现金",
            transactionDate: "2026-09-19",
            transactionTime: "08:00",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 2_100)
        ), operationID: UUID())

        let recordID = UUID()
        let recordRepository = try LocalRecordRepository(database: database)
        _ = try recordRepository.createRecord(LocalRecordDraft(
            id: recordID,
            profileID: profile.id,
            domainKey: "sport",
            title: "散步",
            summary: "20 分钟",
            payloadJSON: try LocalRecordCodec.encode([
                "sport_type": AnyCodable("散步"),
                "duration_minutes": AnyCodable(20)
            ]),
            recordDate: "2026-09-19",
            recordTime: "18:00",
            note: nil,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date(timeIntervalSince1970: 2_200)
        ))

        let month = try LocalFactReader(database: database).month(
            profileID: profile.id,
            monthKey: "2026-09"
        )
        let expenseGroups = LocalFactReadModel.groups(from: month, including: [.expense])
        let recordGroups = LocalFactReadModel.groups(from: month, including: [.record])
        let details = LocalFactReadModel.details(from: month)

        XCTAssertEqual(expenseGroups.flatMap(\.records).map(\.reference), [
            "expense/\(expenseID.uuidString)"
        ])
        XCTAssertEqual(recordGroups.flatMap(\.records).map(\.reference), [
            "data/\(recordID.uuidString)"
        ])
        XCTAssertEqual(details["expense/\(expenseID.uuidString)"]?.amount ?? 0, 6.8, accuracy: 0.001)
        XCTAssertEqual(details["data/\(recordID.uuidString)"]?.domainKey, "sport")
    }

    func testLOCALP1DM010UnifiedExportCoversExpenseAndNonFinancialFacts() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 3_000)
        ))
        let expenseID = UUID()
        _ = try expenseRepository.createExpense(LocalExpenseDraft(
            id: expenseID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 1_200,
            currency: "CNY",
            merchantName: "书店",
            platform: "线下",
            category: "阅读",
            paymentMethod: "现金",
            transactionDate: "2026-09-19",
            transactionTime: nil,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 3_100)
        ), operationID: UUID())
        let recordID = UUID()
        let recordRepository = try LocalRecordRepository(database: database)
        _ = try recordRepository.createRecord(LocalRecordDraft(
            id: recordID,
            profileID: profile.id,
            domainKey: "reading",
            title: "原则",
            summary: "25 分钟",
            payloadJSON: try LocalRecordCodec.encode([
                "book_name": AnyCodable("原则"),
                "reading_minutes": AnyCodable(25)
            ]),
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date(timeIntervalSince1970: 3_200)
        ))

        let portability = LocalFactPortability(database: database)
        var request = NativeDataExportRequest()
        request.content = .universal
        request.range = .all
        request.format = .json
        request.includeFullPayload = true
        let json = try portability.exportArchive(
            request: request,
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let archive = try JSONDecoder.iso8601.decode(LocalFactArchive.self, from: json)
        XCTAssertEqual(archive.format, LocalFactArchive.currentFormat)
        XCTAssertEqual(Set(archive.facts.map(\.reference)), [
            "expense/\(expenseID.uuidString)",
            "data/\(recordID.uuidString)"
        ])
        XCTAssertTrue(archive.facts.contains { $0.payloadJSON.contains("reading_minutes") })

        request.format = .csv
        request.includeFullPayload = false
        let csv = String(
            decoding: try portability.exportArchive(
                request: request,
                exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            as: UTF8.self
        )
        XCTAssertTrue(csv.contains("expense/\(expenseID.uuidString)"))
        XCTAssertTrue(csv.contains("data/\(recordID.uuidString)"))
        XCTAssertTrue(csv.contains(",{}"))
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-phase1-model-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jiezi.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: url)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
