import XCTest
@testable import SnapCount

final class IOSDomainBlocksTests: XCTestCase {
    func testIOSV2POLISH004FoodAverageIncludesExplicitZeroButNotMissingOrUnrecordedDays() throws {
        let zero = record("zero", date: "2026-10-05", domain: .food)
        let high = record("high", date: "2026-10-06", domain: .food)
        let missing = record("missing", date: "2026-10-08", domain: .food)
        let result = model(.food, date: "2026-10-08", records: [zero, high, missing], details: [
            zero.reference: detail(zero, ["total_calorie_kcal": AnyCodable(0)]),
            high.reference: detail(high, ["total_calorie_kcal": AnyCodable(800)])
        ])
        XCTAssertEqual(result.periodRecordCount, 3)
        XCTAssertEqual(result.validDayCount, 2)
        XCTAssertEqual(try XCTUnwrap(result.periodDailyAverage), 400, accuracy: 0.001)
        XCTAssertNil(result.periodTotal, "缺热量的一天不得以零计入完整累计")
        XCTAssertNil(result.highestMeal, "选中日没有可读取热量，不借用其他日最大一餐")
        let measuredDay = model(.food, date: "2026-10-06", records: [zero, high], details: [
            zero.reference: detail(zero, ["total_calorie_kcal": AnyCodable(0)]),
            high.reference: detail(high, ["total_calorie_kcal": AnyCodable(800)])
        ])
        XCTAssertEqual(measuredDay.highestMeal?.reference, high.reference)
    }

    func testIOSV2POLISH004FoodWeekIsNaturalWeekWhileSleepEndsOnSelectedDay() {
        XCTAssertEqual(NativeDomainScenePresentation.trendDateKeys(for: .food, dateKey: "2026-10-08"), [
            "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"
        ])
        XCTAssertEqual(NativeDomainScenePresentation.trendDateKeys(for: .sleep, dateKey: "2026-10-08").first, "2026-10-02")
    }

    func testIOSV2POLISH004SportAndReadingPeriodUseFormalRecordsInNaturalWeek() throws {
        for domain in [AppDomain.sport, .reading] {
            let key = domain == .sport ? "duration_minutes" : "reading_minutes"
            let prior = record("prior", date: "2026-10-04", domain: domain)
            let current = record("current", date: "2026-10-05", domain: domain)
            let next = record("next", date: "2026-10-06", domain: domain)
            let result = model(domain, records: [prior, current, next], details: [
                prior.reference: detail(prior, [key: AnyCodable(900)]),
                current.reference: detail(current, [key: AnyCodable(30), "sport_type": AnyCodable(" 散步 ")]),
                next.reference: detail(next, [key: AnyCodable(45)])
            ])
            XCTAssertEqual(result.periodRecordCount, 2)
            XCTAssertEqual(try XCTUnwrap(result.periodTotal), 75, accuracy: 0.001)
            if domain == .sport { XCTAssertEqual(result.periodTypes, ["散步", "类型未提供"]) }
        }
    }

    func testIOSV2POLISH003TimelineUsesEventTimeAndRetainsEqualTimeReferences() {
        let a = record("a", date: "2026-10-05", domain: .expense, time: "上传 11:00")
        let b = record("b", date: "2026-10-05", domain: .expense, time: "09:00")
        let upload = record("upload", date: "2026-10-05", domain: .expense, time: "上传 10:00")
        let invalid = record("bad", date: "2026-10-05", domain: .expense, time: "99:99")
        var actual = detail(a, [:])
        actual.occurredAt = "2026-10-05T01:00:00Z"
        let result = model(.expense, records: [b, upload, invalid, a], details: [a.reference: actual])
        XCTAssertEqual(result.timeline.map(\.minute), [540, 540])
        XCTAssertEqual(result.timeline.map(\.record.reference), [a.reference, b.reference])
        XCTAssertEqual(result.records.count, 4, "未知业务时间只退出时间线，正式记录仍可达")
    }

    func testIOSV2POLISH003ComparisonUsesPreviousDayAcrossMonthAndMissingAmountStaysUnknown() throws {
        let previous = record("previous", date: "2026-09-30", domain: .expense)
        let current = record("current", date: "2026-10-01", domain: .expense)
        let result = model(.expense, date: "2026-10-01", records: [previous, current], details: [:])
        XCTAssertEqual(try XCTUnwrap(result.previousExpenseTotal), 10, accuracy: 0.001)
        let missing = NativeDayRecord(id: "missing", reference: "expense/missing", dateKey: "2026-09-30",
            kind: .expense, domainKey: nil, title: "未填写", subtitle: "", value: "", timeLabel: nil, systemImage: "creditcard")
        XCTAssertNil(model(.expense, date: "2026-10-01", records: [missing, current], details: [:]).previousExpenseTotal)
    }

    func testIOSV2POLISH004SleepRangeCrossesMidnightAndNeverInfersRangeFromDuration() throws {
        let actual = record("actual", date: "2026-10-05", domain: .sleep)
        let durationOnly = record("duration", date: "2026-10-05", domain: .sleep)
        let reversed = record("reversed", date: "2026-10-05", domain: .sleep)
        let result = model(.sleep, records: [actual, durationOnly, reversed], details: [
            actual.reference: detail(actual, ["sleep_minutes": AnyCodable(480),
                "sleep_start_at": AnyCodable("2026-10-04T23:30:00+08:00"), "wake_at": AnyCodable("2026-10-05T07:30:00+08:00")]),
            durationOnly.reference: detail(durationOnly, ["sleep_minutes": AnyCodable(480)]),
            reversed.reference: detail(reversed, ["sleep_start_at": AnyCodable("2026-10-05T07:30:00+08:00"),
                "wake_at": AnyCodable("2026-10-04T23:30:00+08:00")])
        ])
        XCTAssertEqual(result.sleepRanges.map(\.id), [actual.reference])
        let interval = try XCTUnwrap(result.sleepRanges.first)
        XCTAssertEqual(interval.end.timeIntervalSince(interval.start), 8 * 3600, accuracy: 0.001)
    }

    private func record(_ id: String, date: String, domain: AppDomain, time: String? = nil) -> NativeDayRecord {
        NativeDayRecord(id: id, reference: "\(domain == .expense ? "expense" : "data")/\(id)", dateKey: date,
            kind: domain == .expense ? .expense : domain == .food ? .food : domain == .sleep ? .sleep : domain == .sport ? .sport : .reading,
            domainKey: domain.rawValue, title: id, subtitle: "", value: domain == .expense ? "¥10.00" : "",
            timeLabel: time, systemImage: "circle", status: "done")
    }

    private func detail(_ record: NativeDayRecord, _ payload: [String: AnyCodable]) -> NativeRecordDetail {
        NativeRecordDetail(id: record.reference, rawId: record.id, kind: "data", title: record.title,
            subtitle: "", value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil,
            imageHash: nil, amount: nil, merchantName: nil, platform: nil, category: nil, paymentMethod: nil,
            recordDate: record.dateKey, note: nil, companionMessage: nil, accountId: nil,
            systemImage: "circle", payload: payload, domainKey: record.domainKey)
    }

    private func model(_ domain: AppDomain, date: String = "2026-10-05", records: [NativeDayRecord],
        details: [String: NativeRecordDetail]) -> NativeDomainScenePresentation {
        NativeDomainScenePresentation.make(domain: domain, dateKey: date,
            weekGroups: Dictionary(grouping: records, by: \.dateKey).map { NativeDayRecordGroup(dateKey: $0.key, records: $0.value) },
            details: details, isSignedIn: false, isLoading: false, errorMessage: nil, todayKey: "2026-10-17")
    }
}
