import Foundation
import XCTest
@testable import SnapCount

final class LocalAIIntegrationRegressionTests: XCTestCase {
    func testHostedLocalExpressionRoundTripPersistsTheBoundedPacket() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let older = try repository.createExpense(expenseDraft(
            id: UUID(), profileID: profile.id, amountMinor: 800, date: "2026-11-13"
        ), operationID: UUID())
        let current = try repository.createExpense(expenseDraft(
            id: UUID(), profileID: profile.id, amountMinor: 1280, date: "2026-11-14"
        ), operationID: UUID())
        let detail = LocalExpenseReadModel.detail(from: current)
        var settings = NativeUserSettings()
        settings.companionMemoryEnabled = true
        let persistence = LocalExpressionPersistence(
            database: database,
            settingsProvider: { LocalExpressionSettings(companionEnabled: true, memoryEnabled: true) }
        )
        let context = try XCTUnwrap(persistence.makeCompositionContext(
            for: detail,
            profileID: profile.id,
            settings: settings,
            providerMode: .hosted,
            now: ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
        ))
        XCTAssertEqual(context.recentFacts.map(\.id), [older.id.uuidString])
        XCTAssertNotNil(context.memoryContextJSON)

        let session = try makeStubSession()
        BYOKURLProtocolStub.configure(statusCode: 200, responseData: Data(#"{"ok":true,"data":{"companion_message":"这笔已记下。","ai_feedback":{"badge":"观察","icon":"✨","band":"positive","emotion_line":"这笔记录有明确依据。","utility_line":"保留这份节奏","detail_reason":"来自当前事实","confidence":0.9}}}"#.utf8))
        let provider = HostedAICompanionProvider(
            accessToken: "session-token",
            service: SnapCountUploadService(
                session: session,
                functionsURL: "https://example.test/functions/v1",
                anonKey: "publishable-key"
            )
        )
        let result = try await provider.compose(context: context)
        XCTAssertEqual(result.companionMessage, "这笔已记下。")
        XCTAssertNotNil(result.aiFeedback)

        let body = try XCTUnwrap(BYOKURLProtocolStub.capturedBody)
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(packet["action"] as? String, "generate_local_expression")
        XCTAssertEqual((packet["current_fact"] as? [String: Any])?["id"] as? String, current.id.uuidString)
        XCTAssertNotNil(packet["planner_candidate"] as? [String: Any])
        XCTAssertNotNil(packet["local_memory_context"] as? [String: Any])
        XCTAssertEqual((packet["expression_preferences"] as? [String: Any])?["persona"] as? String, "observer")
        XCTAssertEqual(packet["client_local_time"] as? String, "2026-11-14 20:00")
        XCTAssertEqual(packet["client_captured_at"] as? String, "2026-11-14T12:00:00Z")
        XCTAssertEqual(packet["weekday"] as? String, "周六")

        persistence.persist(companion: result, for: detail)
        let stored = try XCTUnwrap(try repository.expense(id: current.id))
        XCTAssertEqual(stored.companionMessage, "这笔已记下。")
        XCTAssertTrue(stored.aiFeedbackJSON?.contains("这笔记录有明确依据") == true)
        session.invalidateAndCancel()
    }

    func testMemoryOffProviderFailureKeepsFactsAndDeterministicFallback() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let expense = try repository.createExpense(expenseDraft(
            id: UUID(), profileID: profile.id, amountMinor: 2645, date: "2026-11-14"
        ), operationID: UUID())
        var settings = NativeUserSettings()
        settings.companionMemoryEnabled = true
        let persistence = LocalExpressionPersistence(
            database: database,
            settingsProvider: { LocalExpressionSettings(companionEnabled: true, memoryEnabled: false) }
        )
        let detail = LocalExpenseReadModel.detail(from: expense)
        let context = try XCTUnwrap(persistence.makeCompositionContext(
            for: detail, profileID: profile.id, settings: settings, providerMode: .hosted,
            now: ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
        ))
        XCTAssertNil(context.memoryContextJSON)
        XCTAssertTrue(context.recentCompanionLines.isEmpty)

        let session = try makeStubSession()
        BYOKURLProtocolStub.configure(statusCode: 503, responseData: Data("provider unavailable".utf8))
        let provider = HostedAICompanionProvider(
            accessToken: "session-token",
            service: SnapCountUploadService(
                session: session,
                functionsURL: "https://example.test/functions/v1",
                anonKey: "publishable-key"
            )
        )
        do {
            _ = try await provider.compose(context: context)
            XCTFail("provider failure must be observable to the caller")
        } catch {
            XCTAssertTrue(error is SnapCountUploadServiceError)
        }

        let body = try XCTUnwrap(BYOKURLProtocolStub.capturedBody)
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(packet["local_memory_context"])
        persistence.refresh(expense: expense)
        let stored = try XCTUnwrap(try repository.expense(id: expense.id))
        XCTAssertEqual(stored.amountMinor, 2645)
        XCTAssertTrue(stored.aiFeedbackJSON?.contains("expression_planner") == true)
        session.invalidateAndCancel()
    }

    func testStagingIsExcludedAndConfirmationRetryIsIdempotent() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalRecordRepository(database: database)
        let useCase = LocalRecordUseCase(profileStore: profileStore, repository: repository)
        let formal = try await useCase.create(LocalRecordCommand(
            id: UUID(), domainKey: "sport", title: "正式运动", summary: "跑步",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)],
            recordDate: "2026-11-14", recordTime: nil, note: nil, imageData: nil, createdAt: Date()
        ))
        let staged = try await useCase.stage(LocalRecordCandidate(
            id: "pending-staging", domainKey: "sport", title: "待确认运动", summary: "候选",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(20)],
            confidence: 0.5, recordDate: "2026-11-14", recordTime: nil, imageData: nil, createdAt: Date()
        ))
        let facts = try LocalFactReader(database: database).range(
            profileID: try profileStore.activeProfile().id, from: "2026-11-01", to: "2026-11-30"
        ).facts
        XCTAssertTrue(facts.contains { $0.id == formal.record.id })
        XCTAssertFalse(facts.contains { $0.id.uuidString == staged.record.id })

        let recordID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let first = try await useCase.confirmStaging(id: staged.record.id, recordID: recordID)
        let retry = try await useCase.confirmStaging(id: staged.record.id, recordID: UUID())
        XCTAssertEqual(first.record.id, recordID)
        XCTAssertEqual(retry.record.id, recordID)
        let records = try await useCase.records(monthKey: "2026-11")
        XCTAssertEqual(records.filter { $0.id == recordID }.count, 1)
    }

    @MainActor
    func testShortcutNotificationResultAndAppStateRouteRemainIdempotent() throws {
        let json = #"{"status":"completed","record_type":"expense","id":"record-1","notification_text":"已记下","companion_message":"已记下","ai_feedback":{"badge":"观察","icon":"✨","emotion_line":"已记下","utility_line":"保留节奏","confidence":0.9}}"#
        let payload = try JSONDecoder().decode(ShortcutUploadPayload.self, from: Data(json.utf8))
        let result = ShortcutUploadResult(payload: payload)
        XCTAssertEqual(result.route, "records/expense/record-1")
        XCTAssertEqual(result.notificationText.components(separatedBy: "\n").count, 1)
        XCTAssertFalse(result.notificationBody.isEmpty)
        let merged = LocalIntakeNotificationText.merge(
            baseText: "已记下", companionMessage: "已记下",
            feedbackParts: LocalIntakeNotificationFeedback(
                icon: "✨", badge: "观察", emotionLine: "已记下", utilityLine: "保留节奏"
            )
        )
        XCTAssertEqual(merged.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 1)

        let state = AppState()
        state.handleShortcutNotificationRoute(result.route)
        XCTAssertEqual(state.presentedOverlay, .records)
        XCTAssertEqual(state.recordsPath.count, 1)
        state.handleShortcutNotificationRoute(result.route)
        XCTAssertEqual(state.recordsPath.count, 1)
    }

    private func makeStubSession() throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("local-ai-integration-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("local.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private func expenseDraft(id: UUID, profileID: UUID, amountMinor: Int64, date: String) -> LocalExpenseDraft {
        LocalExpenseDraft(
            id: id, profileID: profileID, accountID: nil, amountMinor: amountMinor,
            currency: "CNY", merchantName: "便利店", platform: "", category: "日用",
            paymentMethod: "cash", transactionDate: date, transactionTime: nil,
            note: nil, createdAt: Date()
        )
    }
}
