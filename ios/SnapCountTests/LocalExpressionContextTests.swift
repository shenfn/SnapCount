import Foundation
import XCTest
@testable import SnapCount

final class LocalExpressionContextTests: XCTestCase {
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
