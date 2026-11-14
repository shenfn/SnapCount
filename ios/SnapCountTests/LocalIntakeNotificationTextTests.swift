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
        XCTAssertEqual(output, [
            "这笔咖啡记下了",
            "💸 -¥12.00 · 星巴克 · 餐饮",
            "今日尚无支出记录"
        ])
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
        XCTAssertEqual(output.count, 5)
        XCTAssertEqual(output[3], "💸 -¥12.00 · 星巴克 · 餐饮")
        XCTAssertEqual(output[4], "今日尚无支出记录")
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
        XCTAssertEqual(output, [
            "💸 -¥12.00 · 星巴克 · 餐饮",
            "今日尚无支出记录"
        ])
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

extension LocalIntakeNotificationTextTests {
    func testSharedCompositionKeepsCompanionAndFixedFactsAcrossAppStateAndShortcut() throws {
        let native = try feedback(emotion: "这笔已记下。", utility: "今天继续稳住。")
        let shortcut = ShortcutAIFeedback(
            icon: native.icon,
            badge: native.badge,
            confidence: 0.92,
            emotionLine: native.emotionLine,
            utilityLine: native.utilityLine,
            detailReason: nil
        )
        let base = "💸 -¥12.00 · 星巴克 · 餐饮\n今日尚无支出记录"
        let appStateText = LocalIntakeNotificationText.compose(
            baseText: base,
            companionMessage: "这笔咖啡记下了",
            feedback: LocalIntakeNotificationFeedback(native)
        )
        let shortcutText = LocalIntakeNotificationText.compose(
            baseText: base,
            companionMessage: "这笔咖啡记下了",
            feedback: LocalIntakeNotificationFeedback(shortcut)
        )
        let shortcutResultText = ShortcutUploadResult.expandedDisplayText(
            baseText: base,
            companionMessage: "这笔咖啡记下了",
            feedback: shortcut
        )
        XCTAssertEqual(appStateText, shortcutText)
        XCTAssertEqual(appStateText, shortcutResultText)
        XCTAssertEqual(appStateText, "这笔咖啡记下了\n💸 -¥12.00 · 星巴克 · 餐饮\n今日尚无支出记录")
        XCTAssertFalse(appStateText.contains("这笔已记下。"))
    }

    func testSharedCompositionFallsBackWhenFeedbackIsLowConfidence() throws {
        let lowConfidence = LocalIntakeNotificationFeedback(
            icon: "✨",
            badge: "今天很稳",
            confidence: 0.49,
            emotionLine: "不应显示",
            utilityLine: "也不应显示"
        )
        let text = LocalIntakeNotificationText.compose(
            baseText: "⚠️ -¥25.00 · 便利店 · 请打开 App 补全",
            companionMessage: nil,
            feedback: lowConfidence
        )
        XCTAssertEqual(text, "⚠️ -¥25.00 · 便利店 · 请打开 App 补全")
    }

    func testSharedCompositionDeDuplicatesCompanionEmotionAndFacts() throws {
        let feedback = LocalIntakeNotificationFeedback(
            icon: "✨",
            badge: "今天很稳",
            confidence: 0.9,
            emotionLine: "这笔咖啡记下了",
            utilityLine: "今日尚无支出记录"
        )
        let text = LocalIntakeNotificationText.compose(
            baseText: "💸 -¥12.00 · 星巴克 · 餐饮\n今日尚无支出记录",
            companionMessage: "这笔咖啡记下了",
            feedback: feedback
        )
        XCTAssertEqual(text, "这笔咖啡记下了\n💸 -¥12.00 · 星巴克 · 餐饮\n今日尚无支出记录")
        XCTAssertEqual(text.components(separatedBy: "\n").count, 3)
    }

    func testSharedCompositionPreservesFailureAndPendingBaseWording() {
        let failure = LocalIntakeNotificationText.compose(
            baseText: "识别失败，请重试",
            companionMessage: "不应覆盖失败结果",
            feedback: nil
        )
        XCTAssertEqual(failure, "不应覆盖失败结果\n识别失败，请重试")

        let pending = LocalIntakeNotificationText.compose(
            baseText: "⚠️ -¥25.00 · 便利店 · 请打开 App 补全",
            companionMessage: nil,
            feedback: nil
        )
        XCTAssertEqual(pending, "⚠️ -¥25.00 · 便利店 · 请打开 App 补全")
    }

    func testShortcutNotificationBodyRetainsLineBreaksWithinBudget() {
        let base = String(repeating: "事实", count: 90)
        let result = ShortcutUploadResult(
            displayText: base,
            notificationText: "第一行\n第二行\n\(base)",
            route: "records"
        )
        XCTAssertLessThanOrEqual(result.notificationBody.count, 160)
        XCTAssertTrue(result.notificationBody.contains("\n"))
    }
}
