import Foundation
import XCTest
@testable import SnapCount

final class LocalExpressionContextTests: XCTestCase {
    func testHighConfidenceMemoryCanLeadCandidateSelection() throws {
        let fact = LocalExpressionFact(
            id: "fact-1", domainKey: "food", title: "晚餐", summary: "清淡",
            recordDate: "2026-11-10", recordTime: nil, amount: nil, category: nil
        )
        let context = "{\"facts\":[{\"key\":\"food.preference\",\"value\":\"晚餐偏清淡\",\"confidence\":0.9}]}"
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
