import Foundation
import XCTest
@testable import SnapCount

final class LocalExpressionContextTests: XCTestCase {
    func testCrossRecordExpenseRepeatCarriesBoundedEvidenceAndNumberProvenance() throws {
        let current = LocalExpressionFact(
            id: "expense-current", domainKey: "expense", title: "便利店", summary: "日用",
            recordDate: "2026-11-14", recordTime: nil, amount: 12.8, category: "日用"
        )
        let recent = (0..<20).map { index in
            LocalExpressionFact(
                id: "expense-\(index)", domainKey: "expense", title: "便利店", summary: "日用",
                recordDate: "2026-11-\(String(format: "%02d", max(1, 14 - index)))", recordTime: nil,
                amount: Double(index + 1), category: "日用"
            )
        }
        let repeatCandidate = try XCTUnwrap(
            LocalPlannerCandidateEngine.candidates(for: current, recentFacts: recent)
                .first(where: { $0.dimension == "repeat_pattern" })
        )
        XCTAssertEqual(repeatCandidate.evidence.filter { $0.kind == "recent_fact" }.count, 7)
        XCTAssertTrue(repeatCandidate.numberFacts.contains { $0.value == 12.8 && $0.evidence.first?.reference == current.id })
        XCTAssertTrue(LocalExpressionContract.validates(
            candidate: repeatCandidate,
            currentFactID: current.id,
            recentFactIDs: Set(recent.prefix(7).map(\.id))
        ))
    }

    func testStructuredDomainsProduceBoundedContinuityOnlyWithFormalHistory() {
        for domain in ["food", "sleep", "sport", "reading"] {
            let current = LocalExpressionFact(
                id: "\(domain)-current", domainKey: domain, title: domain, summary: "",
                recordDate: "2026-11-14", recordTime: nil, amount: nil, category: nil
            )
            let recent = LocalExpressionFact(
                id: "\(domain)-recent", domainKey: domain, title: domain, summary: "",
                recordDate: "2026-11-13", recordTime: nil, amount: nil, category: nil
            )
            let candidates = LocalPlannerCandidateEngine.candidates(for: current, recentFacts: [recent])
            let continuity = candidates.first { $0.dimension == "continuity" }
            XCTAssertNotNil(continuity)
            XCTAssertLessThanOrEqual(continuity?.evidence.count ?? .max, LocalPlannerCandidateEngine.maxCandidateEvidence)
            // A derived count cannot be resolved to a single fact field by
            // Edge's numericFieldValue, so it must not carry a number fact.
            XCTAssertEqual(continuity?.numberFacts.count, 0)
        }
    }

    func testNoHistoryReturnsCurrentCandidateOnly() {
        let fact = LocalExpressionFact(
            id: "no-history", domainKey: "sport", title: "运动", summary: "",
            recordDate: "2026-11-14", recordTime: nil, amount: nil, category: nil
        )
        XCTAssertEqual(LocalPlannerCandidateEngine.candidates(for: fact).map(\.dimension), ["current_fact"])
    }

    func testFactReaderIncludesActiveWalletHistoryAndExcludesPendingStaging() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profile = try LocalProfileStore(database: database).activeProfile()
        let wallet = try LocalWalletSnapshotRepository(database: database).create(LocalWalletSnapshotDraft(
            id: UUID(), profileID: profile.id, title: "现金账户", summary: "余额",
            payloadJSON: "{}", recordDate: "2026-11-14", recordTime: nil, occurredAt: nil,
            balanceMinor: 12_300, currency: "CNY", kind: .asset, imagePath: nil, imageHash: nil,
            createdAt: Date()
        ))
        let stagingID = UUID().uuidString
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO local_staging_records (
                    id, profile_id, domain_key, status, confidence, title, summary, payload_json,
                    record_date, record_time, image_path, image_hash, created_at, updated_at,
                    target_record_id, resolved_action, resolved_at, source_kind, domain_version,
                    evidence_json, missing_fields_json
                ) VALUES (?, ?, 'wallet', 'pending_review', 0.8, '待确认钱包', '候选', '{}',
                          '2026-11-14', NULL, NULL, NULL, ?, ?, NULL, NULL, NULL,
                          'ai_candidate', 1, '[]', '[]')
                """, arguments: [stagingID, profile.id.uuidString, Date(), Date()])
        }
        let facts = try LocalFactReader(database: database).range(
            profileID: profile.id, from: "2026-11-01", to: "2026-11-30"
        ).facts
        XCTAssertTrue(facts.contains { $0.id == wallet.id && $0.domainKey == "wallet" })
        XCTAssertFalse(facts.contains { $0.id.uuidString == stagingID })
    }

    func testCompositionContextPopulatesRecentFormalFactsWithMemoryOff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let older = try repository.createExpense(LocalExpenseDraft(
            id: UUID(), profileID: profile.id, accountID: nil, amountMinor: 800,
            currency: "CNY", merchantName: "便利店", platform: "", category: "日用",
            paymentMethod: "cash", transactionDate: "2026-11-13", transactionTime: nil,
            note: nil, createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        ), operationID: UUID())
        let current = try repository.createExpense(LocalExpenseDraft(
            id: UUID(), profileID: profile.id, accountID: nil, amountMinor: 1280,
            currency: "CNY", merchantName: "便利店", platform: "", category: "日用",
            paymentMethod: "cash", transactionDate: "2026-11-14", transactionTime: nil,
            note: nil, createdAt: Date(timeIntervalSince1970: 1_800_000_100)
        ), operationID: UUID())
        var settings = NativeUserSettings()
        settings.companionMemoryEnabled = false
        let persistence = LocalExpressionPersistence(
            database: database,
            settingsProvider: { LocalExpressionSettings(companionEnabled: true, memoryEnabled: false) }
        )
        let context = try XCTUnwrap(persistence.makeCompositionContext(
            for: LocalExpenseReadModel.detail(from: current), profileID: profile.id,
            settings: settings, providerMode: .deterministic,
            now: ISO8601DateFormatter().date(from: "2026-11-14T12:00:00Z")!
        ))
        XCTAssertEqual(context.recentFacts.map(\.id), [older.id.uuidString])
        XCTAssertNil(context.memoryContextJSON)
        XCTAssertTrue(context.plannerCandidates.contains { $0.dimension == "repeat_pattern" })
    }

    func testLOCALAI003ContractKeepsEvidenceAndNumbersBoundToCandidateDimension() throws {
        let fact = LocalExpressionFact(
            id: "fact-contract-1", domainKey: "expense", title: "便利店", summary: "日常用品",
            recordDate: "2026-11-14", recordTime: "10:00", amount: 12.8, category: "日用"
        )
        let candidates = LocalPlannerCandidateEngine.candidates(for: fact, memoryContextJSON: #"{"facts":[{"key":"local_ai.expense.recent_30d","value":"近30天有12条消费记录","confidence":0.9,"entity_type":"merchant","entity_value":"便利店"}]}"#)
        let current = try XCTUnwrap(candidates.first)
        let memory = try XCTUnwrap(candidates.first(where: { $0.dimension == "memory_context" }))
        let currentPayload = try XCTUnwrap(HostedAICompanionProvider.plannerPayload(current, fact: fact))
        let memoryPayload = try XCTUnwrap(HostedAICompanionProvider.plannerPayload(memory, fact: fact))
        let currentEvidence = try XCTUnwrap(currentPayload["evidence"] as? [[String: Any]])
        XCTAssertEqual(currentEvidence.first?["reference"] as? String, fact.id)
        XCTAssertEqual(((currentPayload["number_facts"] as? [[String: Any]])?.first?["value"] as? NSNumber)?.doubleValue, 12.8)
        XCTAssertTrue((memoryPayload["numbers"] as? [Double] ?? []).isEmpty)
        XCTAssertTrue((memoryPayload["number_facts"] as? [[String: Any]] ?? []).isEmpty)
        XCTAssertEqual(current.claimFingerprint, "fnv1a64:510d871ebff57f0f")
        XCTAssertTrue(LocalExpressionContract.validates(candidate: current, currentFactID: fact.id))
        XCTAssertEqual(current.claimFingerprint, LocalPlannerCandidateEngine.candidates(for: fact).first?.claimFingerprint)
    }

    func testCrossEndGoldenFingerprintMatchesEdgeFixture() {
        XCTAssertEqual(
            LocalExpressionContract.claimFingerprint(
                semanticKey: "local_expense_current_fact",
                canonicalText: "这笔便利店消费已记录，金额为¥12.80。"
            ),
            "fnv1a64:510d871ebff57f0f"
        )
    }

    func testEveryProducedCandidateMeetsEdgeBoundsAndProvenance() throws {
        let current = LocalExpressionFact(
            id: "expense-current", domainKey: "expense", title: "便利店", summary: "日用",
            recordDate: "2026-11-14", recordTime: nil, amount: 12.8, category: "日用"
        )
        let recent = (0..<12).map { index in
            LocalExpressionFact(
                id: "expense-recent-\(index)", domainKey: "expense", title: "便利店", summary: "日用",
                recordDate: "2026-11-\(String(format: "%02d", 13 - index))", recordTime: nil,
                amount: Double(index + 1), category: "日用"
            )
        }
        let memoryJSON = #"{"facts":[{"key":"local_ai.expense.merchant_repeat","type":"merchant_pattern","confidence":0.9,"value":"近30天在「便利店」有重复消费记录。","entity_type":"merchant","entity_value":"便利店"}]}"#
        let candidates = LocalPlannerCandidateEngine.candidates(
            for: current,
            recentFacts: recent,
            memoryContextJSON: memoryJSON
        )
        XCTAssertEqual(
            Set(candidates.map(\.dimension)),
            ["current_fact", "repeat_pattern", "continuity", "memory_context"]
        )

        let currentPayload = HostedAICompanionProvider.factPayload(current)
        let recentPayloads = recent.map(HostedAICompanionProvider.factPayload)
        let memoryObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(memoryJSON.utf8)) as? [String: Any]
        )
        let memoryFacts = try XCTUnwrap(memoryObject["facts"] as? [[String: Any]])

        for candidate in candidates {
            let payload = try XCTUnwrap(
                HostedAICompanionProvider.plannerPayload(candidate, fact: current),
                candidate.dimension
            )
            XCTAssertEqual(
                payload["canonical_text"] as? String,
                Optional(candidate.emotionLine),
                candidate.dimension
            )
            let evidence = try XCTUnwrap(payload["evidence"] as? [Any], candidate.dimension)
            XCTAssertLessThanOrEqual(
                evidence.count,
                LocalPlannerCandidateEngine.maxCandidateEvidence,
                candidate.dimension
            )
            let numberFacts = payload["number_facts"] as? [Any] ?? []
            XCTAssertLessThanOrEqual(
                numberFacts.count,
                LocalPlannerCandidateEngine.maxCandidateEvidence,
                candidate.dimension
            )
            XCTAssertNoThrow(
                try EdgePlannerValidatorMirror.validate(
                    payload,
                    currentFact: currentPayload,
                    recentFacts: recentPayloads,
                    memoryFacts: memoryFacts
                ),
                candidate.dimension
            )
        }
    }

    func testLOCALAI003ContractBoundsRecentFactEvidenceReferences() throws {
        let semanticKey = "expense_recent_amount"
        let text = "近期金额 8 元"
        let fingerprint = LocalExpressionContract.claimFingerprint(semanticKey: semanticKey, canonicalText: text)
        let payload: [String: AnyCodable] = [
            "candidate_id": AnyCodable("recent-candidate"),
            "semantic_key": AnyCodable(semanticKey),
            "canonical_text": AnyCodable(text),
            "claim_fingerprint": AnyCodable(fingerprint),
            "presentation_target": AnyCodable("feedback_card"),
            "dimension": AnyCodable("recent_fact"),
            "source": AnyCodable("expression_planner"),
            "emotion_line": AnyCodable(text),
            "evidence": AnyCodable([[
                "kind": "recent_fact", "source": "local_record", "reference": "fact-2", "field": "amount"
            ] as [String: Any]])
        ]
        let candidate = try XCTUnwrap(NativeAIFeedback(payload: payload))
        XCTAssertTrue(LocalExpressionContract.validates(
            candidate: candidate,
            currentFactID: "fact-1",
            recentFactIDs: ["fact-2"]
        ))
        XCTAssertFalse(LocalExpressionContract.validates(
            candidate: candidate,
            currentFactID: "fact-1",
            recentFactIDs: []
        ))
    }

    func testLOCALAI003FCompactMemoryIsSameDomainAndBounded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = LocalCompanionMemoryRepository(database: database)
        let now = Date()
        for index in 0..<10 {
            try repository.upsert(LocalCompanionMemoryDraft(
                id: UUID(), profileID: profile.id,
                memoryKey: "local_ai.expense.recent_\(index)", memoryType: "derived_trend",
                contentJSON: #"{"value":"同域摘要 \#(index)"}"#,
                sourceTable: nil, sourceID: nil, confidence: 0.9 - Double(index) / 100,
                createdAt: now, updatedAt: now
            ))
        }
        try repository.upsert(LocalCompanionMemoryDraft(
            id: UUID(), profileID: profile.id,
            memoryKey: "local_ai.food.recent_30d", memoryType: "derived_trend",
            contentJSON: #"{"value":"其他领域摘要"}"#,
            sourceTable: nil, sourceID: nil, confidence: 1,
            createdAt: now, updatedAt: now
        ))

        let json = try repository.compactContextJSON(profileID: profile.id, domainKey: "expense")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let facts = try XCTUnwrap(object["facts"] as? [[String: Any]])

        XCTAssertEqual(facts.count, 8)
        XCTAssertTrue(facts.allSatisfy { ($0["key"] as? String)?.hasPrefix("local_ai.expense.") == true })
        XCTAssertTrue(facts.allSatisfy { (($0["value"] as? String)?.count ?? 999) <= 240 })
    }

    func testHighConfidenceMemoryCanLeadCandidateSelection() throws {
        let fact = LocalExpressionFact(
            id: "fact-1", domainKey: "food", title: "晚餐", summary: "清淡",
            recordDate: "2026-11-10", recordTime: nil, amount: nil, category: nil
        )
        let context = "{\"facts\":[{\"key\":\"food.preference\",\"value\":\"晚餐偏清淡\",\"confidence\":0.9,\"entity_type\":\"merchant\",\"entity_value\":\"晚餐\"}]}"
        let selected = try XCTUnwrap(LocalPlannerCandidateEngine.selectedCandidate(for: fact, memoryContextJSON: context))
        XCTAssertEqual(selected.dimension, "memory_context")
        XCTAssertTrue(selected.emotionLine.contains("晚餐偏清淡"))
    }

    func testLowConfidenceMemoryKeepsCurrentFactAsDefault() throws {
        let fact = LocalExpressionFact(
            id: "fact-2", domainKey: "food", title: "午餐", summary: "米饭",
            recordDate: "2026-11-10", recordTime: nil, amount: nil, category: nil
        )
        let context = "{\"facts\":[{\"key\":\"food.preference\",\"value\":\"偏清淡\",\"confidence\":0.7}]}"
        let selected = try XCTUnwrap(LocalPlannerCandidateEngine.selectedCandidate(for: fact, memoryContextJSON: context))
        XCTAssertEqual(selected.dimension, "current_fact")
    }

    func testHistoryCandidateOutranksMemoryOnlyAngle() throws {
        let fact = LocalExpressionFact(
            id: "fact-history", domainKey: "expense", title: "小屁孩", summary: "生活",
            recordDate: "2026-11-14", recordTime: nil, amount: 150, category: "生活"
        )
        let recent = (0..<3).map { index in
            LocalExpressionFact(
                id: "recent-\(index)", domainKey: "expense", title: "其他商家", summary: "生活",
                recordDate: "2026-11-\(String(format: "%02d", 13 - index))", recordTime: nil,
                amount: Double(index + 10), category: "生活"
            )
        }
        let memory = #"{"facts":[{"key":"local_ai.expense.recent_30d","value":"近30天生活类多次出现","confidence":0.95,"entity_type":"category","entity_value":"生活"}]}"#
        let selected = try XCTUnwrap(LocalPlannerCandidateEngine.selectedCandidate(
            for: fact, recentFacts: recent, memoryContextJSON: memory
        ))
        XCTAssertEqual(selected.dimension, "continuity")
        XCTAssertGreaterThan(selected.evidence.count, 1)
    }

    func testProviderCompanionPersistsBesidePlannerFeedback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let expense = try repository.createExpense(LocalExpenseDraft(
            id: UUID(), profileID: profile.id, accountID: nil, amountMinor: 2_645,
            currency: "CNY", merchantName: "拼多多", platform: "", category: "日用",
            paymentMethod: "cash", transactionDate: "2026-11-10", transactionTime: nil,
            note: nil, createdAt: Date()
        ), operationID: UUID())
        let detail = LocalExpenseReadModel.detail(from: expense)
        let persistence = LocalExpressionPersistence(
            database: database,
            settingsProvider: { LocalExpressionSettings(companionEnabled: true, memoryEnabled: true) }
        )
        persistence.persist(companion: LocalCompanionResult(
            companionMessage: "这一笔也稳稳记下了。",
            aiFeedback: [
                "version": AnyCodable("feedback-v1"),
                "domain_key": AnyCodable("expense"),
                "source": AnyCodable("hybrid"),
                "emotion_line": AnyCodable("消费事实已经保存。")
            ]
        ), for: detail)

        let restored = try XCTUnwrap(try repository.expense(id: expense.id))
        XCTAssertEqual(restored.companionMessage, "这一笔也稳稳记下了。")
        XCTAssertTrue(restored.aiFeedbackJSON?.contains("消费事实已经保存") == true)
    }
}
