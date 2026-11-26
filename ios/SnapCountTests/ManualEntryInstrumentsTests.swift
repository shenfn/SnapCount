import XCTest
@testable import SnapCount

final class ManualEntryInstrumentsTests: XCTestCase {

    // MARK: - JieziKeypadAmountEngine

    func testKeypadDigitInputAndLeadingZeroReplacement() {
        var text = ""
        text = JieziKeypadAmountEngine.apply(.digit(0), to: text, replacingFresh: false).text
        XCTAssertEqual(text, "0")
        text = JieziKeypadAmountEngine.apply(.digit(0), to: text, replacingFresh: false).text
        XCTAssertEqual(text, "0", "重复前导零应被吞掉")
        text = JieziKeypadAmountEngine.apply(.digit(5), to: text, replacingFresh: false).text
        XCTAssertEqual(text, "5", "前导零后输入非零数字应直接替换")
        text = JieziKeypadAmountEngine.apply(.digit(8), to: text, replacingFresh: false).text
        XCTAssertEqual(text, "58")

        let replaced = JieziKeypadAmountEngine.apply(.digit(3), to: text, replacingFresh: true)
        XCTAssertEqual(replaced.text, "3", "fresh 状态下输入数字应替换原值")
        XCTAssertFalse(replaced.isFresh)
    }

    func testKeypadDecimalGuardSingleDotAndMaxTwoFractionalDigits() {
        var text = ""
        text = JieziKeypadAmountEngine.apply(.decimal, to: text, replacingFresh: false).text
        XCTAssertEqual(text, "0.", "空输入按小数点应自动补 0.")
        text = JieziKeypadAmountEngine.apply(.decimal, to: text, replacingFresh: false).text
        XCTAssertEqual(text, "0.", "重复小数点应被忽略")
        text = JieziKeypadAmountEngine.apply(.digit(5), to: text, replacingFresh: false).text
        text = JieziKeypadAmountEngine.apply(.digit(9), to: text, replacingFresh: false).text
        text = JieziKeypadAmountEngine.apply(.digit(9), to: text, replacingFresh: false).text
        XCTAssertEqual(text, "0.59", "最多保留两位小数")
    }

    func testKeypadIntegerLengthCapAndSanitization() {
        var text = "123456abc"
        text = JieziKeypadAmountEngine.apply(.digit(7), to: text, replacingFresh: false).text
        XCTAssertEqual(text, "123456", "整数部分最多 6 位且应清洗脏字符")
        text = JieziKeypadAmountEngine.apply(.decimal, to: text, replacingFresh: false).text
        text = JieziKeypadAmountEngine.apply(.digit(5), to: text, replacingFresh: false).text
        XCTAssertEqual(text, "123456.5")
        text = JieziKeypadAmountEngine.apply(.backspace, to: text, replacingFresh: false).text
        XCTAssertEqual(text, "123456.")
        text = JieziKeypadAmountEngine.apply(.clear, to: text, replacingFresh: false).text
        XCTAssertEqual(text, "")
        XCTAssertEqual(JieziKeypadAmountEngine.sanitize("12,50"), "12.50")
    }

    // MARK: - JieziSleepRibbonMath

    func testSleepRibbonClampRangeEnforcesNonCrossingAndMinimumDuration() {
        let normal = JieziSleepRibbonMath.clampRange(bed: 210, wake: 675)
        XCTAssertEqual(normal.bed, 210)
        XCTAssertEqual(normal.wake, 675)

        let crossed = JieziSleepRibbonMath.clampRange(bed: 500, wake: 480)
        XCTAssertGreaterThanOrEqual(crossed.wake - crossed.bed, JieziSleepRibbonMath.minimumDurationMinutes)

        let outOfBounds = JieziSleepRibbonMath.clampRange(bed: -100, wake: 5000)
        XCTAssertGreaterThanOrEqual(outOfBounds.bed, 0)
        XCTAssertLessThanOrEqual(outOfBounds.wake, JieziSleepRibbonMath.spanMinutes)
    }

    func testSleepRibbonSnappedOffsetHandlesZeroAndNaNWidthSafely() {
        XCTAssertEqual(JieziSleepRibbonMath.snappedOffset(for: 100, width: 0), 0)
        XCTAssertEqual(JieziSleepRibbonMath.snappedOffset(for: 100, width: -10), 0)
        XCTAssertEqual(JieziSleepRibbonMath.snappedOffset(for: .nan, width: 300), 0)
        XCTAssertEqual(JieziSleepRibbonMath.snappedOffset(for: .infinity, width: 300), 0)
        XCTAssertEqual(JieziSleepRibbonMath.snappedOffset(for: 150, width: 300), 480)
    }

    func testSleepRibbonIsoTimestampsAcrossMidnightAndSameDay() {
        // 23:30 (210) -> 07:15 (675) on wake date 2026-04-12 => start 2026-04-11T23:30:00+08:00, wake 2026-04-12T07:15:00+08:00
        let acrossMidnight = JieziSleepRibbonMath.isoTimestamps(
            dateKey: "2026-04-12",
            bedOffset: 210,
            wakeOffset: 675
        )
        XCTAssertEqual(acrossMidnight.startISO, "2026-04-11T23:30:00+08:00")
        XCTAssertEqual(acrossMidnight.wakeISO, "2026-04-12T07:15:00+08:00")
        XCTAssertEqual(acrossMidnight.durationMinutes, 465)

        // 01:00 (300) -> 08:00 (720) on wake date 2026-04-12 => both on 2026-04-12
        let sameDay = JieziSleepRibbonMath.isoTimestamps(
            dateKey: "2026-04-12",
            bedOffset: 300,
            wakeOffset: 720
        )
        XCTAssertEqual(sameDay.startISO, "2026-04-12T01:00:00+08:00")
        XCTAssertEqual(sameDay.wakeISO, "2026-04-12T08:00:00+08:00")
        XCTAssertEqual(sameDay.durationMinutes, 420)
    }

    // MARK: - NativeManualRecordDraft Sleep Payload

    func testSleepDraftUniversalPayloadRespectsTimeRangeToggle() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let targetDate = formatter.date(from: "2026-04-12")!

        // 1. Default (sleepUsesTimeRange == false) preserves explicit primaryValueText
        var durationOnlyDraft = NativeManualRecordDraft(kind: .universal, domainKey: "sleep")
        durationOnlyDraft.date = targetDate
        durationOnlyDraft.primaryValueText = "390"
        durationOnlyDraft.dimension = "良好"
        let durationPayload = durationOnlyDraft.universalPayload(domain: nil)
        XCTAssertEqual(durationPayload.double("sleep_minutes"), 390)
        XCTAssertNil(durationPayload.string("sleep_start_at"))
        XCTAssertNil(durationPayload.string("wake_at"))

        // 2. When sleepUsesTimeRange == true, emits sleep_start_at, wake_at, and computed sleep_minutes
        var rangeDraft = NativeManualRecordDraft(kind: .universal, domainKey: "sleep")
        rangeDraft.date = targetDate
        rangeDraft.sleepUsesTimeRange = true
        rangeDraft.sleepBedOffsetMinutes = 210  // 23:30
        rangeDraft.sleepWakeOffsetMinutes = 675 // 07:15
        rangeDraft.primaryValueText = "465"
        rangeDraft.dimension = "很好"
        let rangePayload = rangeDraft.universalPayload(domain: nil)
        XCTAssertEqual(rangePayload.double("sleep_minutes"), 465)
        XCTAssertEqual(rangePayload.string("sleep_start_at"), "2026-04-11T23:30:00+08:00")
        XCTAssertEqual(rangePayload.string("wake_at"), "2026-04-12T07:15:00+08:00")
    }

    // MARK: - Expense Timeline Adaptive Domain & Ticks

    func testExpenseTimelineAdaptiveDomainZoomsForClusteredRecordsAndKeepsFullDayWhenWide() {
        func makeEntry(id: String, minute: Int) -> NativeTimelineEntry {
            NativeTimelineEntry(
                record: NativeDayRecord(
                    id: id, reference: "expense/\(id)", dateKey: "2026-04-12", kind: .expense,
                    domainKey: nil, title: "测试-\(id)", subtitle: "", value: "¥20.00", timeLabel: nil,
                    systemImage: "creditcard", status: "local"
                ),
                minute: minute
            )
        }

        // 集中于 12:05–12:12 -> 自动聚焦到至少 4 小时窗口，且不铺满 0...1440
        let clustered = [makeEntry(id: "a", minute: 725), makeEntry(id: "b", minute: 732)]
        let zoomedDomain = NativeExpenseTimelineSelection.adaptiveDomain(for: clustered)
        XCTAssertGreaterThan(zoomedDomain.lowerBound, 0)
        XCTAssertLessThan(zoomedDomain.upperBound, 1440)
        XCTAssertGreaterThanOrEqual(zoomedDomain.upperBound - zoomedDomain.lowerBound, 240)
        XCTAssertEqual(NativeExpenseTimelineSelection.tickMinutes(for: zoomedDomain).count, 5)

        // 跨度超过 10 小时 -> 维持全天 0...1440
        let wide = [makeEntry(id: "morning", minute: 480), makeEntry(id: "night", minute: 1260)]
        XCTAssertEqual(NativeExpenseTimelineSelection.adaptiveDomain(for: wide), 0...1440)
    }

    // MARK: - JieziFoodCalorieEstimator

    func testFoodCalorieEstimatorMatchesAliasParsesGramsAndClampsOverflow() {
        let chicken = JieziFoodCalorieEstimator.estimate(query: "鸡胸肉 150g")
        XCTAssertEqual(chicken?.item.id, "chicken_breast")
        XCTAssertEqual(chicken?.grams, 150)
        XCTAssertEqual(chicken?.estimatedKcal, 200)

        let latte = JieziFoodCalorieEstimator.estimate(query: "冰拿铁350ml")
        XCTAssertEqual(latte?.item.id, "latte")
        XCTAssertEqual(latte?.grams, 350)
        XCTAssertEqual(latte?.estimatedKcal, 182)

        let overflow = JieziFoodCalorieEstimator.estimate(query: "米饭", gramsOverride: 99_999)
        XCTAssertEqual(overflow?.grams, JieziFoodCalorieEstimator.maxGrams)
        XCTAssertNil(JieziFoodCalorieEstimator.estimate(query: "不存在的神秘料理XYZ"))
    }

    func testSameDayTimeSortKeyOrdersByEffectiveClockAcrossEventAndUploadTimes() {
        let labels = ["08:28", "上传 17:18", "上传 10:30", "12:41", nil]
        let sorted = labels.sorted { NativeLocalDate.listTimeSortKey($0) > NativeLocalDate.listTimeSortKey($1) }
        XCTAssertEqual(sorted, ["上传 17:18", "12:41", "上传 10:30", "08:28", nil])

        let afternoon = ISO8601DateFormatter().date(from: "2026-11-25T17:18:00+08:00")!
        let morningKey = NativeLocalDate.effectiveClockSortKey(recordTime: "08:28", fallbackDate: afternoon)
        let fallbackKey = NativeLocalDate.effectiveClockSortKey(recordTime: nil, fallbackDate: afternoon)
        XCTAssertEqual(morningKey, "08:28")
        XCTAssertEqual(fallbackKey, "17:18")
        XCTAssertGreaterThan(fallbackKey, morningKey)
    }
}
