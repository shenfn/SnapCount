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
            now: ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!,
            timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
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

        let hostedBody = try XCTUnwrap(BYOKURLProtocolStub.capturedBody)
        let packet = try XCTUnwrap(JSONSerialization.jsonObject(with: hostedBody) as? [String: Any])
        XCTAssertEqual(packet["action"] as? String, "generate_local_expression")
        let currentFact = try XCTUnwrap(packet["current_fact"] as? [String: Any])
        XCTAssertEqual(currentFact["id"] as? String, current.id.uuidString)
        let candidate = try XCTUnwrap(packet["planner_candidate"] as? [String: Any])
        XCTAssertEqual(candidate["dimension"] as? String, "current_fact")
        XCTAssertNotNil(packet["local_memory_context"] as? [String: Any])
        XCTAssertEqual((packet["expression_preferences"] as? [String: Any])?["persona"] as? String, "observer")
        XCTAssertEqual(packet["client_local_time"] as? String, "2026-11-14 20:00")
        XCTAssertEqual(packet["client_captured_at"] as? String, "2026-11-14T12:00:00Z")
        XCTAssertEqual(packet["weekday"] as? String, "周六")

        let canonicalText = try XCTUnwrap(candidate["canonical_text"] as? String)
        XCTAssertFalse(canonicalText.isEmpty)
        XCTAssertEqual(canonicalText, candidate["emotion_line"] as? String)
        let semanticKey = try XCTUnwrap(candidate["semantic_key"] as? String)
        XCTAssertEqual(
            candidate["claim_fingerprint"] as? String,
            LocalExpressionContract.claimFingerprint(semanticKey: semanticKey, canonicalText: canonicalText)
        )
        let memoryFacts = ((packet["local_memory_context"] as? [String: Any])?["facts"] as? [[String: Any]]) ?? []
        let memoryKeys = Set(memoryFacts.compactMap { $0["key"] as? String })
        let evidence = try XCTUnwrap(candidate["evidence"] as? [[String: Any]])
        for reference in evidence {
            switch reference["kind"] as? String {
            case "current_fact":
                XCTAssertEqual(reference["reference"] as? String, current.id.uuidString)
            case "local_memory":
                XCTAssertTrue(memoryKeys.contains(reference["reference"] as? String ?? ""))
            default:
                XCTFail("unexpected evidence kind: \(reference)")
            }
        }
        let numberFactValues = ((candidate["number_facts"] as? [[String: Any]]) ?? []).compactMap { $0["value"] as? Double }
        XCTAssertEqual(numberFactValues, [12.8])
        XCTAssertEqual(candidate["numbers"] as? [Double], Optional([12.8]))
        XCTAssertNoThrow(try EdgePlannerValidatorMirror.validate(
            candidate,
            currentFact: currentFact,
            memoryFacts: memoryFacts
        ))

        BYOKURLProtocolStub.configure(
            statusCode: 200,
            responseData: byokResponse(#"{"companion_message":"这笔已记下。","ai_feedback":{"badge":"观察","icon":"✨","band":"positive","emotion_line":"这笔记录有明确依据。","utility_line":"保留这份节奏","detail_reason":"来自当前事实","confidence":0.9}}"#)
        )
        let byokResult = try await QwenBYOKCompanionProvider(apiKey: "byok-key", session: session).compose(context: context)
        XCTAssertEqual(byokResult.companionMessage, result.companionMessage)
        let hostedFeedback = try XCTUnwrap(result.aiFeedback)
        let byokFeedback = try XCTUnwrap(byokResult.aiFeedback)
        XCTAssertEqual(Set(byokFeedback.keys), Set(hostedFeedback.keys))

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
        XCTAssertEqual(facts.filter { $0.domainKey == "sport" }.map(\.title), ["正式运动"])
        XCTAssertFalse(facts.contains { $0.title == "待确认运动" })

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
        XCTAssertEqual(result.displayText, result.notificationText)
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

    func testArchivedShortcutResultKeepsCompanionAndFactsInNotificationBody() throws {
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "badge": AnyCodable("观察"),
            "icon": AnyCodable("✨"),
            "band": AnyCodable("neutral"),
            "emotion_line": AnyCodable("这笔消费有明确依据。"),
            "utility_line": AnyCodable("保留这份节奏"),
            "confidence": AnyCodable(0.9)
        ]))
        let result = ShortcutUploadResult.archived(
            notificationText: "💸 -¥12.80 · 便利店 · 日用\n今日已花 ¥12.80（1 笔）",
            companionMessage: "这笔便利店消费已记录，金额为¥12.80。",
            feedback: feedback
        )

        XCTAssertEqual(result.route, "records")
        XCTAssertEqual(result.displayText, result.notificationText)
        let body = result.notificationBody
        XCTAssertTrue(body.contains("这笔便利店消费已记录"))
        XCTAssertTrue(body.contains("-¥12.80"))
        XCTAssertTrue(body.contains("今日已花 ¥12.80"))
        XCTAssertLessThanOrEqual(body.count, 160)
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

    private func byokResponse(_ content: String) -> Data {
        let object: [String: Any] = ["choices": [["message": ["content": content]]]]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}

/// Test-only mirror of `validateLocalPlannerCandidate` in
/// `supabase/functions/ingest-receipt/local-expression-contract.ts`.
///
/// It exists so the iOS suite can prove that a produced candidate would pass
/// the Edge contract. Keep the rules, ordering, and reason strings in sync with
/// the TypeScript implementation; algorithm drift on either side is a bug.
enum EdgePlannerValidatorMirror {
    struct Failure: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }

    private struct Evidence {
        let kind: String
        let source: String
        let reference: String
        let field: String?
    }

    private struct NumberFact {
        let value: Double
        let role: String
        let evidence: [Evidence]
    }

    static func validate(
        _ candidate: [String: Any],
        currentFact: [String: Any],
        recentFacts: [[String: Any]] = [],
        memoryFacts: [[String: Any]] = []
    ) throws {
        let candidateId = trimmedString(candidate["candidate_id"])
        let semanticKey = trimmedString(candidate["semantic_key"])
        let canonicalText = trimmedString(candidate["canonical_text"])
        let dimension = trimmedString(candidate["dimension"])
        let claimFingerprint = trimmedString(candidate["claim_fingerprint"])
        guard !candidateId.isEmpty, !semanticKey.isEmpty, !canonicalText.isEmpty, !dimension.isEmpty else {
            throw Failure(reason: "missing_candidate_identity")
        }
        guard !claimFingerprint.isEmpty,
              claimFingerprint == LocalExpressionContract.claimFingerprint(
                semanticKey: semanticKey,
                canonicalText: canonicalText
              ) else {
            throw Failure(reason: "claim_fingerprint_mismatch")
        }

        let rawEvidence = candidate["evidence"] as? [Any] ?? []
        let evidence = rawEvidence.compactMap(sanitizedEvidence)
        guard !evidence.isEmpty else { throw Failure(reason: "missing_evidence") }
        guard evidence.count == rawEvidence.count else { throw Failure(reason: "invalid_evidence_reference") }

        let currentFactId = trimmedString(currentFact["id"])
        if evidence.contains(where: { $0.kind == "current_fact" }),
           currentFactId.isEmpty || currentFactId == "current_fact" {
            throw Failure(reason: "missing_current_fact_identity")
        }
        let recentIds = Set(recentFacts.compactMap { $0["id"] as? String })
        let memoryKeys = Set(memoryFacts.compactMap { $0["key"] as? String })
        for item in evidence {
            if item.kind == "local_memory" {
                guard item.source == "local_memory", memoryKeys.contains(item.reference) else {
                    throw Failure(reason: "unsupported_evidence_reference")
                }
            } else {
                guard item.source == "local_record" else {
                    throw Failure(reason: "unsupported_evidence_reference")
                }
                if item.kind == "current_fact" {
                    guard item.reference == currentFactId else {
                        throw Failure(reason: "unsupported_evidence_reference")
                    }
                } else {
                    guard recentIds.contains(item.reference) else {
                        throw Failure(reason: "unsupported_evidence_reference")
                    }
                }
            }
        }

        let rawNumberFacts = candidate["number_facts"]
        if let rawNumberFacts, !(rawNumberFacts is [Any]) {
            throw Failure(reason: "invalid_number_facts")
        }
        let numbers = numberArray(candidate["numbers"])
        let countNumbers = numberArray(candidate["count_numbers"])
        guard numbers.valid, countNumbers.valid else {
            throw Failure(reason: "invalid_number_array")
        }

        var numberFacts: [NumberFact] = []
        if let raw = rawNumberFacts as? [Any] {
            for item in raw {
                guard let object = item as? [String: Any],
                      let value = numericValue(object["value"]),
                      let role = object["role"] as? String,
                      ["count", "measure"].contains(role),
                      let rawNumberEvidence = object["evidence"] as? [Any] else {
                    throw Failure(reason: "invalid_number_facts")
                }
                let numberEvidence = rawNumberEvidence.compactMap(sanitizedEvidence)
                guard !numberEvidence.isEmpty, numberEvidence.count == rawNumberEvidence.count else {
                    throw Failure(reason: "invalid_number_facts")
                }
                numberFacts.append(NumberFact(value: value, role: role, evidence: numberEvidence))
            }
            guard numberFacts.count == raw.count else { throw Failure(reason: "invalid_number_facts") }
        }
        if (numbers.present || countNumbers.present) && rawNumberFacts == nil {
            throw Failure(reason: "missing_number_facts")
        }
        if numbers.present {
            for value in numbers.values where !numberFacts.contains(where: { abs($0.value - value) < 1e-9 }) {
                throw Failure(reason: "number_without_provenance")
            }
        }
        if countNumbers.present {
            for value in countNumbers.values where !numberFacts.contains(where: {
                $0.role == "count" && abs($0.value - value) < 1e-9
            }) {
                throw Failure(reason: "count_without_provenance")
            }
        }
        for fact in numberFacts {
            for reference in fact.evidence {
                guard evidence.contains(where: {
                    $0.kind == reference.kind
                        && $0.source == reference.source
                        && $0.reference == reference.reference
                        && $0.field == reference.field
                }) else {
                    throw Failure(reason: "number_evidence_not_in_candidate")
                }
            }
        }
        for fact in numberFacts {
            for reference in fact.evidence {
                guard let actual = evidenceValue(
                    reference,
                    currentFact: currentFact,
                    recentFacts: recentFacts,
                    memoryFacts: memoryFacts
                ), abs(actual - fact.value) < 1e-9 else {
                    throw Failure(reason: "number_value_mismatch")
                }
            }
        }
    }

    private static func trimmedString(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func sanitizedEvidence(_ value: Any) -> Evidence? {
        guard let object = value as? [String: Any],
              let kind = object["kind"] as? String,
              ["current_fact", "recent_fact", "local_memory"].contains(kind),
              let source = object["source"] as? String,
              ["local_record", "local_memory"].contains(source),
              let reference = object["reference"] as? String,
              !reference.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let field: String?
        if object["field"] == nil || object["field"] is NSNull {
            field = nil
        } else if let raw = object["field"] as? String {
            let normalized = raw.trimmingCharacters(in: .whitespaces)
            field = normalized.isEmpty ? nil : normalized
        } else {
            return nil
        }
        return Evidence(
            kind: kind,
            source: source,
            reference: reference.trimmingCharacters(in: .whitespaces),
            field: field
        )
    }

    private static func numericValue(_ value: Any?) -> Double? {
        guard let value, !(value is NSNull) else { return nil }
        if value is Bool { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String,
           let parsed = Double(string.trimmingCharacters(in: .whitespaces)),
           parsed.isFinite {
            return parsed
        }
        return nil
    }

    private struct NumberArray {
        let present: Bool
        let values: [Double]
        let valid: Bool
    }

    private static func numberArray(_ value: Any?) -> NumberArray {
        guard let value else { return NumberArray(present: false, values: [], valid: true) }
        guard let array = value as? [Any] else { return NumberArray(present: true, values: [], valid: false) }
        var values: [Double] = []
        var valid = true
        for item in array {
            let resolved: Double?
            if let object = item as? [String: Any] {
                resolved = numericValue(object["value"])
            } else {
                resolved = numericValue(item)
            }
            if let resolved {
                values.append(resolved)
            } else {
                valid = false
            }
        }
        return NumberArray(present: true, values: values, valid: valid)
    }

    private static func numericFieldValue(_ value: [String: Any]?, field: String?) -> Double? {
        guard let value else { return nil }
        guard let field else { return numericValue(value) }
        if let direct = numericValue(value[field]) { return direct }
        if let payload = value["payload_json"] as? [String: Any],
           let nested = numericValue(payload[field]) {
            return nested
        }
        if let payload = value["payload"] as? [String: Any],
           let nested = numericValue(payload[field]) {
            return nested
        }
        return nil
    }

    private static func evidenceValue(
        _ reference: Evidence,
        currentFact: [String: Any],
        recentFacts: [[String: Any]],
        memoryFacts: [[String: Any]]
    ) -> Double? {
        switch (reference.kind, reference.source) {
        case ("current_fact", "local_record"):
            return numericFieldValue(currentFact, field: reference.field)
        case ("recent_fact", "local_record"):
            let fact = recentFacts.first { $0["id"] as? String == reference.reference }
            return numericFieldValue(fact, field: reference.field)
        case ("local_memory", "local_memory"):
            let memory = memoryFacts.first { $0["key"] as? String == reference.reference }
            return numericFieldValue(memory, field: reference.field)
        default:
            return nil
        }
    }
}
