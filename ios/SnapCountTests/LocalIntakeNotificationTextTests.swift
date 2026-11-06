import XCTest
@testable import SnapCount

final class LocalIntakeNotificationTextTests: XCTestCase {
    private func feedback(
        icon: String = "✨",
        badge: String = "今天很稳",
        emotion: String,
        utility: String
    ) throws -> NativeAIFeedback {
        try XCTUnwrap(NativeAIFeedback(payload: [
            "icon": AnyCodable(icon),
            "badge": AnyCodable(badge),
            "emotion_line": AnyCodable(emotion),
            "utility_line": AnyCodable(utility)
        ]))
    }

    private func expenseInput(
        feedback: NativeAIFeedback? = nil,
        confidence: Double? = nil,
        companionMessage: String? = nil,
        amountMinor: Int64? = 1200,
        merchantName: String? = "星巴克",
        category: String? = "餐饮",
        todaySpendMinor: Int64 = 0,
        todaySpendCount: Int = 0,
        isPending: Bool = false
    ) -> LocalIntakeNotificationInput {
        LocalIntakeNotificationInput(
            domainKey: "expense",
            feedback: feedback,
            confidence: confidence,
            companionMessage: companionMessage,
            amountMinor: amountMinor,
            merchantName: merchantName,
            category: category,
            sourceName: nil,
            todaySpendMinor: todaySpendMinor,
            todaySpendCount: todaySpendCount,
            monthIncomeMinor: 0,
            isPending: isPending
        )
    }

    private func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    // 1
    func testCompanionMessageLeadsAndSkipsEmotionLine() throws {
        let modelFeedback = try feedback(emotion: "情绪句不应该出现在 companion 分支", utility: "实用句也不应该出现")
        let text = LocalIntakeNotificationText.compose(
            expenseInput(feedback: modelFeedback, confidence: 0.9, companionMessage: "这笔咖啡记下了")
        )

        let output = lines(text)
        XCTAssertEqual(output.first, "这笔咖啡记下了")
        XCTAssertFalse(text.contains("情绪句不应该出现在 companion 分支"))
        XCTAssertFalse(text.contains("实用句也不应该出现"))
        // companion 已经占据表达层，不再追加域兜底。
        XCTAssertEqual(output, ["这笔咖啡记下了"])
    }

    // 2
    func testFeedbackWithoutCompanionKeepsStructuredLines() throws {
        let modelFeedback = try feedback(emotion: "记录已经落下。", utility: "继续保持当前节奏。")
        let text = LocalIntakeNotificationText.compose(
            expenseInput(feedback: modelFeedback, confidence: 0.9)
        )

        let output = lines(text)
        XCTAssertEqual(output[0], "✨ 今天很稳")
        XCTAssertEqual(output[1], "记录已经落下。")
        XCTAssertEqual(output[2], "继续保持当前节奏。")
        // 结构化反馈存在时只显示反馈内容，域兜底仅在反馈缺失时使用。
        XCTAssertEqual(output.count, 3)
    }

    // 3
    func testPlainFallbackHasTwoExpenseLines() {
        let text = LocalIntakeNotificationText.compose(expenseInput())

        let output = lines(text)
        XCTAssertEqual(output.count, 2)
        XCTAssertTrue(output[0].hasPrefix("💸"))
        XCTAssertEqual(output[1], "今日尚无支出记录")
    }

    // 4
    func testLowConfidenceFallsBackToPlainCopy() throws {
        let modelFeedback = try feedback(emotion: "低置信度的情绪句", utility: "低置信度的实用句")
        let direct = LocalIntakeNotificationText.compose(expenseInput(feedback: modelFeedback, confidence: 0.49))
        let noFeedback = LocalIntakeNotificationText.compose(expenseInput(confidence: 0.49))

        XCTAssertEqual(direct, noFeedback)
        XCTAssertFalse(direct.contains("低置信度的情绪句"))
        XCTAssertEqual(lines(direct).count, 2)
    }

    // 5
    func testLongEmotionLineClipsAtBoundaryPunctuation() throws {
        let firstChunk = "今天天气很好所以我把这笔支出记录下来了"
        XCTAssertEqual(firstChunk.count, 19)
        let emotion = firstChunk + "，" + "然后继续走了一段路再回头看看自己的账单"
        XCTAssertGreaterThan(emotion.count, 34)

        let modelFeedback = try feedback(emotion: emotion, utility: "继续保持当前节奏。")
        let text = LocalIntakeNotificationText.compose(
            LocalIntakeNotificationInput(
                domainKey: "sleep",
                feedback: modelFeedback,
                confidence: 0.9,
                companionMessage: nil,
                amountMinor: nil,
                merchantName: nil,
                category: nil,
                sourceName: nil,
                todaySpendMinor: 0,
                todaySpendCount: 0,
                monthIncomeMinor: 0,
                isPending: false
            )
        )

        let clipped = lines(text)[1]
        XCTAssertEqual(clipped, firstChunk + "。")
        XCTAssertTrue(clipped.hasSuffix("。"))
        XCTAssertFalse(clipped.hasSuffix("…"))
    }

    // 6
    func testPunctuationTooEarlyFallsBackToHardCut() throws {
        let emotion = "好，" + String(repeating: "记", count: 40)
        let modelFeedback = try feedback(emotion: emotion, utility: "继续保持当前节奏。")
        let text = LocalIntakeNotificationText.compose(
            LocalIntakeNotificationInput(
                domainKey: "sleep",
                feedback: modelFeedback,
                confidence: 0.9,
                companionMessage: nil,
                amountMinor: nil,
                merchantName: nil,
                category: nil,
                sourceName: nil,
                todaySpendMinor: 0,
                todaySpendCount: 0,
                monthIncomeMinor: 0,
                isPending: false
            )
        )

        let clipped = lines(text)[1]
        XCTAssertEqual(clipped.count, 34)
        XCTAssertTrue(clipped.hasSuffix("…"))
        XCTAssertFalse(clipped.contains("。"))
    }

    // 7
    func testDuplicatedLinesAreCollapsed() {
        let text = LocalIntakeNotificationText.compose(
            expenseInput(companionMessage: "💸 -¥12.00 · 星巴克 · 餐饮")
        )

        let output = lines(text)
        XCTAssertEqual(output, ["💸 -¥12.00 · 星巴克 · 餐饮"])
    }

    // 8
    func testIncomeFallbackFormat() {
        let text = LocalIntakeNotificationText.compose(
            LocalIntakeNotificationInput(
                domainKey: "income",
                feedback: nil,
                confidence: nil,
                companionMessage: nil,
                amountMinor: 50000,
                merchantName: nil,
                category: nil,
                sourceName: "某某公司",
                todaySpendMinor: 0,
                todaySpendCount: 0,
                monthIncomeMinor: 1234500,
                isPending: false
            )
        )

        let output = lines(text)
        XCTAssertEqual(output, ["💰 +¥500.00 · 某某公司", "本月已入 ¥12345.00"])
    }

    // 9
    func testPendingExpenseAsksForCompletion() {
        let text = LocalIntakeNotificationText.compose(
            expenseInput(amountMinor: 2500, merchantName: "便利店", isPending: true)
        )

        let output = lines(text)
        XCTAssertEqual(output[0], "⚠️ -¥25.00 · 便利店 · 请打开 App 补全")
        XCTAssertFalse(output[0].contains("餐饮"))
    }

    // 10
    func testBuiltinDomainEmoji() {
        func plain(_ domainKey: String) -> String {
            LocalIntakeNotificationText.compose(
                LocalIntakeNotificationInput(
                    domainKey: domainKey,
                    feedback: nil,
                    confidence: nil,
                    companionMessage: nil,
                    amountMinor: nil,
                    merchantName: nil,
                    category: nil,
                    sourceName: nil,
                    todaySpendMinor: 0,
                    todaySpendCount: 0,
                    monthIncomeMinor: 0,
                    isPending: false
                )
            )
        }

        XCTAssertEqual(plain("sleep"), "🌙 已归档到睡眠记录")
        XCTAssertEqual(plain("sport"), "🏃 已归档到运动记录")
    }
}
